import Foundation
import NIOCore
import _NIOFileSystem
import NIOHTTP1
import NIOPosix
import Logging
import Crypto
import NIOConcurrencyHelpers
import _NIOFileSystemFoundationCompat

extension Request {
    public var fileio: FileIO {
        return .init(
            io: self.application.fileio,
            allocator: self.application.allocator,
            request: self
        )
    }
}

// MARK: FileIO

/// `FileIO` is a convenience wrapper around SwiftNIO's `NonBlockingFileIO`.
///
/// It can read files, both in their entirety and chunked.
///
///
///     req.fileio.readFile(at: "/path/to/file.txt") { chunk in
///         print(chunk) // part of file
///     }
///
///     req.fileio.collectFile(at: "/path/to/file.txt").map { file in
///         print(file) // entire file
///     }
///
/// It can also create streaming HTTP responses.
///
///     app.get("file-stream") { req -> Response in
///         return req.fileio.streamFile(at: "/path/to/file.txt", for: req)
///     }
///
/// Streaming file responses respect `E-Tag` headers present in the request.
public struct FileIO: Sendable {
    /// Wrapped non-blocking file io from SwiftNIO
    private let io: NonBlockingFileIO

    /// ByteBufferAllocator to use for generating buffers.
    private let allocator: ByteBufferAllocator
    
    /// HTTP request context.
    let request: Request

    let fileSystem: FileSystem = .shared

    /// Creates a new `FileIO`.
    ///
    /// See `Request.fileio()` to create one.
    internal init(io: NonBlockingFileIO, allocator: ByteBufferAllocator, request: Request) {
        self.io = io
        self.allocator = allocator
        self.request = request
    }

    /// Reads the contents of a file at the supplied path.
    ///
    ///     let data = try req.fileio.collectFile(at: "/path/to/file.txt").wait()
    ///     print(data) // file data
    ///
    /// - parameters:
    ///     - path: Path to file on the disk.
    /// - returns: `Future` containing the file data as a `ByteBuffer`.
    public func collectFile(at path: String) -> EventLoopFuture<ByteBuffer> {
        let dataWrapper: NIOLockedValueBox<ByteBuffer> = .init(self.allocator.buffer(capacity: 0))
        return self.readFile(at: path) { new in
            var new = new
            _ = dataWrapper.withLockedValue({ $0.writeBuffer(&new) })
            return self.request.eventLoop.makeSucceededFuture(())
        }.map { dataWrapper.withLockedValue { $0 } }
    }

    /// Reads the contents of a file at the supplied path in chunks.
    ///
    ///     try req.fileio.readFile(at: "/path/to/file.txt") { chunk in
    ///         print("chunk: \(data)")
    ///     }.wait()
    ///
    /// - parameters:
    ///     - path: Path to file on the disk.
    ///     - chunkSize: Maximum size for the file data chunks.
    ///     - onRead: Closure to be called sequentially for each file data chunk.
    /// - returns: `Future` that will complete when the file read is finished.
    @preconcurrency public func readFile(
        at path: String,
        chunkSize: Int = NonBlockingFileIO.defaultChunkSize,
        onRead: @Sendable @escaping (ByteBuffer) -> EventLoopFuture<Void>
    ) -> EventLoopFuture<Void> {
        self.request.eventLoop.makeFutureWithTask {
            guard let fileSize = try await FileSystem.shared.info(forFileAt: .init(path))?.size else {
                throw Abort(.internalServerError)
            }
            try await self.read(
                path: path,
                fromOffset: 0,
                byteCount: Int(fileSize),
                chunkSize: chunkSize,
                onRead: onRead
            ).get()
        }
    }

