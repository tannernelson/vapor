import NIOConcurrencyHelpers

/// Configures an application's active `Middleware`.
/// Middleware will be used in the order they are added.
#warning("This was a struct, fix when we work out the API")
public final class Middlewares: Sendable {
    /// The configured middleware.
    private let storage: NIOLockedValueBox<[Middleware]>

  
    public enum Position {
      case beginning
      case end
    }
  
    /// Create a new, empty `Middleware`.
    public init() {
        self.storage = .init([])
    }

    /// Adds a pre-initialized `Middleware` instance.
    ///
    ///     app.middleware.use(fooMiddleware)
    ///
    /// - warning: Ensure the `Middleware` is thread-safe when using this method.
    ///            Otherwise, use the type-based method and register the `Middleware`
    ///            using factory method to `Services`.
    public func use(_ middleware: Middleware, at position: Position = .end) {
      switch position {
      case .end:
          self.storage.withLockedValue { $0.append(middleware) }
      case .beginning:
          self.storage.withLockedValue { $0.insert(middleware, at: 0) }
      }
    }

    /// Resolves the configured middleware for a given container
    public func resolve() -> [Middleware] {
        return self.storage.withLockedValue { $0 }
    }
}
