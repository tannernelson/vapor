import Foundation

public struct BcryptHasher: PasswordHasher {
    let cost: Int
    
    public init(cost: Int) {
        self.cost = cost
    }
    
#warning("Run this on a thread pool or something")
    
    public func hash<Password>(
        _ password: Password
    ) throws -> [UInt8]
        where Password: DataProtocol
    {
        let string = String(decoding: password, as: UTF8.self)
        let digest = try Bcrypt.hash(string, cost: self.cost)
        return .init(digest.utf8)
    }

    public func verify<Password, Digest>(
        _ password: Password,
        created digest: Digest
    ) throws -> Bool
        where Password: DataProtocol, Digest: DataProtocol
    {
        try Bcrypt.verify(
            String(decoding: password.copyBytes(), as: UTF8.self),
            created: String(decoding: digest.copyBytes(), as: UTF8.self)
        )
    }
}
