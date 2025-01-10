#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import NIOCore
import _NIOFileSystem
import NIOHTTP1
import Logging
import Crypto
import _NIOFileSystemFoundationCompat

extension Request {
#warning("Fix")
    public var fileio: FileIO {
        return .init(
            allocator: self.application.allocator,
            request: self,
//            storage: self.application.storage
            storage: NewStorage()
        )
    }
}

// MARK: FileIO

/// `FileIO` is a convenience wrapper to make it easy to stream files as a ``Response``. It supports chunked responses and `E-Tag`s.
///
///     app.get("file-stream") { req -> Response in
///         try await req.fileio.streamFile(at: "/path/to/file.txt", for: req)
///     }
///
/// Streaming file responses respect `E-Tag` headers present in the request.
public struct FileIO: Sendable {
    /// ByteBufferAllocator to use for generating buffers.
    private let allocator: ByteBufferAllocator
    
    /// HTTP request context.
    private let request: Request

    /// The underlying ``FileSystem`` to use
    private let fileSystem: FileSystem
    
    /// A cache to store e-tags in
    private let storage: NewStorage

    /// Creates a new `FileIO`.
    ///
    /// See `Request.fileio()` to create one.
    internal init(allocator: ByteBufferAllocator, request: Request, storage: NewStorage) {
        self.allocator = allocator
        self.request = request
        self.fileSystem = .shared
        self.storage = storage
    }

    /// Generates a fresh ETag for a file or returns its currently cached one.
    /// - Parameters:
    ///   - path: The file's path.
    ///   - lastModified: When the file was last modified.
    /// - Returns: A `String` which holds the ETag.
    private func generateETagHash(path: String, lastModified: Date) async throws -> String {
        if let hash = request.application.storage[FileMiddleware.ETagHashes.self]?[path], hash.lastModified == lastModified {
            return hash.digestHex
        } else {
            guard let fileSize = try await FileSystem.shared.info(forFileAt: .init(path))?.size else {
                throw Abort(.internalServerError)
            }
            let chunks = try await fileSystem.withFileHandle(forReadingAt: .init(path)) { fileHandle in
                fileHandle.readChunks(in: 0..<(fileSize))
            }
            let buffer = try await chunks.collect(upTo: Int(fileSize))
            let digest = SHA256.hash(data: buffer.readableBytesView)
                        
            // update hash in dictionary
            var hashes = await self.storage.get(FileMiddleware.ETagHashes.self)
            hashes?[path] = FileMiddleware.ETagHashes.FileHash(lastModified: lastModified, digestHex: digest.hex)
            await self.storage.set(FileMiddleware.ETagHashes.self, to: hashes)
            return digest.hex
        }
    }
    
