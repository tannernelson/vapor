import NIOCore
import NIOExtras
import NIOHTTP1
import NIOHTTP2
import NIOHTTPCompression
import NIOSSL
import Logging
import NIOPosix
import NIOConcurrencyHelpers

public enum HTTPVersionMajor: Equatable, Hashable, Sendable {
    case one
    case two
}

public final class HTTPServer: Server, Sendable {
    /// Engine server config struct.
    ///
    ///     let serverConfig = HTTPServerConfig.default(port: 8123)
    ///     services.register(serverConfig)
    ///
    public struct Configuration: Sendable {
        public static let defaultHostname = "127.0.0.1"
        public static let defaultPort = 8080
        
        /// Address the server will bind to. Configuring an address using a hostname with a nil host or port will use the default hostname or port respectively.
        public var address: BindAddress
        
        /// Host name the server will bind to.
        public var hostname: String {
            get {
                switch address {
                case .hostname(let hostname, _):
                    return hostname ?? Self.defaultHostname
                default:
                    return Self.defaultHostname
                }
            }
            set {
                switch address {
                case .hostname(_, let port):
                    address = .hostname(newValue, port: port)
                default:
                    address = .hostname(newValue, port: nil)
                }
            }
        }
        
        /// Port the server will bind to.
        public var port: Int {
            get {
                switch address {
                case .hostname(_, let port):
                    return port ?? Self.defaultPort
                default:
                    return Self.defaultPort
                }
            }
            set {
                switch address {
                case .hostname(let hostname, _):
                    address = .hostname(hostname, port: newValue)
                default:
                    address = .hostname(nil, port: newValue)
                }
            }
        }
        
        /// A human-readable description of the configured address. Used in log messages when starting server.
        var addressDescription: String {
            let scheme = tlsConfiguration == nil ? "http" : "https"
            switch address {
            case .hostname(let hostname, let port):
                return "\(scheme)://\(hostname ?? Self.defaultHostname):\(port ?? Self.defaultPort)"
            case .unixDomainSocket(let socketPath):
                return "\(scheme)+unix: \(socketPath)"
            }
        }
        
        /// Listen backlog.
        public var backlog: Int
        
        /// When `true`, can prevent errors re-binding to a socket after successive server restarts.
        public var reuseAddress: Bool
        
        /// When `true`, OS will attempt to minimize TCP packet delay.
        public var tcpNoDelay: Bool

        /// Response compression configuration.
        public var responseCompression: ResponseCompressionConfiguration

        /// Request decompression configuration.
        public var requestDecompression: RequestDecompressionConfiguration
        
        /// When `true`, HTTP server will support pipelined requests.
        public var supportPipelining: Bool
        
        public var supportVersions: Set<HTTPVersionMajor>
        
        public var tlsConfiguration: TLSConfiguration?
        
        /// If set, this name will be serialized as the `Server` header in outgoing responses.
        public var serverName: String?

        /// When `true`, report http metrics through `swift-metrics`
        public var reportMetrics: Bool

        /// Any uncaught server or responder errors will go here.
        public var logger: Logger

        /// A time limit to complete a graceful shutdown
        public var shutdownTimeout: TimeAmount

        /// An optional callback that will be called instead of using swift-nio-ssl's regular certificate verification logic.
        /// This is the same as `NIOSSLCustomVerificationCallback` but just marked as `Sendable`
        public var customCertificateVerifyCallback: (@Sendable ([NIOSSLCertificate], EventLoopPromise<NIOSSLVerificationResult>) -> Void)?
        
        /// The number of incoming TCP connections to accept per "tick" (i.e. each time through the server's event loop).
        ///
        /// Most users will never need to change this value; its primary use case is to work around benchmarking
        /// artifacts where bursts of connections are created within extremely small intervals. See
        /// https://forums.swift.org/t/standard-vapor-website-drops-1-5-of-requests-even-at-concurrency-of-100/71583/49
        /// for additional information.
        public var connectionsPerServerTick: UInt

