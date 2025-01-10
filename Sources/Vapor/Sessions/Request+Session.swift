extension Request {
    /// Returns the current `Session` or creates one.
    ///
    ///     router.get("session") { req -> String in
    ///         req.session.data["name"] = "Vapor"
    ///         return "Session set"
    ///     }
    ///
    /// - note: `SessionsMiddleware` must be added and enabled.
    /// - returns: `Session` for this `Request`.
    public var session: Session {
        get async {
            if await !self._sessionCache.middlewareFlag {
                // No `SessionsMiddleware` was detected on your app.
                // Suggested solutions:
                // - Add the `SessionsMiddleware` globally to your app using `app.middleware.use`
                // - Add the `SessionsMiddleware` to a route group.
                assertionFailure("No `SessionsMiddleware` detected.")
            }
            if let existing = await self._sessionCache.session {
                return existing
            } else {
                let new = Session()
                await self._sessionCache.setSession(new)
                return new
            }
        }
    }
    
    public var hasSession: Bool {
        get async {
            await self._sessionCache.session != nil
        }
    }

    private struct SessionCacheKey: StorageKey {
        typealias Value = SessionCache
    }
    
    internal var _sessionCache: SessionCache {
        if let existing = self.storage[SessionCacheKey.self] {
            return existing
        } else {
            let new = SessionCache()
            self.storage.setFirstTime(SessionCacheKey.self, to: new)
            return new
        }
    }
}
