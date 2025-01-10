import NIOCore
import NIOPosix
import Foundation

extension PasswordHasher {
    public func async(
        on threadPool: NIOThreadPool,
        hopTo eventLoop: EventLoop
    ) -> AsyncPasswordHasher {
        .init(
            hasher: self,
            threadPool: threadPool,
            eventLoop: eventLoop
        )
    }
}

public struct AsyncPasswordHasher: Sendable {
    let hasher: PasswordHasher
    let threadPool: NIOThreadPool
    let eventLoop: EventLoop
    
    public init(hasher: PasswordHasher, threadPool: NIOThreadPool, eventLoop: EventLoop) {
        self.hasher = hasher
        self.threadPool = threadPool
        self.eventLoop = eventLoop
    }
    
    public func hash<Password>(_ password: Password) async throws -> [UInt8]
        where Password: DataProtocol & Sendable
    {
        try await self.hasher.hash(password)
    }
    
    public func verify<Password, Digest>(
        _ password: Password,
        created digest: Digest
    ) async throws -> Bool
        where Password: DataProtocol & Sendable, Digest: DataProtocol & Sendable
    {
        try await self.hasher.verify(password, created: digest)
    }
    
    public func hash(_ password: String) async throws -> String {
        let bytes = try await self.hash([UInt8](password.utf8))
        return String(decoding: bytes, as: UTF8.self)
    }

    public func verify(_ password: String, created digest: String) async throws -> Bool {
        try await self.verify(
            [UInt8](password.utf8),
            created: [UInt8](digest.utf8)
        )
    }
}