        public init(
            hostname: String = Self.defaultHostname,
            port: Int = Self.defaultPort,
            backlog: Int = 256,
            reuseAddress: Bool = true,
            tcpNoDelay: Bool = true,
            responseCompression: ResponseCompressionConfiguration = .disabled,
            requestDecompression: RequestDecompressionConfiguration = .enabled,
            supportPipelining: Bool = true,
            supportVersions: Set<HTTPVersionMajor>? = nil,
            tlsConfiguration: TLSConfiguration? = nil,
            serverName: String? = nil,
            reportMetrics: Bool = true,
            logger: Logger? = nil,
            shutdownTimeout: TimeAmount = .seconds(10),
            customCertificateVerifyCallback: (@Sendable ([NIOSSLCertificate], EventLoopPromise<NIOSSLVerificationResult>) -> Void)? = nil,
            connectionsPerServerTick: UInt = 256
        ) {
            self.init(
                address: .hostname(hostname, port: port),
                backlog: backlog,
                reuseAddress: reuseAddress,
                tcpNoDelay: tcpNoDelay,
                responseCompression: responseCompression,
                requestDecompression: requestDecompression,
                supportPipelining: supportPipelining,
                supportVersions: supportVersions,
                tlsConfiguration: tlsConfiguration,
                serverName: serverName,
                reportMetrics: reportMetrics,
                logger: logger,
                shutdownTimeout: shutdownTimeout,
                customCertificateVerifyCallback: customCertificateVerifyCallback,
                connectionsPerServerTick: connectionsPerServerTick
            )
        }

        public init(
            address: BindAddress,
            backlog: Int = 256,
            reuseAddress: Bool = true,
            tcpNoDelay: Bool = true,
            responseCompression: ResponseCompressionConfiguration = .disabled,
            requestDecompression: RequestDecompressionConfiguration = .enabled,
            supportPipelining: Bool = true,
            supportVersions: Set<HTTPVersionMajor>? = nil,
            tlsConfiguration: TLSConfiguration? = nil,
            serverName: String? = nil,
            reportMetrics: Bool = true,
            logger: Logger? = nil,
            shutdownTimeout: TimeAmount = .seconds(10),
            customCertificateVerifyCallback: (@Sendable ([NIOSSLCertificate], EventLoopPromise<NIOSSLVerificationResult>) -> Void)? = nil,
            connectionsPerServerTick: UInt = 256
        ) {
            self.address = address
            self.backlog = backlog
            self.reuseAddress = reuseAddress
            self.tcpNoDelay = tcpNoDelay
            self.responseCompression = responseCompression
            self.requestDecompression = requestDecompression
            self.supportPipelining = supportPipelining
            if let supportVersions = supportVersions {
                self.supportVersions = supportVersions
            } else {
                self.supportVersions = tlsConfiguration == nil ? [.one] : [.one, .two]
            }
            self.tlsConfiguration = tlsConfiguration
            self.serverName = serverName
            self.reportMetrics = reportMetrics
            self.logger = logger ?? Logger(label: "codes.vapor.http-server")
            self.shutdownTimeout = shutdownTimeout
            self.customCertificateVerifyCallback = customCertificateVerifyCallback
            self.connectionsPerServerTick = connectionsPerServerTick
        }
    }
    
    public var onShutdown: EventLoopFuture<Void> {
        guard let connection = self.connection.withLockedValue({ $0 }) else {
            fatalError("Server has not started yet")
        }
        return connection.channel.closeFuture
    }

    /// The configuration for the HTTP server.
    ///
    /// Many properties of the configuration may be changed both before and after the server has been started.
    ///
    /// However, a warning will be logged and the configuration will be discarded if an option could not be
    /// changed after the server has started. These include the following properties, which are only read
    /// once when the server starts:
    /// - ``Configuration-swift.struct/address``
    /// - ``Configuration-swift.struct/hostname``
    /// - ``Configuration-swift.struct/port``
    /// - ``Configuration-swift.struct/backlog``
    /// - ``Configuration-swift.struct/reuseAddress``
    /// - ``Configuration-swift.struct/tcpNoDelay``
    public var configuration: Configuration {
        get { _configuration.withLockedValue { $0 } }
    }
    
