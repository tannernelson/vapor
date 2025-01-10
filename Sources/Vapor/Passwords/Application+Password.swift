//import Foundation
//
//extension Application {
//    public var password: Password {
//        .init(application: self)
//    }
//
//    public struct Password: PasswordHasher {
//        let application: Application
//
//        public var async: AsyncPasswordHasher {
//            self.sync.async(
//                on: self.application.threadPool,
//                hopTo: self.application.eventLoopGroup.next()
//            )
//        }
//
//        public var sync: PasswordHasher {
//            guard let makeVerifier = self.application.passwords.storage.makeVerifier.withLockedValue({ $0.factory }) else {
//                fatalError("No password verifier configured. Configure with app.passwords.use(...)")
//            }
//            return makeVerifier(self.application)
//        }
//
//        public func verify<Password, Digest>(
//            _ password: Password,
//            created digest: Digest
//        ) throws -> Bool
//            where Password: DataProtocol, Digest: DataProtocol
//        {
//            try self.sync.verify(password, created: digest)
//        }
//
//        public func hash<Password>(_ password: Password) throws -> [UInt8]
//            where Password: DataProtocol
//        {
//            try self.sync.hash(password)
//        }
//    }
//}
