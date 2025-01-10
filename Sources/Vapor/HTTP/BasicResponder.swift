import NIOCore

/// A basic, closure-based `Responder`.
public struct BasicResponder: Responder {
    /// The stored responder closure.
    private let closure: @Sendable (Request) async throws -> Response

    /// Create a new `BasicResponder`.
    ///
    ///     let notFound: Responder = BasicResponder { req in
    ///         return req.response(http: .init(status: .notFound))
    ///     }
    ///
    /// - parameters:
    ///     - closure: Responder closure.
    public init(
        closure: @Sendable @escaping (Request) async throws -> Response
    ) {
        self.closure = closure
    }

    // See `Responder`.
    public func respond(to request: Request) async throws -> Response {
        return try await closure(request)
    }
}