    /// Generates a chunked `Response` for the specified file. This method respects values in
    /// the `"ETag"` header and is capable of responding `304 Not Modified` if the file in question
    /// has not been modified since last served. If `advancedETagComparison` is set to true,
    /// the response will have its ETag field set to a byte-by-byte hash of the requested file. If set to false, a simple ETag consisting of the last modified date and file size
    /// will be used. This method will also set the `"Content-Type"` header
    /// automatically if an appropriate `MediaType` can be found for the file's suffix.
    ///
    ///     app.get("file-stream") { req in
    ///         return req.fileio.streamFile(at: "/path/to/file.txt")
    ///     }
    ///
    /// - parameters:
    ///     - path: Path to file on the disk.
    ///     - mediaType: HTTPMediaType, if not specified, will be created from file extension.
    ///     - advancedETagComparison: The method used when ETags are generated. If true, a byte-by-byte hash is created (and cached), otherwise a simple comparison based on the file's last modified date and size.
    ///     - onCompleted: Closure to be run on completion of stream.
    /// - returns: A `200 OK` response containing the file stream and appropriate headers.
    public func streamFile(
        at path: String,
        mediaType: HTTPMediaType? = nil,
        advancedETagComparison: Bool = false,
        onCompleted: @escaping @Sendable (Result<Void, Error>) async throws -> () = { _ in }
    ) async throws -> Response {
        // Get file attributes for this file.
        guard let fileInfo = try await FileSystem.shared.info(forFileAt: .init(path)) else {
            throw Abort(.internalServerError)
        }

        let contentRange: HTTPHeaders.Range?
        if let rangeFromHeaders = request.headers.range {
            if rangeFromHeaders.unit == .bytes && rangeFromHeaders.ranges.count == 1 {
                contentRange = rangeFromHeaders
            } else {
                contentRange = nil
            }
        } else if request.headers.contains(name: .range) {
            // Range header was supplied but could not be parsed i.e. it was invalid
            request.logger.debug("Range header was provided in request but was invalid")
            throw Abort(.badRequest)
        } else {
            contentRange = nil
        }

        let eTag: String

        if advancedETagComparison {
            eTag = try await generateETagHash(path: path, lastModified: fileInfo.lastDataModificationTime.date)
        } else {
            // Generate ETag value, "last modified date in epoch time" + "-" + "file size"
            eTag = "\"\(fileInfo.lastDataModificationTime.seconds)-\(fileInfo.size)\""
        }
        
        // Create empty headers array.
        var headers: HTTPHeaders = [:]

        // Respond with lastModified header
        headers.lastModified = HTTPHeaders.LastModified(value: fileInfo.lastDataModificationTime.date)

        headers.replaceOrAdd(name: .eTag, value: eTag)

        // Check if file has been cached already and return NotModified response if the etags match
        if eTag == request.headers.first(name: .ifNoneMatch) {
            // Per RFC 9110 here: https://www.rfc-editor.org/rfc/rfc9110.html#status.304
            // and here: https://www.rfc-editor.org/rfc/rfc9110.html#name-content-encoding
            // A 304 response MUST include the ETag header and a Content-Length header matching what the original resource's content length would have been were this a 200 response.
            headers.replaceOrAdd(name: .contentLength, value: fileInfo.size.description)
            return Response(status: .notModified, version: .http1_1, headersNoUpdate: headers, body: .empty)
        }

        // Create the HTTP response.
        let response = Response(status: .ok, headers: headers)
        let offset: Int64
        let byteCount: Int
        if let contentRange = contentRange {
            response.status = .partialContent
            response.headers.add(name: .accept, value: contentRange.unit.serialize())
            if let firstRange = contentRange.ranges.first {
                do {
                    let range = try firstRange.asResponseContentRange(limit: Int(fileInfo.size))
                    response.headers.contentRange = HTTPHeaders.ContentRange(unit: contentRange.unit, range: range)
                    (offset, byteCount) = try firstRange.asByteBufferBounds(withMaxSize: Int(fileInfo.size), logger: request.logger)
                } catch {
                    throw Abort(.badRequest)
                }
            } else {
                offset = 0
                byteCount = Int(fileInfo.size)
            }
        } else {
            offset = 0
            byteCount = Int(fileInfo.size)
        }
        // Set Content-Type header based on the media type
        // Only set Content-Type if file not modified and returned above.
        if
            let fileExtension = path.components(separatedBy: ".").last,
            let type = mediaType ?? HTTPMediaType.fileExtension(fileExtension)
        {
            response.headers.contentType = type
        }
        
        response.body = .init(asyncStream: { stream in
            do {
                let chunks = try await fileSystem.withFileHandle(forReadingAt: .init(path)) { fileHandle in
                    fileHandle.readChunks(in: offset..<(offset + Int64(byteCount)))
                }
                for try await chunk in chunks {
                    try await stream.writeBuffer(chunk)
                }
                try await stream.write(.end)
                try await onCompleted(.success(()))
            } catch {
                try? await stream.write(.error(error))
                try await onCompleted(.failure(error))
            }
        }, count: byteCount, byteBufferAllocator: request.byteBufferAllocator)

        return response
    }
}

extension HTTPHeaders.Range.Value {
    
    fileprivate func asByteBufferBounds(withMaxSize size: Int, logger: Logger) throws -> (offset: Int64, byteCount: Int) {
        switch self {
            case .start(let value):
                guard value <= size, value >= 0 else {
                    logger.debug("Requested range start was invalid: \(value)")
                    throw Abort(.badRequest)
                }
                return (offset: numericCast(value), byteCount: size - value)
            case .tail(let value):
                guard value <= size, value >= 0 else {
                    logger.debug("Requested range end was invalid: \(value)")
                    throw Abort(.badRequest)
                }
                return (offset: numericCast(size - value), byteCount: value)
            case .within(let start, let end):
                guard start >= 0, end >= 0, start <= end, start <= size, end <= size else {
                    logger.debug("Requested range was invalid: \(start)-\(end)")
                    throw Abort(.badRequest)
                }
                let (byteCount, overflow) =  (end - start).addingReportingOverflow(1)
                guard !overflow else {
                    logger.debug("Requested range was invalid: \(start)-\(end)")
                    throw Abort(.badRequest)
                }
                return (offset: numericCast(start), byteCount: byteCount)
        }
    }
}