    /// Generates a chunked `Response` for the specified file. This method respects values in
    /// the `"ETag"` header and is capable of responding `304 Not Modified` if the file in question
    /// has not been modified since last served. This method will also set the `"Content-Type"` header
    /// automatically if an appropriate `MediaType` can be found for the file's suffix.
    ///
    ///     app.get("file-stream") { req in
    ///         return req.fileio.streamFile(at: "/path/to/file.txt")
    ///     }
    ///
    /// - parameters:
    ///     - path: Path to file on the disk.
    ///     - chunkSize: Maximum size for the file data chunks.
    ///     - mediaType: HTTPMediaType, if not specified, will be created from file extension.
    ///     - onCompleted: Closure to be run on completion of stream.
    /// - returns: A `200 OK` response containing the file stream and appropriate headers.
    @preconcurrency public func streamFile(
        at path: String,
        chunkSize: Int = NonBlockingFileIO.defaultChunkSize,
        mediaType: HTTPMediaType? = nil,
        onCompleted: @Sendable @escaping (Result<Void, Error>) -> () = { _ in }
    ) -> Response {
        // Get file attributes for this file.
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: path),
            let modifiedAt = attributes[.modificationDate] as? Date,
            let fileSize = (attributes[.size] as? NSNumber)?.intValue
        else {
            return Response(status: .internalServerError)
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
            let response = Response(status: .badRequest)
            return response
        } else {
            contentRange = nil
        }
        // Create empty headers array.
        var headers: HTTPHeaders = [:]

        // Respond with lastModified header
        headers.lastModified = HTTPHeaders.LastModified(value: modifiedAt)

        // Generate ETag value, "HEX value of last modified date" + "-" + "file size"
        let fileETag = "\"\(modifiedAt.timeIntervalSince1970)-\(fileSize)\""
        headers.replaceOrAdd(name: .eTag, value: fileETag)

        // Check if file has been cached already and return NotModified response if the etags match
        if fileETag == request.headers.first(name: .ifNoneMatch) {
            // Per RFC 9110 here: https://www.rfc-editor.org/rfc/rfc9110.html#status.304
            // and here: https://www.rfc-editor.org/rfc/rfc9110.html#name-content-encoding
            // A 304 response MUST include the ETag header and a Content-Length header matching what the original resource's content length would have been were this a 200 response.
            headers.replaceOrAdd(name: .contentLength, value: fileSize.description)
            return Response(status: .notModified, version: .http1_1, headersNoUpdate: headers, body: .empty)
        }

        // Create the HTTP response.
        let response = Response(status: .ok, headers: headers)
        let offset: Int64
        let byteCount: Int
        if let contentRange = contentRange {
            response.responseBox.withLockedValue { box in
                box.status = .partialContent
                box.headers.add(name: .accept, value: contentRange.unit.serialize())
            }
            if let firstRange = contentRange.ranges.first {
                do {
                    let range = try firstRange.asResponseContentRange(limit: fileSize)
                    response.headers.contentRange = HTTPHeaders.ContentRange(unit: contentRange.unit, range: range)
                    (offset, byteCount) = try firstRange.asByteBufferBounds(withMaxSize: fileSize, logger: request.logger)
                } catch {
                    let response = Response(status: .badRequest)
                    return response
                }
            } else {
                offset = 0
                byteCount = fileSize
            }
        } else {
            offset = 0
            byteCount = fileSize
        }
        // Set Content-Type header based on the media type
        // Only set Content-Type if file not modified and returned above.
        if
            let fileExtension = path.components(separatedBy: ".").last,
            let type = mediaType ?? HTTPMediaType.fileExtension(fileExtension)
        {
            response.headers.contentType = type
        }
        response.body = .init(stream: { stream in
            self.read(path: path, fromOffset: offset, byteCount: byteCount, chunkSize: chunkSize) { chunk in
                return stream.write(.buffer(chunk))
            }.whenComplete { result in
                switch result {
                case .failure(let error):
                    stream.write(.error(error), promise: nil)
                case .success:
                    stream.write(.end, promise: nil)
                }
                onCompleted(result)
            }
        }, count: byteCount, byteBufferAllocator: request.byteBufferAllocator)

