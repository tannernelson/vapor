import NIOCore

extension Request {
    public struct Body: CustomStringConvertible, Sendable {
        let request: Request
        
        init(_ request: Request) {
            self.request = request
        }
        
        public var data: ByteBuffer? {
            switch self.request.bodyStorage.withLockedValue({ $0 }) {
            case .collected(let buffer): return buffer
            case .none, .stream: return nil
            }
        }
        
        public var string: String? {
            if var data = self.data {
                return data.readString(length: data.readableBytes)
            } else {
                return nil
            }
        }
        
        public func drain(_ handler: @Sendable @escaping (BodyStreamResult) -> EventLoopFuture<Void>) {
            switch self.request.bodyStorage.withLockedValue({ $0 }) {
            case .stream(let stream):
                stream.read { (result, promise) in
                    handler(result).cascade(to: promise)
                }
            case .collected(let buffer):
                _ = handler(.buffer(buffer))
                    .map {
                        handler(.end)
                    }
            case .none:
                _ = handler(.end)
            }
        }
        
#warning("Fix")
        public func collect(max: Int? = 1 << 14) -> EventLoopFuture<ByteBuffer?> {
            switch self.request.bodyStorage.withLockedValue({ $0 }) {
            case .stream(let stream):
                return stream.consume(max: max, on: self.request.eventLoop).map { buffer in
                    self.request.bodyStorage.withLockedValue({ $0 = .collected(buffer) })
                    return buffer
                }
            case .collected(let buffer):
                return self.request.eventLoop.makeSucceededFuture(buffer)
            case .none:
                return self.request.eventLoop.makeSucceededFuture(nil)
            }
        }
        
        public var description: String {
            if var data = self.data,
               let description = data.readString(length: data.readableBytes) {
                return description
            } else {
                return ""
            }
        }
    }
}
