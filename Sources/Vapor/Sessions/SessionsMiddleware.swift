import NIOCore

/// Uses HTTP cookies to save and restore sessions for connecting clients.
///
/// If a cookie matching the configured cookie name is found on an incoming request,
/// the value will be used as an identifier to find the associated `Session`.
///
/// If a session is used during a request (`Request.session()`), a cookie will be set
/// on the outgoing response with the session's unique identifier. This cookie must be
/// returned on the next request to restore the session.
///
///     app.middleware.use(app.sessions.middleware)
///
/// See `SessionsConfig` and `Sessions` for more information.
public final class SessionsMiddleware: Middleware {
    /// The cookie to work with
    let configuration: SessionsConfiguration

    /// Session store.
    public let session: SessionDriver

    /// Creates a new `SessionsMiddleware`.
    ///
    /// - parameters:
    ///     - sessions: `Sessions` implementation to use for fetching and storing sessions.
    ///     - configuration: `SessionsConfiguration` to use for naming and creating cookie values.
    public init(
        session: SessionDriver,
        configuration: SessionsConfiguration = .default()
    ) {
        self.session = session
        self.configuration = configuration
    }

    public func respond(to request: Request, chainingTo next: Responder) async throws -> Response {
        // Signal middleware has been added.
        await request._sessionCache.setMiddlewareFlag()

        // Check for an existing session
        if let cookieValue = request.cookies[self.configuration.cookieName] {
            // A cookie value exists, get the session for it.
            let id = SessionID(string: cookieValue.string)
            let data = try await self.session.readSession(id, for: request)
            if let data = data {
                // Session found, restore data and id.
                await request._sessionCache.setSession(.init(id: id, data: data))
            } else {
                // Session id not found, create new session.
                await request._sessionCache.setSession(.init())
            }
            let response = try await next.respond(to: request)
            return try await self.addCookies(to: response, for: request)
        } else {
            // No cookie value exists, simply respond.
            let response = try await next.respond(to: request)
            return try await self.addCookies(to: response, for: request)
        }
    }

    /// Adds session cookie to response or clears if session was deleted.
#warning("Do we need to pass request everywhere?")
    private func addCookies(to response: Response, for request: Request) async throws -> Response {
        if let session = await request._sessionCache.session, await session.isValid {
            // A session exists or has been created. we must
            // set a cookie value on the response
            let sessionID: SessionID
            if let id = await session.id {
                // A cookie exists, just update this session.
                sessionID = try await self.session.updateSession(id, to: session.data, for: request)
            } else {
                // No cookie, this is a new session.
                sessionID = try await self.session.createSession(session.data, for: request)
            }

            // After create or update, set cookie on the response.
            response.cookies[self.configuration.cookieName] = self.configuration.cookieFactory(sessionID, session)
            return response
        } else if let cookieValue = request.cookies[self.configuration.cookieName] {
            // The request had a session cookie, but now there is no valid session.
            // we need to perform cleanup.
            let id = SessionID(string: cookieValue.string)
            try await self.session.deleteSession(id, for: request)
            response.cookies[self.configuration.cookieName] = .expired
            return response
        } else {
            // no session or existing cookie
            return response
        }
    }
}
