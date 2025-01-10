import NIOCore
import Logging

/// Emits a log message containing the request method and path to a `Request`'s logger.
/// The log level of the message is configurable.
public final class RouteLoggingMiddleware: Middleware {
    public let logLevel: Logger.Level
    
    public init(logLevel: Logger.Level = .info) {
        self.logLevel = logLevel
    }
    
    public func respond(to request: Request, chainingTo next: any Responder) async throws -> Response {
        request.logger.log(level: self.logLevel, "\(request.method) \(request.url.path.removingPercentEncoding ?? request.url.path)")
        return try await next.respond(to: request)
    }
}
