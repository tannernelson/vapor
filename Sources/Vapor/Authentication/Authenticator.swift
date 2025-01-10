import NIOCore

/// Capable of being authenticated.
public protocol Authenticatable { }

/// Helper for creating authentication middleware.
///
/// See `RequestAuthenticator` and `SessionAuthenticator` for more information.
public protocol Authenticator: Middleware { }

/// Help for creating authentication middleware based on `Request`.
///
/// `Authenticator`'s use the incoming request to check for authentication information.
/// If valid authentication credentials are present, the authenticated user is added to `req.auth`.
public protocol RequestAuthenticator: Authenticator {
    func authenticate(request: Request) async throws -> Void
}

extension RequestAuthenticator {
    public func respond(to request: Request, chainingTo next: Responder) async throws -> Response {
        try await self.authenticate(request: request)
        return try await next.respond(to: request)
    }
}

// MARK: Basic

/// Helper for creating authentication middleware using the Basic authorization header.
public protocol BasicAuthenticator: RequestAuthenticator {
    func authenticate(basic: BasicAuthorization, for request: Request) async throws -> Void
}

extension BasicAuthenticator {
    public func authenticate(request: Request) async throws -> Void {
        guard let basicAuthorization = request.headers.basicAuthorization else {
            return
        }
        return try await self.authenticate(basic: basicAuthorization, for: request)
    }
}

// MARK: Bearer

/// Helper for creating authentication middleware using the Bearer authorization header.
public protocol BearerAuthenticator: RequestAuthenticator {
    func authenticate(bearer: BearerAuthorization, for request: Request) async throws -> Void
}

extension BearerAuthenticator {
    public func authenticate(request: Request) async throws -> Void {
        guard let bearerAuthorization = request.headers.bearerAuthorization else {
            return
        }
        return try await self.authenticate(bearer: bearerAuthorization, for: request)
    }
}

// MARK: Credentials

/// Helper for creating authentication middleware using request body contents.
public protocol CredentialsAuthenticator: RequestAuthenticator {
    associatedtype Credentials: Content
    func authenticate(credentials: Credentials, for request: Request) async throws -> Void
}

extension CredentialsAuthenticator {
    public func authenticate(request: Request) async throws -> Void {
#warning("TODO")
        try await request.body.collect(max: nil).get()
        let credentials: Credentials
        do {
            credentials = try request.content.decode(Credentials.self)
        } catch {
            return
        }
        return try await self.authenticate(credentials: credentials, for: request)
    }
}
