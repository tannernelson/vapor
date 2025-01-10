import Foundation

public protocol PasswordHasher: Sendable {
    func hash<Password>(_ password: Password) async throws -> [UInt8]
        where Password: DataProtocol

    func verify<Password, Digest>(
        _ password: Password,
        created digest: Digest
    ) async throws -> Bool
        where Password: DataProtocol, Digest: DataProtocol
}

extension PasswordHasher {
    public func hash(_ password: String) async throws -> String {
        try await String(decoding: self.hash([UInt8](password.utf8)), as: UTF8.self)
    }

    public func verify(_ password: String, created digest: String) async throws -> Bool {
        try await self.verify(
            [UInt8](password.utf8),
            created: [UInt8](digest.utf8)
        )
    }
}
