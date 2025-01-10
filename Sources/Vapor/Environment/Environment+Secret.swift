import NIOFileSystem
import Logging

extension Environment {
    /// Reads a file's content for a secret. The secret key is the name of the environment variable that is expected to
    /// specify the path of the file containing the secret.
    ///
    /// - Parameters:
    ///   - key: The environment variable name
    ///
    /// Example usage:
    ///
    /// ````
    /// func configure(_ app: Application) {
    ///     // ...
    ///
    ///     let databasePassword = try await Environment.secret(key: "DATABASE_PASSWORD_FILE")
    ///
    /// ````
    ///
    /// - Important: Do _not_ use `.wait()` if loading a secret at any time after the app has booted, such as while
    ///   handling a `Request`. Chain the result as you would any other future instead.
    public static func secret(key: String, logger: Logger) async throws -> String? {
        guard let filePath = self.get(key) else {
            return nil
        }
        return try await self.secret(path: filePath, logger: logger)
    }


    /// Load the content of a file at a given path as a secret.
    ///  
    /// - Parameters:
    ///   - path: Path to the file containing the secret
    ///  
    /// - Returns:
    ///   - The loaded content of a file or `nil` if there was an error
    public static func secret(path: String, logger: Logger) async throws -> String? {
        do {
            return try await FileSystem.shared.withFileHandle(forReadingAt: FilePath(path)) { handle in
                guard let fileSize = try await FileSystem.shared.info(forFileAt: .init(path))?.size else {
                    logger.debug("Unable to get file size of file", metadata: ["filePath": "\(path)"])
                    throw Abort(.internalServerError)
                }
                let chunks = handle.readChunks()
                let buffer = try await chunks.collect(upTo: Int(fileSize))
                return buffer
                    .getString(at: buffer.readerIndex, length: buffer.readableBytes)!
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            return nil
        }
    }
}
