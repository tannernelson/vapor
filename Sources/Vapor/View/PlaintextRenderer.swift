import NIOCore
import NIOPosix
import Logging
import _NIOFileSystem

public struct PlaintextRenderer: ViewRenderer, Sendable {
    private let viewsDirectory: String
    private let logger: Logger

    public init(
        viewsDirectory: String,
        logger: Logger
    ) {
        self.viewsDirectory = viewsDirectory.finished(with: "/")
        self.logger = logger
    }
    
    public func `for`(_ request: Request) -> ViewRenderer {
        PlaintextRenderer(
            viewsDirectory: self.viewsDirectory,
            logger: request.logger
        )
    }

    public func render<E>(_ name: String, _ context: E) async throws -> View
        where E: Encodable
    {
        self.logger.trace("Rendering plaintext view", metadata: ["name": "\(name)", "context": "\(context)"])
        let path = name.hasPrefix("/")
            ? name
            : self.viewsDirectory + name
        return try await FileSystem.shared.withFileHandle(forReadingAt: FilePath(path)) { handle in
            guard let fileSize = try await FileSystem.shared.info(forFileAt: .init(path))?.size else {
                self.logger.debug("Unable to get file size of file", metadata: ["filePath": "\(path)"])
                throw Abort(.internalServerError)
            }
            let chunks = handle.readChunks()
            let buffer = try await chunks.collect(upTo: Int(fileSize))
            return View(data: buffer)
        }
    }
}