        return response
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
    ///     - chunkSize: Maximum size for the file data chunks.
    ///     - mediaType: HTTPMediaType, if not specified, will be created from file extension.
    ///     - advancedETagComparison: The method used when ETags are generated. If true, a byte-by-byte hash is created (and cached), otherwise a simple comparison based on the file's last modified date and size.
    ///     - onCompleted: Closure to be run on completion of stream.
    /// - returns: A `200 OK` response containing the file stream and appropriate headers.
    public func streamFile(
        at path: String,
        chunkSize: Int = NonBlockingFileIO.defaultChunkSize,
        mediaType: HTTPMediaType? = nil,
        advancedETagComparison: Bool,
        onCompleted: @escaping @Sendable (Result<Void, Error>) -> () = { _ in }
    ) -> EventLoopFuture<Response> {
        // Get file attributes for this file.
        self.request.eventLoop.makeFutureWithTask {
            try await self.asyncStreamFile(at: path, chunkSize: chunkSize, mediaType: mediaType, advancedETagComparison: advancedETagComparison, onCompleted: onCompleted)
        }
    }

    /// Private read method. `onRead` closure uses ByteBuffer and expects future return.
    /// There may be use in publicizing this in the future for reads that must be async.
    private func read(
        path: String,
        fromOffset offset: Int64,
        byteCount: Int,
        chunkSize: Int,
        onRead: @Sendable @escaping (ByteBuffer) -> EventLoopFuture<Void>
    ) -> EventLoopFuture<Void> {
        self.request.eventLoop.flatSubmit {
            do {
                let fd = try NIOFileHandle(path: path)
                let fdWrapper = NIOLoopBound(fd, eventLoop: self.request.eventLoop)
                let done = self.io.readChunked(
                    fileHandle: fd,
                    fromOffset: offset,
                    byteCount: byteCount,
                    chunkSize: chunkSize,
                    allocator: allocator,
                    eventLoop: self.request.eventLoop
                ) { chunk in
                    return onRead(chunk)
                }
                done.whenComplete { _ in
                    try? fdWrapper.value.close()
                }
                return done
            } catch {
                return self.request.eventLoop.makeFailedFuture(error)
            }
        }
    }
    
    /// Async version of `read(path:fromOffset:byteCount:chunkSize:onRead)`
    private func read(
        path: String,
        fromOffset offset: Int64,
        byteCount: Int
    ) async throws -> ByteBuffer {
        let fd = try NIOFileHandle(path: path)
        defer {
            try? fd.close()
        }
        return try await self.io.read(fileHandle: fd, fromOffset: offset, byteCount: byteCount, allocator: allocator)
    }
    
    /// Write the contents of buffer to a file at the supplied path.
    ///
    ///     let data = ByteBuffer(string: "ByteBuffer")
    ///     try req.fileio.writeFile(data, at: "/path/to/file.txt").wait()
    ///
    /// - parameters:
    ///     - path: Path to file on the disk.
    ///     - buffer: The `ByteBuffer` to write.
    /// - returns: `Future` that will complete when the file write is finished.
    public func writeFile(_ buffer: ByteBuffer, at path: String) -> EventLoopFuture<Void> {
        self.request.eventLoop.flatSubmit {
            do {
                let fd = try NIOFileHandle(path: path, mode: .write, flags: .allowFileCreation())
                let fdWrapper = NIOLoopBound(fd, eventLoop: self.request.eventLoop)
                let done = io.write(fileHandle: fd, buffer: buffer, eventLoop: self.request.eventLoop)
                done.whenComplete { _ in
                    try? fdWrapper.value.close()
                }
                return done
            } catch {
                return self.request.eventLoop.makeFailedFuture(error)
            }
        }
    }