    public func updateConfiguration(_ newConfig: Configuration) async {
        let oldValue = _configuration.withLockedValue { $0 }
        
        let canBeUpdatedDynamically =
            oldValue.address == newConfig.address
            && oldValue.backlog == newConfig.backlog
            && oldValue.connectionsPerServerTick == newConfig.connectionsPerServerTick
            && oldValue.reuseAddress == newConfig.reuseAddress
            && oldValue.tcpNoDelay == newConfig.tcpNoDelay
        
        guard canBeUpdatedDynamically || !didStart.withLockedValue({ $0 }) else {
            oldValue.logger.warning("Cannot modify server configuration after server has been started.")
            return
        }
        await self.application.storage.set(Application.HTTP.Server.ConfigurationKey.self, to: newConfig)
        _configuration.withLockedValue { $0 = newConfig }
    }

    private let responder: Responder
    private let _configuration: NIOLockedValueBox<Configuration>
    private let eventLoopGroup: EventLoopGroup
    private let connection: NIOLockedValueBox<HTTPServerConnection?>
    private let didShutdown: NIOLockedValueBox<Bool>
    private let didStart: NIOLockedValueBox<Bool>
    private let application: Application
    
    public init(
        application: Application,
        responder: Responder,
        configuration: Configuration,
        on eventLoopGroup: EventLoopGroup = MultiThreadedEventLoopGroup.singleton
    ) {
        self.application = application
        self.responder = responder
        self._configuration = .init(configuration)
        self.eventLoopGroup = eventLoopGroup
        self.didStart = .init(false)
        self.didShutdown = .init(false)
        self.connection = .init(nil)
    }
    
    public func start(address: BindAddress?) async throws {
        var configuration = self.configuration
        
        switch address {
        case .none:
            /// Use the configuration as is.
            break
        case .hostname(let hostname, let port):
            /// Override the hostname, port, neither, or both.
            configuration.address = .hostname(hostname ?? configuration.hostname, port: port ?? configuration.port)
        case .unixDomainSocket:
            /// Override the socket path.
            configuration.address = address!
        }
        
        /// Log starting message for debugging before attempting to start the server.
        configuration.logger.debug("Server starting on \(configuration.addressDescription)")

        /// Start the actual `HTTPServer`.
        let serverConnection = try await HTTPServerConnection.start(
            application: self.application,
            server: self,
            responder: self.responder,
            configuration: configuration,
            on: self.eventLoopGroup
        ).get()
        
        self.connection.withLockedValue {
            precondition($0 == nil, "You can't start the server connection twice")
            $0 = serverConnection
        }
        
        /// Overwrite configuration with actual address, if applicable.
        /// They may differ from the provided configuation if port 0 was provided, for example.
        if let localAddress = self.localAddress {
            if let hostname = localAddress.hostname, let port = localAddress.port {
                configuration.address = .hostname(hostname, port: port)
            } else if let pathname = localAddress.pathname {
                configuration.address = .unixDomainSocket(path: pathname)
            }
        }

        /// Log started message with the actual configuration.
        configuration.logger.notice("Server started on \(configuration.addressDescription)")

        await self.updateConfiguration(configuration)
        self.didStart.withLockedValue { $0 = true }
    }
    
    public func shutdown() async {
        guard let connection = self.connection.withLockedValue({ $0 }) else {
            return
        }
        self.configuration.logger.debug("Requesting HTTP server shutdown")
        do {
            try await connection.close(timeout: self.configuration.shutdownTimeout).get()
        } catch {
            self.configuration.logger.error("Could not stop HTTP server: \(error)")
        }
        self.configuration.logger.debug("HTTP server shutting down")
        self.didShutdown.withLockedValue { $0 = true }
        // Make sure we remove the connection reference in case we want to start up again
        self.connection.withLockedValue { $0 = nil }
    }

