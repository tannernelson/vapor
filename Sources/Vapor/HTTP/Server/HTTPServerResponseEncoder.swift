import NIOCore
import NIOHTTP1
import NIOConcurrencyHelpers

final class HTTPServerResponseEncoder: ChannelOutboundHandler, RemovableChannelHandler {
    typealias OutboundIn = Response
    typealias OutboundOut = HTTPServerResponsePart
    
    /// Optional server header.
    private let serverHeader: String?
    private let dateCache: RFC1123DateCache

    struct ResponseEndSentEvent { }
    
    init(serverHeader: String?, dateCache: RFC1123DateCache) {
        self.serverHeader = serverHeader
        self.dateCache = dateCache
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let response = self.unwrapOutboundIn(data)
        var headOrNoContentRequest = false
        response.responseBox.withLockedValue { box in
            // add a RFC1123 timestamp to the Date header to make this
            // a valid request
            box.headers.add(name: "date", value: self.dateCache.currentTimestamp())
            if let server = self.serverHeader {
                box.headers.add(name: "server", value: server)
            }
            
            // begin serializing
            let responseHead = HTTPResponseHead(version: box.version, status: box.status, headers: box.headers)
            context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
            
            if box.status == .noContent || box.forHeadRequest {
                headOrNoContentRequest = true
            }
        }
        
        if headOrNoContentRequest {
            // don't send bodies for 204 (no content) responses
            // or HEAD requests
            context.fireUserInboundEventTriggered(ResponseEndSentEvent())
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: promise)
        } else {
            switch response.body.storage {
            case .none:
                context.fireUserInboundEventTriggered(ResponseEndSentEvent())
                context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: promise)
            case .buffer(let buffer):
                self.writeAndflush(buffer: buffer, context: context, promise: promise)
            case .string(let string):
                let buffer = context.channel.allocator.buffer(string: string)
                self.writeAndflush(buffer: buffer, context: context, promise: promise)
            case .staticString(let string):
                let buffer = context.channel.allocator.buffer(staticString: string)
                self.writeAndflush(buffer: buffer, context: context, promise: promise)
            case .data(let data):
                let buffer = context.channel.allocator.buffer(bytes: data)
                self.writeAndflush(buffer: buffer, context: context, promise: promise)
//            case .dispatchData(let data):
//                let buffer = context.channel.allocator.buffer(dispatchData: data)
//                self.writeAndflush(buffer: buffer, context: context, promise: promise)
            case .stream(let stream):
                let channelStream = ChannelResponseBodyStream(
                    context: context,
                    handler: self,
                    promise: promise,
                    count: stream.count == -1 ? nil : stream.count
                )
                stream.callback(channelStream)
            case .asyncStream(let stream):
                let channelStream = ChannelResponseBodyStream(
                    context: context,
                    handler: self,
                    promise: promise,
                    count: stream.count == -1 ? nil : stream.count
                )
                
                Task {
                    do {
                        try await stream.callback(channelStream)
                        // We assert in ChannelResponseBodyStream that either .end or .error gets sent, so once we
                        // get here the promise can be assumed to already be completed. However, just in case, succeed
                        // it here anyway. This guarantees we never leave the callback without completing the promise
                        // one way or the other in release builds.
                        promise?.succeed()
                    } catch {
                        promise?.fail(error)
                    }
                }
            }
        }
    }
    
    /// Writes a `ByteBuffer` to the context.
    private func writeAndflush(buffer: ByteBuffer, context: ChannelHandlerContext, promise: EventLoopPromise<Void>?) {
        if buffer.readableBytes > 0 {
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }
        context.fireUserInboundEventTriggered(ResponseEndSentEvent())
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: promise)
    }
}

private final class ChannelResponseBodyStream: BodyStreamWriter, AsyncBodyStreamWriter {
    let contextBox: NIOLoopBound<ChannelHandlerContext>
    let handlerBox: NIOLoopBound<HTTPServerResponseEncoder>
    let promise: EventLoopPromise<Void>?
    let count: Int?
    let currentCount: NIOLoopBoundBox<Int>
    let isComplete: NIOLockedValueBox<Bool>
    let eventLoop: EventLoop

