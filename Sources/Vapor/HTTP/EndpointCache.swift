import Foundation
import NIOCore
import Logging
import NIOHTTP1

public enum EndpointCacheError: Swift.Error {
    case unexpctedResponseStatus(HTTPStatus, uri: URI)
    case contentDecodeFailure(Error)
}

/// Handles the complexities of HTTP caching.
public actor EndpointCache<T>: Sendable where T: Decodable & Sendable {
    private var cached: (T?, Date?)
    private var request: T?
    private var headers: HTTPHeaders?
    private let uri: URI
    
    /// The designated initializer.
    /// - Parameters:
    ///   - uri: The `URI` of the resource to be downloaded.
    public init(uri: URI) {
        self.uri = uri
        self.request = nil
        self.headers = nil
        self.cached = (nil, nil)
    }
    
    /// Downloads the resource.
    /// - Parameters:
    ///   - request: The `Request` which is initiating the download.
    ///   - logger: An optional logger
    public func get(on request: Request, logger: Logger? = nil) async throws -> T {
        return try await self.download(on: request.eventLoop, using: request.client, logger: logger ?? request.logger)
    }
    
    /// Downloads the resource.
    /// - Parameters:
    ///   - eventLoop: The `EventLoop` to use for the download.
    ///   - client: The `Client` which will perform the download.
    ///   - logger: `Logger` to output to
    public func get(using client: Client, logger: Logger, on eventLoop: EventLoop) async throws -> T {
        if let cachedData = self.cached.0, let cacheUntil = self.cached.1, Date() < cacheUntil {
            // If no-cache was set on the header, you *always* have to validate with the server.
            // must-revalidate does not require checking with the server until after it expires.
            let cachedHeaders = self.headers
            if cachedHeaders == nil || cachedHeaders?.cacheControl == nil || cachedHeaders?.cacheControl?.noCache == false {
                return cachedData
            }
        }
        
        // Don't make a new request if one is already running.
        if let request {
            return request
        }
        
        logger.trace("Encpoint cache, requesting data", metadata: ["url": "\(self.uri)"])
        
        let request = try await self.download(on: eventLoop, using: client, logger: logger)
        // Once the request finishes, clear the current request and return the data.
        self.request = nil
        
        return request
    }
    
    private func download(on eventLoop: EventLoop, using client: Client, logger: Logger) async throws -> T {
        // https://www.w3.org/Protocols/rfc2616/rfc2616-sec13.html#sec13.3.4
        var headers: HTTPHeaders = [:]
        if let eTag = self.headers?.first(name: .eTag) {
            headers.add(name: .ifNoneMatch, value: eTag)
        }
        if let lastModified = self.headers?.lastModified {
            // TODO: If using HTTP/1.0 then this should be .ifUnmodifiedSince instead. Don't know
            // how to determine that right now.
            headers.add(name: .ifModifiedSince, value: lastModified.serialize())
        }
        
        // Cache-Control max-age is calculated against the request date.
        let requestSentAt = Date()
        
        let response = try await client.get(self.uri, headers: headers)
        if !(response.status == .notModified || response.status == .ok) {
            throw EndpointCacheError.unexpctedResponseStatus(response.status, uri: self.uri)
        }
        
        do {
            if let cacheControl = response.headers.cacheControl, cacheControl.noStore == true {
                // The server *shouldn't* give an expiration with no-store, but...
                self.clearCache()
            } else {
                self.headers = response.headers
                self.cached.1 = headers.expirationDate(requestSentAt: requestSentAt)
            }
            
            switch response.status {
            case .notModified:
                logger.trace("EndpointCache - cached data is still valid.")
                
                let cachedData = self.cached
                guard let cached = cachedData.0 else {
                    // This shouldn't actually be possible, but just in case.
                    self.clearCache()
                    return try await self.download(on: eventLoop, using: client, logger: logger)
                }
                
                return cached
                
            case .ok:
                logger.trace("EndpointCache - new data received")
                
                let data: T
                
                do {
                    data = try response.content.decode(T.self)
                } catch {
                    throw EndpointCacheError.contentDecodeFailure(error)
                }
                
                if self.cached.1 != nil {
                    self.cached.0 = data
                }
                
                return data
                
            default:
                // This shouldn't ever happen due to the previous flatMapThrowing
                throw Abort(.internalServerError)
            }
        } catch {
            let cachedData = self.cached
            guard let headers = self.headers, let cached = cachedData.0 else {
                throw error
            }
            
            if let cacheControl = headers.cacheControl, let cacheUntil = cachedData.1 {
                if let staleIfError = cacheControl.staleIfError,
                   cacheUntil.addingTimeInterval(Double(staleIfError)) > Date() {
                    // Can use the data for staleIfError seconds past expiration when the server is non-responsive
                    return cached
                } else if cacheControl.noCache == true && cacheUntil > Date() {
                    // The spec isn't very clear here.  If no-cache is present you're supposed to validate with the
                    // server. However, if the server doesn't respond, but I'm still within the expiration time, I'm
                    // opting to say that the cache should be considered usable.
                    return cached
                }
            }
            
            self.clearCache()
            
            throw error
        }
    }
    
    private func clearCache() {
        self.cached = (nil, nil)
        self.headers = nil
    }
}