    public var localAddress: SocketAddress? {
        return self.connection.withLockedValue({ $0 })?.channel.localAddress
    }
    
    deinit {
        let started = self.didStart.withLockedValue { $0 }
        let shutdown = self.didShutdown.withLockedValue { $0 }
        assert(!started || shutdown, "HTTPServer did not shutdown before deinitializing")
    }
}

private final class HTTPServerConnection: Sendable {
    let channel: Channel
    let quiesce: ServerQuiescingHelper
    
    static func start(
        application: Application,
        server: HTTPServer,
        responder: Responder,
        configuration: HTTPServer.Configuration,
        on eventLoopGroup: EventLoopGroup
    ) -> EventLoopFuture<HTTPServerConnection> {
        let quiesce = ServerQuiescingHelper(group: eventLoopGroup)
        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            /// Specify accepts per loop and backlog, and enable `SO_REUSEADDR` for the server itself.
            .serverChannelOption(ChannelOptions.maxMessagesPerRead, value: configuration.connectionsPerServerTick)
            .serverChannelOption(ChannelOptions.backlog, value: Int32(configuration.backlog))
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: configuration.reuseAddress ? SocketOptionValue(1) : SocketOptionValue(0))
            
            /// Set handlers that are applied to the Server's channel.
            .serverChannelInitializer { channel in
                channel.pipeline.addHandler(quiesce.makeServerChannelHandler(channel: channel))
            }
            
            /// Set the handlers that are applied to the accepted Channels.
            .childChannelInitializer { [unowned application, unowned server] channel in
                /// Copy the most up-to-date configuration.
                let configuration = server.configuration

                /// Add TLS handlers if configured.
                if var tlsConfiguration = configuration.tlsConfiguration {
                    /// Prioritize http/2 if supported.
                    if configuration.supportVersions.contains(.two) {
                        tlsConfiguration.applicationProtocols.append("h2")
                    }
                    if configuration.supportVersions.contains(.one) {
                        tlsConfiguration.applicationProtocols.append("http/1.1")
                    }
                    let sslContext: NIOSSLContext
                    let tlsHandler: NIOSSLServerHandler
                    do {
                        sslContext = try NIOSSLContext(configuration: tlsConfiguration)
                        tlsHandler = NIOSSLServerHandler(context: sslContext, customVerifyCallback: configuration.customCertificateVerifyCallback)
                    } catch {
                        configuration.logger.error("Could not configure TLS: \(error)")
                        return channel.close(mode: .all)
                    }
                    return channel.pipeline.addHandler(tlsHandler).flatMap { _ in
                        channel.configureHTTP2SecureUpgrade(h2ChannelConfigurator: { channel in
                            channel.configureHTTP2Pipeline(
                                mode: .server,
                                inboundStreamInitializer: { channel in
                                    return channel.pipeline.addVaporHTTP2Handlers(
                                        application: application,
                                        responder: responder,
                                        configuration: configuration
                                    )
                                }
                            ).map { _ in }
                        }, http1ChannelConfigurator: { channel in
                            return channel.pipeline.addVaporHTTP1Handlers(
                                application: application,
                                responder: responder,
                                configuration: configuration
                            )
                        })
                    }
                } else {
                    guard !configuration.supportVersions.contains(.two) else {
                        fatalError("Plaintext HTTP/2 (h2c) not yet supported.")
                    }
                    return channel.pipeline.addVaporHTTP1Handlers(
                        application: application,
                        responder: responder,
                        configuration: configuration
                    )
                }
            }
            