    /// Generates a fresh ETag for a file or returns its currently cached one.
    /// - Parameters:
    ///   - path: The file's path.
    ///   - lastModified: When the file was last modified.
    /// - Returns: An `EventLoopFuture<String>` which holds the ETag.
    private func generateETagHash(path: String, lastModified: Date) -> EventLoopFuture<String> {
        if let hash = request.application.storage[FileMiddleware.ETagHashes.self]?[path], hash.lastModified == lastModified {
            return request.eventLoop.makeSucceededFuture(hash.digestHex)
        } else {
            return collectFile(at: path).map { buffer in
                let digest = SHA256.hash(data: buffer.readableBytesView)
                
                // update hash in dictionary
                request.application.storage[FileMiddleware.ETagHashes.self]?[path] = FileMiddleware.ETagHashes.FileHash(lastModified: lastModified, digestHex: digest.hex)
                
                return digest.hex
            }
        }
    }
    
    // MARK: - Concurrency
    /// Reads the contents of a file at the supplied path.
    ///
    ///     let data = try await req.fileio.collectFile(file: "/path/to/file.txt")
    ///     print(data) // file data
    ///
    /// - parameters:
    ///     - path: Path to file on the disk.
    /// - returns: `ByteBuffer` containing the file data.
    public func collectFile(at path: String) async throws -> ByteBuffer {
        guard let fileSize = try await FileSystem.shared.info(forFileAt: .init(path))?.size else {
            throw Abort(.internalServerError)
        }
        return try await self.read(path: path, fromOffset: 0, byteCount: Int(fileSize))
    }
    
    /// Wrapper around `NIOFileSystem.FileChunks`.
    /// This can be removed once `NIOFileSystem` reaches a stable API.
    public struct FileChunks: AsyncSequence {
        public typealias Element = ByteBuffer
        private let fileHandle: _NIOFileSystem.FileHandleProtocol
        private let fileChunks: _NIOFileSystem.FileChunks

        init(fileChunks: _NIOFileSystem.FileChunks, fileHandle: some _NIOFileSystem.FileHandleProtocol) {
            self.fileChunks = fileChunks
            self.fileHandle = fileHandle
        }

        public struct FileChunksIterator: AsyncIteratorProtocol {
            private var iterator: _NIOFileSystem.FileChunks.AsyncIterator
            private let fileHandle: _NIOFileSystem.FileHandleProtocol

            fileprivate init(wrapping iterator: _NIOFileSystem.FileChunks.AsyncIterator, fileHandle: some _NIOFileSystem.FileHandleProtocol) {
                self.iterator = iterator
                self.fileHandle = fileHandle
            }

            public mutating func next() async throws -> ByteBuffer? {
                let chunk = try await iterator.next()
                if chunk == nil {
                    // For convenience's sake, close when we hit EOF. Closing on error is left up to the caller.
                    try await fileHandle.close()
                }
                return chunk
            }
        }
        
        public func closeHandle() async throws {
            try await self.fileHandle.close()
        }

        public func makeAsyncIterator() -> FileChunksIterator {
            FileChunksIterator(wrapping: fileChunks.makeAsyncIterator(), fileHandle: fileHandle)
        }
    }

    /// Reads the contents of a file at the supplied path in chunks.
    ///
    ///    for try await chunk in try await req.fileio.readFile(at: "/path/to/file.txt") {
    ///        print("chunk: \(data)")
    ///    }
    ///
    /// - parameters:
    ///     - path: Path to file on the disk.
    ///     - chunkSize: Maximum size for the file data chunks.
    /// - returns: `FileChunks` containing the file data chunks.
    public func readFile(
        at path: String,
        chunkSize: Int = NonBlockingFileIO.defaultChunkSize,
        offset: Int64? = nil,
        byteCount: Int? = nil
    ) async throws -> FileChunks {
        let filePath = FilePath(path)
        
        let readHandle = try await fileSystem.openFile(forReadingAt: filePath)
        
        let chunks: _NIOFileSystem.FileChunks
        
        if let offset {
            if let byteCount {
                chunks = readHandle.readChunks(in: offset..<(offset+Int64(byteCount)), chunkLength: .bytes(Int64(chunkSize)))
            } else {
                chunks = readHandle.readChunks(in: offset..., chunkLength: .bytes(Int64(chunkSize)))
            }
        } else {
            chunks = readHandle.readChunks(chunkLength: .bytes(Int64(chunkSize)))
        }

        return FileChunks(fileChunks: chunks, fileHandle: readHandle)
    }
    
