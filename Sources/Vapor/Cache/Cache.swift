import NIOCore
/// Codable key-value pair cache.
public protocol Cache: Sendable {
    /// Gets a decodable value from the cache. Returns `nil` if not found.
    func get<T>(_ key: String, as type: T.Type) async throws -> T? where T: Decodable

    /// Sets an encodable value into the cache. Existing values are replaced. If `nil`, removes value.
    func set<T>(_ key: String, to value: T?) async throws where T: Encodable

    /// Sets an encodable value into the cache with an expiry time. Existing values are replaced. If `nil`, removes value.
    func set<T>(_ key: String, to value: T?, expiresIn expirationTime: CacheExpirationTime?) async throws where T: Encodable
    
    func delete(_ key: String) async throws

    /// Gets a decodable value from the cache. Returns `nil` if not found.
    func get<T>(_ key: String) async throws -> T? where T: Decodable
}

extension Cache {
    public func delete(_ key: String) async throws
    {
        return try await self.set(key, to: String?.none)
    }
    
    /// Gets a decodable value from the cache. Returns `nil` if not found.
    public func get<T>(_ key: String) async throws -> T?
        where T: Decodable
    {
        return try await self.get(key, as: T.self)
    }
}