            /// Enable `TCP_NODELAY` and `SO_REUSEADDR` for the accepted Channels.
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: configuration.tcpNoDelay ? SocketOptionValue(1) : SocketOptionValue(0))
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: configuration.reuseAddress ? SocketOptionValue(1) : SocketOptionValue(0))
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
        
        let channel: EventLoopFuture<Channel>
        switch configuration.address {
        case .hostname:
            channel = bootstrap.bind(host: configuration.hostname, port: configuration.port)
        case .unixDomainSocket(let socketPath):
            channel = bootstrap.bind(unixDomainSocketPath: socketPath)
        }
        
        return channel.map { channel in
            return .init(channel: channel, quiesce: quiesce)
        }.flatMapErrorThrowing { error -> HTTPServerConnection in
            quiesce.initiateShutdown(promise: nil)
            throw error
        }
    }
    
    init(channel: Channel, quiesce: ServerQuiescingHelper) {
        self.channel = channel
        self.quiesce = quiesce
    }
    
    func close(timeout: TimeAmount) -> EventLoopFuture<Void> {
        let promise = self.channel.eventLoop.makePromise(of: Void.self)
        self.channel.eventLoop.scheduleTask(in: timeout) {
            promise.fail(Abort(.internalServerError, reason: "Server stop took too long."))
        }
        self.quiesce.initiateShutdown(promise: promise)
        return promise.futureResult
    }
    
    var onClose: EventLoopFuture<Void> {
        self.channel.closeFuture
    }
    
    deinit {
        assert(!self.channel.isActive, "HTTPServerConnection deinitialized without calling shutdown()")
    }
}

extension HTTPResponseHead {
    /// Determines if the head is purely informational. If a head is informational another head will follow this
    /// head eventually.
    /// 
    /// This is also from SwiftNIO
    var isInformational: Bool {
        100 <= self.status.code && self.status.code < 200 && self.status.code != 101
    }
}

extension ChannelPipeline {
    func addVaporHTTP2Handlers(
        application: Application,
        responder: Responder,
        configuration: HTTPServer.Configuration
    ) -> EventLoopFuture<Void> {
        /// Create server pipeline array.
        var handlers: [ChannelHandler] = []
        
        let http2 = HTTP2FramePayloadToHTTP1ServerCodec()
        handlers.append(http2)
        
        /// Add response compressor as configured.
        handlers.append(configuration.responseCompression.makeCompressor())
        
        /// Add request decompressor if configured.
        switch configuration.requestDecompression.storage {
        case .enabled(let limit):
            let requestDecompressionHandler = NIOHTTPRequestDecompressor(
                limit: limit
            )
            handlers.append(requestDecompressionHandler)
        case .disabled:
            break
        }
        
        /// Add NIO → HTTP request decoder.
        let serverReqDecoder = HTTPServerRequestDecoder(
            application: application
        )
        handlers.append(serverReqDecoder)
        
        /// Add NIO → HTTP response encoder.
        let serverResEncoder = HTTPServerResponseEncoder(
            serverHeader: configuration.serverName,
            dateCache: .eventLoop(self.eventLoop)
        )
        handlers.append(serverResEncoder)
        
        /// Add server request → response delegate.
        let handler = HTTPServerHandler(responder: responder, logger: application.logger)
        handlers.append(handler)
        
        return self.addHandlers(handlers).flatMap {
            /// Close the connection in case of any errors.
            self.addHandler(NIOCloseOnErrorHandler())
        }
    }
    
