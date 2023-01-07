#if compiler(>=5.5) && canImport(_Concurrency)
import NIOCore

/// A basic, async closure-based `Responder`.
@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public struct AsyncBasicResponder: AsyncResponder {
    /// The stored responder closure.
    private let closure: (Request) async throws -> Response

    /// Create a new `BasicResponder`.
    ///
    ///     let notFound: Responder = BasicResponder { req in
    ///         let res = req.response(http: .init(status: .notFound))
    ///         return req.eventLoop.newSucceededFuture(result: res)
    ///     }
    ///
    /// - parameters:
    ///     - closure: Responder closure.
    public init(
        closure: @escaping (Request) async throws -> Response
    ) {
        self.closure = closure
    }

    public func respond(to request: Request) async throws -> Response {
        return try await closure(request)
    }
}

#endif
