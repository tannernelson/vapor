import NIOConcurrencyHelpers

extension Request {
    /// Helper for accessing authenticated objects.
    /// See `Authenticator` for more information.
    public var auth: Authentication {
        return .init(request: self)
    }

    /// Request helper for storing and fetching authenticated objects.
    public struct Authentication {
        let request: Request
        init(request: Request) {
            self.request = request
        }
    }
}

extension Request.Authentication {
    /// Authenticates the supplied instance for this request.
    public func login<A>(_ instance: A) async
        where A: Authenticatable
    {
        await self.cache[A.self] = UnsafeAuthenticationBox(instance)
    }

    /// Unauthenticates an authenticatable type.
    public func logout<A>(_ type: A.Type = A.self) async
        where A: Authenticatable
    {
        await self.cache[A.self] = nil
    }

    /// Returns an instance of the supplied type. Throws if no
    /// instance of that type has been authenticated or if there
    /// was a problem.
    @discardableResult public func require<A>(_ type: A.Type = A.self) async throws -> A
        where A: Authenticatable
    {
        guard let a = await self.get(A.self) else {
            throw Abort(.unauthorized)
        }
        return a
    }

    /// Returns the authenticated instance of the supplied type.
    /// - note: `nil` if no type has been authed.
    public func get<A>(_ type: A.Type = A.self) async -> A?
        where A: Authenticatable
    {
        return await self.cache[A.self]?.authenticated
    }

    /// Returns `true` if the type has been authenticated.
    public func has<A>(_ type: A.Type = A.self) async -> Bool
        where A: Authenticatable
    {
        return await self.get(A.self) != nil
    }

    private final class Cache: Sendable {
        private let storage: NIOLockedValueBox<[ObjectIdentifier: Sendable]>

        init() {
            self.storage = .init([:])
        }

        internal subscript<A>(_ type: A.Type) -> UnsafeAuthenticationBox<A>?
            where A: Authenticatable
            {
            get { 
                storage.withLockedValue { $0[ObjectIdentifier(A.self)] as? UnsafeAuthenticationBox<A> }
            }
            set { 
                storage.withLockedValue { $0[ObjectIdentifier(A.self)] = newValue }
            }
        }
    }

    private struct CacheKey: StorageKey {
        typealias Value = Cache
    }

    private var cache: Cache {
        get async {
            if let existing = self.request.storage[CacheKey.self] {
                return existing
            } else {
                let new = Cache()
                await self.request.storage.set(CacheKey.self, to: new)
                return new
            }
        }
    }
}

// This is to get around the fact that for legacy reasons we can't enforce Sendability on Authenticatable
// types (e.g. Fluent 4 models can never be Sendable because they're reference types with mutable values
// required by protocols and property wrappers). This allows us to store the Authenticatable type in a
// safe-most-of-the-time way. This does introduce an edge case where type could be stored and mutated in
// multiple places. But given how Vapor and its users use Authentication this should almost never
// occur and it was decided the trade-off was acceptable
// As the name implies, the usage of this is unsafe because it disables the sendable checking of the
// compiler and does not add any synchronization.
@usableFromInline
internal struct UnsafeAuthenticationBox<A>: @unchecked Sendable {
    @usableFromInline
    let authenticated: A
    
    @inlinable
    init(_ authenticated: A) {
        self.authenticated = authenticated
    }
}