    func addVaporHTTP1Handlers(
        application: Application,
        responder: Responder,
        configuration: HTTPServer.Configuration
    ) -> EventLoopFuture<Void> {
        /// Create server pipeline array.
        var handlers: [RemovableChannelHandler] = []
        
        /// Configure HTTP/1:
        /// Add http parsing and serializing.
        let httpResEncoder = HTTPResponseEncoder()
        let httpReqDecoder = ByteToMessageHandler(HTTPRequestDecoder(
            leftOverBytesStrategy: .forwardBytes
        ))
        handlers += [httpResEncoder, httpReqDecoder]
        
        /// Add pipelining support if configured.
        if configuration.supportPipelining {
            let pipelineHandler = HTTPServerPipelineHandler()
            handlers.append(pipelineHandler)
        }
        
        /// Add response compressor as configured.
        handlers.append(configuration.responseCompression.makeCompressor())

        /// Add request decompressor if configured.
        switch configuration.requestDecompression.storage {
        case .enabled(let limit):
            let requestDecompressionHandler = NIOHTTPRequestDecompressor(
                limit: limit
            )
            handlers.append(requestDecompressionHandler)
        case .disabled:
            break
        }

        /// Add NIO → HTTP response encoder.
        let serverResEncoder = HTTPServerResponseEncoder(
            serverHeader: configuration.serverName,
            dateCache: .eventLoop(self.eventLoop)
        )
        handlers.append(serverResEncoder)
        
        /// Add NIO → HTTP request decoder.
        let serverReqDecoder = HTTPServerRequestDecoder(
            application: application
        )
        handlers.append(serverReqDecoder)
        /// Add server request → response delegate.
        let handler = HTTPServerHandler(responder: responder, logger: application.logger)

        /// Add HTTP upgrade handler.
        let upgrader = HTTPServerUpgradeHandler(
            httpRequestDecoder: httpReqDecoder,
            httpHandlers: handlers + [handler]
        )

        handlers.append(upgrader)
        handlers.append(handler)
        
        return self.addHandlers(handlers).flatMap {
            /// Close the connection in case of any errors.
            self.addHandler(NIOCloseOnErrorHandler())
        }
    }
}

// MARK: Helper function for constructing NIOSSLServerHandler.
extension NIOSSLServerHandler {
    convenience init(context: NIOSSLContext, customVerifyCallback: NIOSSLCustomVerificationCallback?) {
        if let callback = customVerifyCallback {
            self.init(context: context, customVerificationCallback: callback)
        } else {
            self.init(context: context)
        }
    }
}

// MARK: Response Compression Helpers
extension HTTPServer.Configuration.ResponseCompressionConfiguration {
    func makeCompressor() -> HTTPResponseCompressor {
        HTTPResponseCompressor(initialByteBufferCapacity: storage.initialByteBufferCapacity) { [storage] responseHeaders, isCompressionSupported in
            defer {
                /// Always remove this marker header.
                responseHeaders.headers.remove(name: .xVaporResponseCompression)
            }
            
            /// If compression isn't supported, skip any further processing.
            guard isCompressionSupported else { return .doNotCompress }
            
            /// If we allow overrides, check for the response compression marker header value first before making any further checks:
            if storage.allowRequestOverrides, let responseCompressionHeader = responseHeaders.headers.responseCompression.value {
                switch responseCompressionHeader {
                case .enable: return .compressIfPossible
                case .disable: return .doNotCompress
                case .useDefault: break
                }
            }
            
            switch storage {
            case .enabled(_, let disallowedTypes, _):
                /// If there were no explicit overrides, fallback to checking the content type against the disallowed set. If any type succeeds the check, disable compression:
                let shouldDisable = responseHeaders.headers.parseDirectives(name: .contentType).contains { contentTypeDirectives in
                    guard let mediaType = HTTPMediaType(directives: contentTypeDirectives)
                    else { return false }
                    
                    return disallowedTypes.contains(mediaType)
                }
                
                /// Return `.doNotCompress` if compression should be disabled, or `.compressIfPossible` to allow it.
                return shouldDisable ? .doNotCompress : .compressIfPossible
            case .disabled(_, let allowedTypes, _):
                /// If there were no explicit overrides, fallback to checking the content type against the allowed set. If all types succeed the check, enable compression:
                let shouldEnable = responseHeaders.headers.parseDirectives(name: .contentType).allSatisfy { contentTypeDirectives in
                    guard let mediaType = HTTPMediaType(directives: contentTypeDirectives)
                    else { return false }
                    
                    return allowedTypes.contains(mediaType)
                }
                
                /// Return `.compressIfPossible` if compression should be enabled, or `.doNotCompress` to disallow it.
                return shouldEnable ? .compressIfPossible : .doNotCompress
            }
        }
    }
}
