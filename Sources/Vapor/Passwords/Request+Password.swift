import Foundation

extension Request {
    public var password: Password {
        .init(request: self)
    }
    
    public struct Password: PasswordHasher {
        let request: Request
        
        public var async: AsyncPasswordHasher {
            self.request.application.passwordHasher
        }
        
        public func verify<Password, Digest>(
            _ password: Password,
            created digest: Digest
        ) async throws -> Bool
            where Password: DataProtocol & Sendable, Digest: DataProtocol & Sendable
        {
            try await self.async.verify(password, created: digest)
        }
        
        public func hash<Password>(_ password: Password) async throws -> [UInt8]
            where Password: DataProtocol & Sendable
        {
            try await self.async.hash(password)
        }
    }
}
