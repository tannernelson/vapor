import NIOConcurrencyHelpers

/// Singleton service cache for a `Session`. Used with a message's private container.
internal actor SessionCache: Sendable {
    /// Set to `true` when passing through middleware.
    var middlewareFlag: Bool

    /// The cached session.
    var session: Session?

    /// Creates a new `SessionCache`.
    init(session: Session? = nil) {
        self.session = session
        self.middlewareFlag = false
    }
    
    func setSession(_ session: Session) {
        self.session = session
    }
    
    func setMiddlewareFlag() {
        self.middlewareFlag = true
    }
}
