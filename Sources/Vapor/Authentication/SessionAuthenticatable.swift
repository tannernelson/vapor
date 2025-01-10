import NIOCore

/// Helper for creating authentication middleware in conjunction with `SessionsMiddleware`.
public protocol SessionAuthenticator: Authenticator {
    associatedtype User: SessionAuthenticatable

    /// Authenticate a model with the supplied ID.
    func authenticate(sessionID: User.SessionID, for request: Request) async throws -> Void
}

extension SessionAuthenticator {
    public func respond(to request: Request, chainingTo next: Responder) async throws -> Response {
        // if the user has already been authenticated
        // by a previous middleware, continue
        if await request.auth.has(User.self) {
            return try await next.respond(to: request)
        }

        if let aID = await request.session.authenticated(User.self) {
            // try to find user with id from session
            try await self.authenticate(sessionID: aID, for: request)
        }
        
        let response = try await next.respond(to: request)

        if let user = await request.auth.get(User.self) {
            // if a user has been authed (or is still authed), store in the session
            await request.session.authenticate(user)
        } else if await request.hasSession {
            // if no user is authed, it's possible they've been unauthed.
            // remove from session.
            await request.session.unauthenticate(User.self)
        }
        return response
    }
}

/// Models conforming to this protocol can have their authentication
/// status cached using `SessionAuthenticator`.
public protocol SessionAuthenticatable: Authenticatable {
    /// Session identifier type.
    associatedtype SessionID: LosslessStringConvertible, Sendable

    /// Unique session identifier.
    var sessionID: SessionID { get }
}

private extension SessionAuthenticatable {
    static var sessionName: String {
        return "\(Self.self)"
    }
}

extension Session {
    /// Authenticates the model into the session.
    public func authenticate<A>(_ a: A)
        where A: SessionAuthenticatable
    {
        self.data["_" + A.sessionName + "Session"] = a.sessionID.description
    }

    /// Un-authenticates the model from the session.
    public func unauthenticate<A>(_ a: A.Type)
        where A: SessionAuthenticatable
    {
        self.data["_" + A.sessionName + "Session"] = nil
    }

    /// Returns the authenticatable type's ID if it exists
    /// in the session data.
    public func authenticated<A>(_ a: A.Type) -> A.SessionID?
        where A: SessionAuthenticatable
    {
        self.data["_" + A.sessionName + "Session"]
            .flatMap { A.SessionID.init($0) }
    }
}
