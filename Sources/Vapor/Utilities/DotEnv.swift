#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
import Darwin
#endif
import Logging
import NIOCore
import _NIOFileSystem

/// Reads dotenv (`.env`) files and loads them into the current process.
///
///     let file = try await DotEnvFile.read(path: ".env")
///     for line in file.lines {
///         print("\(line.key)=\(line.value)")
///     }
///     file.load(overwrite: true) // loads all lines into the process
///
/// Dotenv files are formatted using `KEY=VALUE` syntax. They support comments using the `#` symbol.
/// They also support strings, both single and double-quoted.
///
///     FOO=BAR
///     STRING='Single Quote String'
///     # Comment
///     STRING2="Double Quoted\nString"
///
/// Single-quoted strings are parsed literally. Double-quoted strings may contain escaped newlines
/// that will be converted to actual newlines.
public struct DotEnvFile: Sendable {
    /// Represents a `KEY=VALUE` pair in a dotenv file.
    public struct Line: Sendable, CustomStringConvertible, Equatable {
        /// The key.
        public let key: String

        /// The value.
        public let value: String

        /// `CustomStringConvertible` conformance.
        public var description: String {
            return "\(self.key)=\(self.value)"
        }
    }

    /// All `KEY=VALUE` pairs found in the file.
    public let lines: [Line]

    /// Creates a new DotEnvFile
    init(lines: [Line]) {
        self.lines = lines
    }

    /// Loads this file's `KEY=VALUE` pairs into the current process.
    ///
    ///     let file: DotEnvFile
    ///     file.load(overwrite: true) // loads all lines into the process
    ///
    /// - parameters:
    ///     - overwrite: If `true`, values already existing in the process' env
    ///                  will be overwritten. Defaults to `false`.
    public func load(overwrite: Bool = false) {
        for line in self.lines {
            setenv(line.key, line.value, overwrite ? 1 : 0)
        }
    }
    
    // MARK: - Concurrency
    /// Reads a dotenv file from the supplied path.
    ///
    ///     let file = try await DotEnvFile.read(path: ".env")
    ///     for line in file.lines {
    ///         print("\(line.key)=\(line.value)")
    ///     }
    ///     file.load(overwrite: true) // loads all lines into the process
    ///     print(Environment.process.FOO) // BAR
    ///
    /// Use `DotEnvFile.load` to read and load with one method.
    ///
    /// - parameters:
    ///     - path: Absolute or relative path of the dotenv file.
    ///     - logger: ``Logging.Logger`` to use for logs
    public static func read(path: String, logger: Logger = Logger(label: "dot-env-loggger")) async throws -> DotEnvFile {
        try await FileSystem.shared.withFileHandle(forReadingAt: .init(path)) { fileHandle in
            let chunks = fileHandle.readChunks()
            guard let fileSize = try await FileSystem.shared.info(forFileAt: .init(path))?.size else {
                logger.debug("Unable to get file size of file", metadata: ["filePath": "\(path)"])
                throw Abort(.internalServerError)
            }
            let buffer = try await chunks.collect(upTo: Int(fileSize))
            var parser = Parser(source: buffer)
            return DotEnvFile(lines: parser.parse())
        }
    }
    
    /// Reads a dotenv file from the supplied path and loads it into the process.
    ///
    ///     try await DotEnvFile.load(path: ".env")
    ///     print(Environment.process.FOO) // BAR
    ///
    /// Use `DotEnvFile.read` to read the file without loading it.
    ///
    /// - parameters:
    ///     - path: Absolute or relative path of the dotenv file.
    ///     - overwrite: If `true`, values already existing in the process' env
    ///                  will be overwritten. Defaults to `false`.
    public static func load(
        path: String,
        overwrite: Bool = false,
        logger: Logger = Logger(label: "dot-env-loggger")
    ) async throws {
        let file = try await self.read(path: path, logger: logger)
        file.load(overwrite: overwrite)
    }
    
    /// Reads the dotenv files relevant to the environment and loads them into the process.
    ///
    ///     let path: String
    ///     let logger: Logger
    ///     try DotEnvFile.load(path: path, logger: logger)
    ///     print(Environment.process.FOO) // BAR
    ///
    /// - parameters:
    ///     - path: Absolute or relative path of the dotenv file.
    ///     - logger: Optionally provide an existing logger.
    public static func load(
        path: String,
        logger: Logger = Logger(label: "dot-env-loggger")
    ) async {
        do {
            try await load(path: path, overwrite: false, logger: logger)
        } catch {
            logger.debug("Could not load \(path) file: \(error)")
        }
    }
    
