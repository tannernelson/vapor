import NIOCore
import Logging

final class HTTPServerHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = Request
    typealias OutboundOut = Response
    
    let responder: Responder
    let logger: Logger
    var isShuttingDown: Bool
    
    init(responder: Responder, logger: Logger) {
        self.responder = responder
        self.logger = logger
        self.isShuttingDown = false
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let box = NIOLoopBound((context, self), eventLoop: context.eventLoop)
        let request = self.unwrapInboundIn(data)
        // hop(to:) is required here to ensure we're on the correct event loop
        let responder = self.responder
        context.eventLoop.makeFutureWithTask {
            try await responder.respond(to: request)
        }.hop(to: context.eventLoop).whenComplete { response in
            let (context, handler) = box.value
            handler.serialize(response, for: request, context: context)
        }
    }
    
    func serialize(_ response: Result<Response, Error>, for request: Request, context: ChannelHandlerContext) {
        switch response {
        case .failure(let error):
            self.errorCaught(context: context, error: error)
        case .success(let response):
            if request.method == .HEAD {
                response.responseBox.withLockedValue { $0.forHeadRequest = true }
            }
            self.serialize(response, for: request, context: context)
        }
    }
    
    func serialize(_ response: Response, for request: Request, context: ChannelHandlerContext) {
        switch request.version.major {
        case 2:
            context.write(self.wrapOutboundOut(response), promise: nil)
        default:
            let keepAlive = !self.isShuttingDown && request.requestBox.withLockedValue({ $0.isKeepAlive })
            if self.isShuttingDown {
                self.logger.debug("In-flight request has completed")
            }
            response.headers.add(name: .connection, value: keepAlive ? "keep-alive" : "close")
            let done = context.write(self.wrapOutboundOut(response))
            let box = NIOLoopBound((context, self), eventLoop: context.eventLoop)
            done.whenComplete { result in
                let (context, handler) = box.value
                switch result {
                case .success:
                    if !keepAlive {
                        context.close(mode: .output, promise: nil)
                    }
                case .failure(let error):
                    if case .stream(let stream) = response.body.storage {
                        stream.callback(ErrorBodyStreamWriter(eventLoop: request.eventLoop, error: error))
                    } else if case .asyncStream(let stream) = response.body.storage {
                        Task {
                            try? await stream.callback(ErrorBodyStreamWriter(eventLoop: request.eventLoop, error: error))
                        }
                    }
                    handler.errorCaught(context: context, error: error)
                }
            }
        }
    }
    
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case is ChannelShouldQuiesceEvent:
            self.logger.trace("HTTP handler will no longer respect keep-alive")
            self.isShuttingDown = true
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }
}

fileprivate struct ErrorBodyStreamWriter: BodyStreamWriter, AsyncBodyStreamWriter {
    let eventLoop: EventLoop
    let error: Error
    
    func write(_ result: BodyStreamResult, promise: EventLoopPromise<Void>?) {
        promise?.fail(error)
    }
    
    func write(_ result: BodyStreamResult) async throws {
        throw error
    }
}
