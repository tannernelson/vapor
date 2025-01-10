import NIOHTTPCompression

extension HTTPServer.Configuration {
    /// Supported HTTP decompression options.
    public struct RequestDecompressionConfiguration: Sendable {
        /// Disables decompression. This is the default option.
        public static var disabled: Self {
            .init(storage: .disabled)
        }

        /// Enables decompression with default configuration.
        public static var enabled: Self {
            .enabled(limit: .ratio(25))
        }

        /// Enables decompression with custom configuration.
        public static func enabled(
            limit: NIOHTTPDecompression.DecompressionLimit
        ) -> Self {
            .init(storage: .enabled(limit: limit))
        }

        enum Storage {
            case disabled
            case enabled(limit: NIOHTTPDecompression.DecompressionLimit)
        }

        var storage: Storage
    }
}