    enum Error: Swift.Error {
        case tooManyBytes
        case notEnoughBytes
        case apiMisuse // tried to send a buffer or end indication after already ending or erroring the stream
    }

    init(
        context: ChannelHandlerContext,
        handler: HTTPServerResponseEncoder,
        promise: EventLoopPromise<Void>?,
        count: Int?
    ) {
        context.eventLoop.assertInEventLoop()
        
        self.contextBox = .init(context, eventLoop: context.eventLoop)
        self.handlerBox = .init(handler, eventLoop: context.eventLoop)
        self.promise = promise
        self.count = count
        self.currentCount = .init(0, eventLoop: context.eventLoop)
        self.isComplete = .init(false)
        self.eventLoop = context.eventLoop
    }
    
    func write(_ result: BodyStreamResult) async throws {
        let promise = self.eventLoop.makePromise(of: Void.self)
        
        self.eventLoop.execute { self.write(result, promise: promise) }
        try await promise.futureResult.get()
    }
    
    /// > Note: `self.promise` is the promise that completes the original write to `HTTPServerResponseEncoder` that
    /// > triggers the streaming response; it should only be succeeded when the stream ends. The `promise` parameter
    /// > of this method is specific to the particular invocation and signals that a buffer has finished writing or
    /// > that the stream has been fully completed, and should always be completed or pending completion by the time
    /// > this method returns. Both promises should be failed when an error occurs, unless otherwise specifically noted.
    func write(_ result: BodyStreamResult, promise: EventLoopPromise<Void>?) {
        self.eventLoop.assertInEventLoop() // Only check in debug, just in case...

        func finishStream() {
            self.isComplete.withLockedValue { $0 = true }
            self.contextBox.value.fireUserInboundEventTriggered(HTTPServerResponseEncoder.ResponseEndSentEvent())
            // Don't forward the current promise (if any) to the write completion of the end-response signal, as we
            // will be notified of errors through other paths and can get spurious I/O errors from this write that
            // ought to be ignored.
            self.contextBox.value.writeAndFlush(self.handlerBox.value.wrapOutboundOut(.end(nil)), promise: nil)
        }

        // See https://github.com/vapor/vapor/issues/2976 for why we do some of these checks.
        switch result {
        case .buffer(let buffer):
            guard !self.isComplete.withLockedValue({ $0 }) else { // Don't try to send data if we already ended
                return promise?.fail(Error.apiMisuse) ?? () // self.promise is already completed, so fail the local one and bail
            }
            if let count = self.count, (self.currentCount.value + buffer.readableBytes) > count {
                self.promise?.fail(Error.tooManyBytes)
                promise?.fail(Error.tooManyBytes)
            } else {
                self.currentCount.value += buffer.readableBytes
                // Cascade the completion of the buffer write to the local promise (if any).
                self.contextBox.value.writeAndFlush(self.handlerBox.value.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: promise)
            }
        case .end:
            if !self.isComplete.withLockedValue({ $0 }) { // Don't send the response end events more than once.
                finishStream()
                // check this only after sending the stream end; we want to make send that regardless
                if let count = self.count, self.currentCount.value < count {
                    self.promise?.fail(Error.notEnoughBytes)
                    promise?.fail(Error.notEnoughBytes)
                } else {
                    self.promise?.succeed()
                    promise?.succeed()
                }
            } else {
                promise?.fail(Error.apiMisuse) // If we already ended, fail the local promise with API misuse
            }
        case .error(let error):
            if !self.isComplete.withLockedValue({ $0 }) { // Don't send the response end events more than once.
                finishStream()
                self.promise?.fail(error)
            }
            promise?.fail(error) // We want to fail the local promise regardless. Echo the error back.
        }
    }

    deinit {
        assert(self.isComplete.withLockedValue { $0 }, "Response body stream writer deinitialized before .end or .error was sent.")
    }
}
