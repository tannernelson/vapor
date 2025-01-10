import Foundation
import NIOCore
import NIOConcurrencyHelpers

actor MemoryCacheStorage: Sendable {
    struct CacheEntryBox<T> {
        var expiresAt: Date?
        var value: T
        
        init(_ value: T) {
            self.expiresAt = nil
            self.value = value
        }
    }
    
    private var storage: [String: Any]
    
    init() {
        self.storage = [:]
    }
    
    func get<T>(_ key: String) -> T?
        where T: Decodable
    {
        guard let box = self.storage[key] as? CacheEntryBox<T> else { return nil }
        if let expiresAt = box.expiresAt, expiresAt < Date() {
            self.storage.removeValue(forKey: key)
            return nil
        }
        
        return box.value
    }
    
    func set<T>(_ key: String, to value: T?, expiresIn expirationTime: CacheExpirationTime?)
        where T: Encodable
    {
        if let value = value {
            var box = CacheEntryBox(value)
            if let expirationTime = expirationTime {
                box.expiresAt = Date().addingTimeInterval(TimeInterval(expirationTime.seconds))
            }
            self.storage[key] = box
        } else {
            self.storage.removeValue(forKey: key)
        }
    }
}

public struct MemoryCache: Cache {
    let storage: MemoryCacheStorage
    
    public init() {
        self.storage = MemoryCacheStorage()
    }
    
    public func get<T>(_ key: String, as type: T.Type) async throws -> T?
        where T: Decodable & Sendable
    {
        await self.storage.get(key)
    }
    
    public func set<T>(_ key: String, to value: T?) async throws -> Void
        where T: Encodable & Sendable
    {
        try await self.set(key, to: value, expiresIn: nil)
    }
    
    public func set<T>(_ key: String, to value: T?, expiresIn expirationTime: CacheExpirationTime?) async throws -> Void
        where T: Encodable & Sendable
    {
        await self.storage.set(key, to: value, expiresIn: expirationTime)
    }
}
