import NIOCore
import NIOConcurrencyHelpers

// MARK: - Request.Body.AsyncSequenceDelegate
extension Request.Body {
    
    /// `Request.Body.AsyncSequenceDelegate` bridges between EventLoop
    /// and AsyncSequence. Crucially, this type handles backpressure
    /// by synchronizing bytes on the `EventLoop`
    ///
    /// `AsyncSequenceDelegate` can be created and **must be retained**
    /// in `Request.Body/makeAsyncIterator()` method.
    fileprivate final class AsyncSequenceDelegate: @unchecked Sendable, NIOAsyncSequenceProducerDelegate {
        private enum State {
            case notCalledYet
            case noSignalReceived
            case waitingForSignalFromConsumer(EventLoopPromise<Void>)
        }

        private var _state: State = .notCalledYet
        private let eventLoop: any EventLoop

        init(eventLoop: any EventLoop) {
            self.eventLoop = eventLoop
        }

        private func produceMore0() {
            self.eventLoop.preconditionInEventLoop()
            switch self._state {
            case .notCalledYet:
                // We can just return here to sign to the producer that we want more data
                break
            case .noSignalReceived:
                preconditionFailure()
            case .waitingForSignalFromConsumer(let promise):
                self._state = .noSignalReceived
                promise.succeed(())
            }
        }

        private func didTerminate0() {
            self.eventLoop.preconditionInEventLoop()
            switch self._state {
            case .notCalledYet:
                // Means didn't hit the backpressure limits, so just return
                break
            case .noSignalReceived:
                // we will inform the producer, since the next write will fail.
                break
            case .waitingForSignalFromConsumer(let promise):
                self._state = .noSignalReceived
                promise.fail(CancellationError())
            }
        }

        func registerBackpressurePromise(_ promise: EventLoopPromise<Void>) {
            self.eventLoop.preconditionInEventLoop()
            switch self._state {
            case .noSignalReceived, .notCalledYet:
                self._state = .waitingForSignalFromConsumer(promise)
            case .waitingForSignalFromConsumer:
                preconditionFailure()
            }
        }

        func didTerminate() {
            self.eventLoop.execute { self.didTerminate0() }
        }

        func produceMore() {
            self.eventLoop.execute { self.produceMore0() }
        }
    }
}

// MARK: - Request.Body.AsyncSequence
extension Request.Body: AsyncSequence {
    public typealias Element = ByteBuffer
    
    /// This wrapper generalizes our implementation.
    /// `RequestBody.AsyncIterator` is the override point for
    /// using another implementation
    public struct AsyncIterator: AsyncIteratorProtocol {
        public typealias Element = ByteBuffer

        fileprivate typealias Underlying = NIOThrowingAsyncSequenceProducer<ByteBuffer, any Error, NIOAsyncSequenceProducerBackPressureStrategies.HighLowWatermark, Request.Body.AsyncSequenceDelegate>.AsyncIterator

        private var underlying: Underlying

        fileprivate init(underlying: Underlying) {
            self.underlying = underlying
        }

        public mutating func next() async throws -> ByteBuffer? {
            return try await self.underlying.next()
        }
    }
    
    /// Checks that the request has a body suitable for an AsyncSequence
    ///
    /// AsyncSequence streaming should use a body of type .stream().
    /// Using `.collected(_)` will load the entire request into memory
    /// which should be avoided for large file uploads.
    ///
    /// Example: app.on(.POST, "/upload", body: .stream) { ... }
    private func checkBodyStorage() {
        switch request.bodyStorage.withLockedValue({ $0 }) {
        case .stream(_):
            break
        case .collected(_):
            break
        default:
            preconditionFailure("""
            AsyncSequence streaming should use a body of type .stream()
            Example: app.on(.POST, "/upload", body: .stream) { ... }
           """)
        }
    }
    
    /// Generates an `AsyncIterator` to stream the body’s content as
    /// `ByteBuffer` sequences. This implementation supports backpressure using
    /// `NIOAsyncSequenceProducerBackPressureStrategies`
    /// - Returns: `AsyncIterator` containing the `Request.Body` as a
    /// `ByteBuffer` sequence
    public func makeAsyncIterator() -> AsyncIterator {
        let delegate = AsyncSequenceDelegate(eventLoop: request.eventLoop)
        
        let producer = NIOThrowingAsyncSequenceProducer.makeSequence(
            elementType: ByteBuffer.self,
            failureType: Error.self,
            backPressureStrategy: NIOAsyncSequenceProducerBackPressureStrategies
                .HighLowWatermark(lowWatermark: 5, highWatermark: 20),
            finishOnDeinit: true,
            delegate: delegate
        )
        
        let source = producer.source
        
        self.drain { streamResult in
            switch streamResult {
            case .buffer(let buffer):
                // Send the buffer to the async sequence
                let result = source.yield(buffer)
                // Inspect the source view and handle outcomes
                switch result {
                case .dropped:
                    // The consumer dropped the sequence.
                    // Inform the producer that we don't want more data
                    // by returning an error in the future.
                    delegate.didTerminate()
                    return request.eventLoop.makeFailedFuture(CancellationError())
                case .stopProducing:
                    // The consumer is too slow.
                    // We need to create a promise that we succeed later.
                    let promise = request.eventLoop.makePromise(of: Void.self)
                    // We pass the promise to the delegate so that we can succeed it,
                    // once we get a call to `delegate.produceMore()`.
                    delegate.registerBackpressurePromise(promise)
                    // return the future that we will fulfill eventually.
                    return promise.futureResult
                case .produceMore:
                    // We can produce more immediately. Return a succeeded future.
                    return request.eventLoop.makeSucceededVoidFuture()
                }
            case .error(let error):
                source.finish(error)
                return request.eventLoop.makeSucceededVoidFuture()
            case .end:
                source.finish()
                return request.eventLoop.makeSucceededVoidFuture()
            }
        }
        
        return AsyncIterator(underlying: producer.sequence.makeAsyncIterator())
    }
}