    /// Reads the dotenv files relevant to the environment and loads them into the process.
    ///
    ///     let environment: Environment
    ///     let logger: Logger
    ///     try await DotEnvFile.load(for: .development, logger: logger)
    ///     print(Environment.process.FOO) // BAR
    ///
    /// - parameters:
    ///     - environment: current environment, selects which .env file to use.
    ///     - logger: Optionally provide an existing logger.
    public static func load(
        for environment: Environment = .development,
        logger: Logger = Logger(label: "dot-env-loggger")
    ) async {
        // Load specific .env first since values are not overridden.
        await DotEnvFile.load(path: ".env.\(environment.name)", logger: logger)
        await DotEnvFile.load(path: ".env", logger: logger)
    }
}

// MARK: Parser

extension DotEnvFile {
    struct Parser {
        var source: ByteBuffer
        init(source: ByteBuffer) {
            self.source = source
        }

        mutating func parse() -> [Line] {
            var lines: [Line] = []
            while let next = self.parseNext() {
                lines.append(next)
            }
            return lines
        }

        private mutating func parseNext() -> Line? {
            self.skipSpaces()
            guard let peek = self.peek() else {
                return nil
            }
            switch peek {
            case .octothorpe:
                // comment following, skip it
                self.skipComment()
                // then parse next
                return self.parseNext()
            case .newLine:
                // empty line, skip
                self.pop() // \n
                // then parse next
                return self.parseNext()
            default:
                // this is a valid line, parse it
                return self.parseLine()
            }
        }

        private mutating func skipComment() {
            let commentLength: Int
            if let toNewLine = self.countDistance(to: .newLine) {
                commentLength = toNewLine + 1 // include newline
            } else {
                commentLength = self.source.readableBytes
            }
            self.source.moveReaderIndex(forwardBy: commentLength)
        }

        private mutating func parseLine() -> Line? {
            guard let keyLength = self.countDistance(to: .equal) else {
                return nil
            }
            guard let key = self.source.readString(length: keyLength) else {
                return nil
            }
            self.pop() // =
            guard let value = self.parseLineValue() else {
                return nil
            }
            return Line(key: key, value: value)
        }

        private mutating func parseLineValue() -> String? {
            let valueLength: Int
            if let toNewLine = self.countDistance(to: .newLine) {
                valueLength = toNewLine
            } else {
                valueLength = self.source.readableBytes
            }
            guard let value = self.source.readString(length: valueLength) else {
                return nil
            }
            guard let first = value.first, let last = value.last else {
                return value
            }
            // check for quoted strings
            switch (first, last) {
            case ("\"", "\""):
                // double quoted strings support escaped \n
                return value.dropFirst().dropLast()
                    .replacingOccurrences(of: "\\n", with: "\n")
            case ("'", "'"):
                // single quoted strings just need quotes removed
                return value.dropFirst().dropLast() + ""
            default: return value
            }
        }

        private mutating func skipSpaces() {
            scan: while let next = self.peek() {
                switch next {
                case .space: self.pop()
                default: break scan
                }
            }
        }

        private func peek() -> UInt8? {
            return self.source.getInteger(at: self.source.readerIndex)
        }

        private mutating func pop() {
            self.source.moveReaderIndex(forwardBy: 1)
        }

        private func countDistance(to byte: UInt8) -> Int? {
            var copy = self.source
            var found = false
            scan: while let next = copy.readInteger(as: UInt8.self) {
                if next == byte {
                    found = true
                    break scan
                }
            }
            guard found else {
                return nil
            }
            let distance = copy.readerIndex - source.readerIndex
            guard distance != 0 else {
                return nil
            }
            return distance - 1
        }
    }
}

private extension UInt8 {
    static var newLine: UInt8 {
        return 0xA
    }

    static var space: UInt8 {
        return 0x20
    }

    static var octothorpe: UInt8 {
        return 0x23
    }

    static var equal: UInt8 {
        return 0x3D
    }
}
