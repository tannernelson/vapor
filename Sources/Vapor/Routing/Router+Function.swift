extension Router {
    // MARK: Middleware Function
    
    /// Creates a sub `Router` wrapped in the supplied middleware function.
    ///
    ///     let group = router.grouped { req, next in
    ///         // this closure will be called with each request
    ///         print(req)
    ///         // use next responder in chain to respond
    ///         return try next.respond(to: req)
    ///     }
    ///     group.get("/") { ... }
    ///
    /// The above example logs all incoming requests.
    ///
    /// - parameters:
    ///     - respond: Closure accepting a `Request` and `Responder` and returning a `Future<Response>`.
    /// - returns: `Router` with closure attached
    public func grouped(_ respond: @escaping (HTTPRequestContext, Responder) throws -> EventLoopFuture<HTTPResponse>) -> Router {
        return grouped([MiddlewareFunction(respond)])
    }

    /// Creates a sub `Router` wrapped in the supplied middleware function.
    ///
    ///     router.group({ req, next in
    ///         // this closure will be called with each request
    ///         print(req)
    ///         // use next responder in chain to respond
    ///         return try next.respond(to: req)
    ///     }) { group in
    ///         group.get("/") { ... }
    ///     }
    ///
    /// The above example logs all incoming requests.
    ///
    /// - parameters:
    ///     - respond: Closure accepting a `Request` and `Responder` and returning a `Future<Response>`.
    ///     - configure: Closure to configure the newly created sub `Router`.
    public func group(_ respond: @escaping (HTTPRequestContext, Responder) throws -> EventLoopFuture<HTTPResponse>, configure: (Router) -> ()) {
        group([MiddlewareFunction(respond)], configure: configure)
    }
}

// MARK: Private

/// Wrapper to create Middleware from function
private class MiddlewareFunction: Middleware {
    /// Internal request handler.
    private let respond: (HTTPRequestContext, Responder) throws -> EventLoopFuture<HTTPResponse>

    /// Creates a new `MiddlewareFunction`
    init(_ function: @escaping (HTTPRequestContext, Responder) throws -> EventLoopFuture<HTTPResponse>) {
        self.respond = function
    }

    /// See `Middleware`.
    func respond(to req: HTTPRequestContext, chainingTo next: Responder) -> EventLoopFuture<HTTPResponse> {
        do {
            return try self.respond(req, next)
        } catch {
            return req.eventLoop.makeFailedFuture(error: error)
        }
    }
}
