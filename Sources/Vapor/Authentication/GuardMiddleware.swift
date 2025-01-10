import NIOCore
import NIOHTTP1

extension Authenticatable {
    /// This middleware ensures that an `Authenticatable` type `A` has been authenticated
    /// by a previous `Middleware` or throws an `Error`. The middlewares that actually perform
    /// authentication will _not_ throw errors if they fail to authenticate the user (except in
    /// some exceptional cases like malformed data). This allows the middlewares to be composed
    /// together to create chains of authentication for multiple user types.
    ///
    /// Use this middleware to protect routes that might not otherwise attempt to access the
    /// authenticated user (which always requires prior authentication).
    ///
    /// Use `Authenticatable.guardMiddleware(...)` to create an instance.
    ///
    /// Use this middleware in conjunction with other middleware such as `BearerAuthenticator`
    /// and `BasicAuthenticator` to do the actual authentication.
    ///
    /// - parameters:
    ///     - throwing: `Error` to throw if the type is not authed.
    public static func guardMiddleware(
        throwing error: Error = Abort(.unauthorized, reason: "\(Self.self) not authenticated.")
    ) -> Middleware {
        return GuardAuthenticationMiddleware<Self>(throwing: error)
    }
}



private final class GuardAuthenticationMiddleware<A>: Middleware
    where A: Authenticatable
{
    /// Error to throw when guard fails.
    private let error: Error

    /// Creates a new `GuardAuthenticationMiddleware`.
    ///
    /// - parameters:
    ///     - type: `Authenticatable` type to ensure is authed.
    ///     - error: `Error` to throw if the type is not authed.
    internal init(_ type: A.Type = A.self, throwing error: Error) {
        self.error = error
    }

    public func respond(to request: Request, chainingTo next: Responder) async throws -> Response {
        guard await request.auth.has(A.self) else {
            throw self.error
        }
        return try await next.respond(to: request)
    }
}
