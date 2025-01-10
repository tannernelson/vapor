import Foundation
import NIOCore
import NIOHTTP1

/// Captures all errors and transforms them into an internal server error HTTP response.
public final class ErrorMiddleware: Middleware {
    /// Structure of `ErrorMiddleware` default response.
    internal struct ErrorResponse: Codable {
        /// Always `true` to indicate this is a non-typical JSON response.
        var error: Bool

        /// The reason for the error.
        var reason: String
    }

    /// Create a default `ErrorMiddleware`. Logs errors to a `Logger` based on `Environment`
    /// and converts `Error` to `Response` based on conformance to `AbortError` and `Debuggable`.
    ///
    /// - parameters:
    ///     - environment: The environment to respect when presenting errors.
    public static func `default`(environment: Environment) -> ErrorMiddleware {
        return .init { req, error in
            let status: HTTPResponseStatus, reason: String, source: ErrorSource
            var headers: HTTPHeaders

            // Inspect the error type and extract what data we can.
            switch error {
            case let debugAbort as (DebuggableError & AbortError):
                (reason, status, headers, source) = (debugAbort.reason, debugAbort.status, debugAbort.headers, debugAbort.source ?? .capture())
                
            case let abort as AbortError:
                (reason, status, headers, source) = (abort.reason, abort.status, abort.headers, .capture())
            
            case let debugErr as DebuggableError:
                (reason, status, headers, source) = (debugErr.reason, .internalServerError, [:], debugErr.source ?? .capture())
            
            default:
                // In debug mode, provide the error description; otherwise hide it to avoid sensitive data disclosure.
                reason = environment.isRelease ? "Something went wrong." : String(describing: error)
                (status, headers, source) = (.internalServerError, [:], .capture())
            }
            
            // Report the error
            req.logger.report(error: error,
                              metadata: ["method" : "\(req.method.rawValue)",
                                         "url" : "\(req.url.string)",
                                         "userAgent" : .array(req.headers["User-Agent"].map { "\($0)" })],
                              file: source.file,
                              function: source.function,
                              line: source.line)
            
            // attempt to serialize the error to json
            let body: Response.Body
            do {
                let encoder = try ContentConfiguration.global.requireEncoder(for: .json)
                var byteBuffer = req.byteBufferAllocator.buffer(capacity: 0)
                try encoder.encode(ErrorResponse(error: true, reason: reason), to: &byteBuffer, headers: &headers)
                
                body = .init(
                    buffer: byteBuffer,
                    byteBufferAllocator: req.byteBufferAllocator
                )
            } catch {
                body = .init(string: "Oops: \(String(describing: error))\nWhile encoding error: \(reason)", byteBufferAllocator: req.byteBufferAllocator)
                headers.contentType = .plainText
            }
            
            // create a Response with appropriate status
            return Response(status: status, headers: headers, body: body)
        }
    }

    /// Error-handling closure.
    private let closure: @Sendable (Request, Error) async -> (Response)

    /// Create a new `ErrorMiddleware`.
    ///
    /// - parameters:
    ///     - closure: Error-handling closure. Converts `Error` to `Response`.
    public init(_ closure: @Sendable @escaping (Request, Error) async -> (Response)) {
        self.closure = closure
    }
    
    public func respond(to request: Request, chainingTo next: any Responder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch {
            return await self.closure(request, error)
        }
    }
}