    /// Write the contents of buffer to a file at the supplied path.
    ///
    ///     let data = ByteBuffer(string: "ByteBuffer")
    ///     try await req.fileio.writeFile(data, at: "/path/to/file.txt")
    ///
    /// - parameters:
    ///     - path: Path to file on the disk.
    ///     - buffer: The `ByteBuffer` to write.
    /// - returns: `Void` when the file write is finished.
    public func writeFile(_ buffer: ByteBuffer, at path: String) async throws {
        let fd = try NIOFileHandle(path: path, mode: .write, flags: .allowFileCreation())
        defer {
            try? fd.close()
        }
        try await self.io.write(fileHandle: fd, buffer: buffer)
    }
    
    /// Generates a chunked `Response` for the specified file. This method respects values in
    /// the `"ETag"` header and is capable of responding `304 Not Modified` if the file in question
    /// has not been modified since last served. If `advancedETagComparison` is set to true,
    /// the response will have its ETag field set to a byte-by-byte hash of the requested file. If set to false, a simple ETag consisting of the last modified date and file size
    /// will be used. This method will also set the `"Content-Type"` header
    /// automatically if an appropriate `MediaType` can be found for the file's suffix.
    ///
    ///     app.get("file-stream") { req in
    ///         return req.fileio.asyncStreamFile(at: "/path/to/file.txt")
    ///     }
    ///
    /// Async equivalent of ``streamFile(at:chunkSize:mediaType:advancedETagComparison:onCompleted:)`` using Swift Concurrency
    /// functions under the hood
    ///
    /// - parameters:
    ///     - path: Path to file on the disk.
    ///     - chunkSize: Maximum size for the file data chunks.
    ///     - mediaType: HTTPMediaType, if not specified, will be created from file extension.
    ///     - advancedETagComparison: The method used when ETags are generated. If true, a byte-by-byte hash is created (and cached), otherwise a simple comparison based on the file's last modified date and size.
    ///     - onCompleted: Closure to be run on completion of stream.
    /// - returns: A `200 OK` response containing the file stream and appropriate headers.
    public func asyncStreamFile(
        at path: String,
        chunkSize: Int = NonBlockingFileIO.defaultChunkSize,
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
            eTag = try await generateETagHash(path: path, lastModified: fileInfo.lastDataModificationTime.date).get()
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
                let chunks = try await self.readFile(at: path, chunkSize: chunkSize, offset: offset, byteCount: byteCount)
                do {
                    for try await chunk in chunks {
                        try await stream.writeBuffer(chunk)
                    }
                    try? await chunks.closeHandle()
                } catch {
                    try? await chunks.closeHandle()
                    throw error
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
                guard start >= 0, end >= 0, start < end, start <= size else {
                    logger.debug("Requested range was invalid: \(start)-\(end)")
                    throw Abort(.badRequest)
                }
                let (byteCount, overflow) =  (end - start).addingReportingOverflow(1)
                guard !overflow else {
                    logger.debug("Requested range was invalid: \(start)-\(end)")
                    throw Abort(.badRequest)
                }
                var byteCountToReqeust = byteCount
                    // Request past EOF, return up to EOF bytes
                if (end > size) {
                    byteCountToReqeust = byteCount - (end - size)
                }
                return (offset: numericCast(start), byteCount: byteCountToReqeust)
        }
    }
}
