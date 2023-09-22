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
        
        /// Listen backlog.
        public var backlog: Int
        
        /// When `true`, can prevent errors re-binding to a socket after successive server restarts.
        public var reuseAddress: Bool
        
        /// When `true`, OS will attempt to minimize TCP packet delay.
        public var tcpNoDelay: Bool

        /// Response compression configuration.
        public var responseCompression: CompressionConfiguration

        /// Supported HTTP compression options.
        public struct CompressionConfiguration: Sendable {
            /// Disables compression. This is the default.
            public static var disabled: Self {
                .init(storage: .disabled)
            }

            /// Enables compression with default configuration.
            public static var enabled: Self {
                .enabled(initialByteBufferCapacity: 1024)
            }

            /// Enables compression with custom configuration.
            public static func enabled(
                initialByteBufferCapacity: Int
            ) -> Self {
                .init(storage: .enabled(
                    initialByteBufferCapacity: initialByteBufferCapacity
                ))
            }

            enum Storage {
                case disabled
                case enabled(initialByteBufferCapacity: Int)
            }

            var storage: Storage
        }

        /// Request decompression configuration.
        public var requestDecompression: DecompressionConfiguration

        /// Supported HTTP decompression options.
        public struct DecompressionConfiguration: Sendable {
            /// Disables decompression. This is the default option.
            public static var disabled: Self {
                .init(storage: .disabled)
            }

            /// Enables decompression with default configuration.
            public static var enabled: Self {
                .enabled(limit: .ratio(10))
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
        @preconcurrency
        public var customCertificateVerifyCallback: (@Sendable ([NIOSSLCertificate], EventLoopPromise<NIOSSLVerificationResult>) -> Void)?

        public init(
            hostname: String = Self.defaultHostname,
            port: Int = Self.defaultPort,
            backlog: Int = 256,
            reuseAddress: Bool = true,
            tcpNoDelay: Bool = true,
            responseCompression: CompressionConfiguration = .disabled,
            requestDecompression: DecompressionConfiguration = .disabled,
            supportPipelining: Bool = true,
            supportVersions: Set<HTTPVersionMajor>? = nil,
            tlsConfiguration: TLSConfiguration? = nil,
            serverName: String? = nil,
            reportMetrics: Bool = true,
            logger: Logger? = nil,
            shutdownTimeout: TimeAmount = .seconds(10)
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
                shutdownTimeout: shutdownTimeout
            )
        }
        
        public init(
            address: BindAddress,
            backlog: Int = 256,
            reuseAddress: Bool = true,
            tcpNoDelay: Bool = true,
            responseCompression: CompressionConfiguration = .disabled,
            requestDecompression: DecompressionConfiguration = .disabled,
            supportPipelining: Bool = true,
            supportVersions: Set<HTTPVersionMajor>? = nil,
            tlsConfiguration: TLSConfiguration? = nil,
            serverName: String? = nil,
            reportMetrics: Bool = true,
            logger: Logger? = nil,
            shutdownTimeout: TimeAmount = .seconds(10)
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
            self.customCertificateVerifyCallback = nil
        }
    }
    
    public var onShutdown: EventLoopFuture<Void> {
        guard let connection = self.connection.withLockedValue({ $0 }) else {
            fatalError("Server has not started yet")
        }
        return connection.channel.closeFuture
    }

    public var configuration: Configuration {
        get { _configuration.withLockedValue { $0 } }
        set {
            guard !didStart.withLockedValue({ $0 }) else {
                _configuration.withLockedValue({ $0 }).logger.warning("Cannot modify server configuration after server has been started.")
                return
            }
            self.application.storage[Application.HTTP.Server.ConfigurationKey.self] = newValue
            _configuration.withLockedValue { $0 = newValue }
        }
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
        on eventLoopGroup: EventLoopGroup
    ) {
        self.application = application
        self.responder = responder
        self._configuration = .init(configuration)
        self.eventLoopGroup = eventLoopGroup
        self.didStart = .init(false)
        self.didShutdown = .init(false)
        self.connection = .init(nil)
    }
    
    public func start(address: BindAddress?) throws {
        var configuration = self.configuration
        
        switch address {
        case .none: // use the configuration as is
            break
        case .hostname(let hostname, let port): // override the hostname, port, neither, or both
            configuration.address = .hostname(hostname ?? configuration.hostname, port: port ?? configuration.port)
        case .unixDomainSocket: // override the socket path
            configuration.address = address!
        }
        
        // print starting message
        let scheme = configuration.tlsConfiguration == nil ? "http" : "https"
        let addressDescription: String
        switch configuration.address {
        case .hostname(let hostname, let port):
            addressDescription = "\(scheme)://\(hostname ?? configuration.hostname):\(port ?? configuration.port)"
        case .unixDomainSocket(let socketPath):
            addressDescription = "\(scheme)+unix: \(socketPath)"
        }
        
        self.configuration.logger.notice("Server starting on \(addressDescription)")

        // start the actual HTTPServer
        try self.connection.withLockedValue {
            $0 = try HTTPServerConnection.start(
                application: self.application,
                responder: self.responder,
                configuration: configuration,
                on: self.eventLoopGroup
            ).wait()
        }

        self.configuration = configuration
        self.didStart.withLockedValue { $0 = true }
    }
    
    public func shutdown() {
        guard let connection = self.connection.withLockedValue({ $0 }) else {
            return
        }
        self.configuration.logger.debug("Requesting HTTP server shutdown")
        do {
            try connection.close(timeout: self.configuration.shutdownTimeout).wait()
        } catch {
            self.configuration.logger.error("Could not stop HTTP server: \(error)")
        }
        self.configuration.logger.debug("HTTP server shutting down")
        self.didShutdown.withLockedValue { $0 = true }
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
        responder: Responder,
        configuration: HTTPServer.Configuration,
        on eventLoopGroup: EventLoopGroup
    ) -> EventLoopFuture<HTTPServerConnection> {
        let quiesce = ServerQuiescingHelper(group: eventLoopGroup)
        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            // Specify backlog and enable SO_REUSEADDR for the server itself
            .serverChannelOption(ChannelOptions.backlog, value: Int32(configuration.backlog))
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: configuration.reuseAddress ? SocketOptionValue(1) : SocketOptionValue(0))
            
            // Set handlers that are applied to the Server's channel
            .serverChannelInitializer { channel in
                channel.pipeline.addHandler(quiesce.makeServerChannelHandler(channel: channel))
            }
            
            // Set the handlers that are applied to the accepted Channels
            .childChannelInitializer { [unowned application] channel in
                // add TLS handlers if configured
                if var tlsConfiguration = configuration.tlsConfiguration {
                    // prioritize http/2
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
            
            // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
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

/// A simple channel handler that catches errors emitted by parsing HTTP requests
/// and sends 400 Bad Request responses.
///
/// This channel handler provides the basic behaviour that the majority of simple HTTP
/// servers want. This handler does not suppress the parser errors: it allows them to
/// continue to pass through the pipeline so that other handlers (e.g. logging ones) can
/// deal with the error.
/// 
/// adapted from: https://github.com/apple/swift-nio/blob/00341c92770e0a7bebdc5fda783f08765eb3ff56/Sources/NIOHTTP1/HTTPServerProtocolErrorHandler.swift
final class HTTP1ServerErrorHandler: ChannelDuplexHandler, RemovableChannelHandler {
    typealias InboundIn = Never
    typealias InboundOut = Never
    typealias OutboundIn = HTTPServerResponsePart
    typealias OutboundOut = HTTPServerResponsePart
    let logger: Logger
    private var hasUnterminatedResponse: Bool = false
    
    init(logger: Logger) {
        self.logger = logger
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        if let error = error as? HTTPParserError {
            self.makeHTTPParserErrorResponse(context: context, error: error)
        }

        // Now pass the error on in case someone else wants to see it.
        // In the Vapor ChannelPipeline the connection will eventually 
        // be closed by the NIOCloseOnErrorHandler
        context.fireErrorCaught(error)
    }

    private func makeHTTPParserErrorResponse(context: ChannelHandlerContext, error: HTTPParserError) {
        // Any HTTPParserError is automatically fatal, and we don't actually need (or want) to
        // provide that error to the client: we just want to inform them something went wrong
        // and then close off the pipeline. However, we can only send an
        // HTTP error response if another response hasn't started yet.
        //
        // A side note here: we cannot block or do any delayed work. 
        // The channel might be closed right after we return from this function.
        if !self.hasUnterminatedResponse {
            self.logger.debug("Bad Request - Invalid HTTP: \(error)")
            let headers = HTTPHeaders([("Connection", "close"), ("Content-Length", "0")])
            let head = HTTPResponseHead(version: .http1_1, status: .badRequest, headers: headers)
            context.write(self.wrapOutboundOut(.head(head)), promise: nil)
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        }
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let res = self.unwrapOutboundIn(data)
        switch res {
        case .head(let head) where head.isInformational:
            precondition(!self.hasUnterminatedResponse)
        case .head:
            precondition(!self.hasUnterminatedResponse)
            self.hasUnterminatedResponse = true
        case .body:
            precondition(self.hasUnterminatedResponse)
        case .end:
            precondition(self.hasUnterminatedResponse)
            self.hasUnterminatedResponse = false
        }
        context.write(data, promise: promise)
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
        // create server pipeline array
        var handlers: [ChannelHandler] = []
        
        let http2 = HTTP2FramePayloadToHTTP1ServerCodec()
        handlers.append(http2)
        
        // add NIO -> HTTP request decoder
        let serverReqDecoder = HTTPServerRequestDecoder(
            application: application
        )
        handlers.append(serverReqDecoder)
        
        // add NIO -> HTTP response encoder
        let serverResEncoder = HTTPServerResponseEncoder(
            serverHeader: configuration.serverName,
            dateCache: .eventLoop(self.eventLoop)
        )
        handlers.append(serverResEncoder)
        
        // add server request -> response delegate
        let handler = HTTPServerHandler(responder: responder, logger: application.logger)
        handlers.append(handler)
        
        return self.addHandlers(handlers).flatMap {
            // close the connection in case of any errors
            self.addHandler(NIOCloseOnErrorHandler())
        }
    }
    
    func addVaporHTTP1Handlers(
        application: Application,
        responder: Responder,
        configuration: HTTPServer.Configuration
    ) -> EventLoopFuture<Void> {
        // create server pipeline array
        var handlers: [RemovableChannelHandler] = []
        
        // configure HTTP/1
        // add http parsing and serializing
        let httpResEncoder = HTTPResponseEncoder()
        let httpReqDecoder = ByteToMessageHandler(HTTPRequestDecoder(
            leftOverBytesStrategy: .forwardBytes
        ))
        handlers += [httpResEncoder, httpReqDecoder]
        
        // add pipelining support if configured
        if configuration.supportPipelining {
            let pipelineHandler = HTTPServerPipelineHandler()
            handlers.append(pipelineHandler)
        }
        
        // add response compressor if configured
        switch configuration.responseCompression.storage {
        case .enabled(let initialByteBufferCapacity):
            let responseCompressionHandler = HTTPResponseCompressor(
                initialByteBufferCapacity: initialByteBufferCapacity
            )
            handlers.append(responseCompressionHandler)
        case .disabled:
            break
        }

        // add request decompressor if configured
        switch configuration.requestDecompression.storage {
        case .enabled(let limit):
            let requestDecompressionHandler = NIOHTTPRequestDecompressor(
                limit: limit
            )
            handlers.append(requestDecompressionHandler)
        case .disabled:
            break
        }

        let errorHandler = HTTP1ServerErrorHandler(logger: configuration.logger)
        handlers.append(errorHandler)

        // add NIO -> HTTP response encoder
        let serverResEncoder = HTTPServerResponseEncoder(
            serverHeader: configuration.serverName,
            dateCache: .eventLoop(self.eventLoop)
        )
        handlers.append(serverResEncoder)
        
        // add NIO -> HTTP request decoder
        let serverReqDecoder = HTTPServerRequestDecoder(
            application: application
        )
        handlers.append(serverReqDecoder)
        // add server request -> response delegate
        let handler = HTTPServerHandler(responder: responder, logger: application.logger)

        // add HTTP upgrade handler
        let upgrader = HTTPServerUpgradeHandler(
            httpRequestDecoder: httpReqDecoder,
            httpHandlers: handlers + [handler]
        )

        handlers.append(upgrader)
        handlers.append(handler)
        
        return self.addHandlers(handlers).flatMap {
            // close the connection in case of any errors
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
