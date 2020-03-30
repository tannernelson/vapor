/// Capable of verifying that a supplied password matches a hash.
public protocol PasswordVerifier {
    /// Verifies that the supplied password matches a given hash.
    func verify<Password, Digest>(_ password: Password, created digest: Digest) throws -> Bool
        where Password: DataProtocol, Digest: DataProtocol
    func verify(_ password: String, created digest: String) throws -> Bool
    func `for`(_ request: Request) -> PasswordVerifier
}

/// Simply compares the password to the hash.
/// Don't use this in production.
public struct PlaintextVerifier: PasswordVerifier {
    /// Create a new plaintext verifier.
    public init() {}

    /// See PasswordVerifier.verify
    public func verify<Password, Digest>(_ password: Password, created digest: Digest) throws -> Bool
        where Password: DataProtocol, Digest: DataProtocol
    {
        return password.copyBytes() == digest.copyBytes()
    }
    
    public func verify(_ password: String, created digest: String) throws -> Bool {
        return password == digest
    }
}

extension PlaintextVerifier {
    public func `for`(_ request: Request) -> PasswordVerifier {
        return PlaintextVerifier()
    }
}
