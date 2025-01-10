//import NIOConcurrencyHelpers
//
//extension Application {
//    public var passwords: Passwords {
//        .init(application: self)
//    }
//
//    public struct Passwords: Sendable {
//        public struct Provider: Sendable {
//            let run: @Sendable (Application) -> ()
//
//            public init(_ run: @Sendable @escaping (Application) -> ()) {
//                self.run = run
//            }
//        }
//
//        struct Key: StorageKey {
//            typealias Value = Storage
//        }
//
//        let application: Application
//
//        public func use(_ provider: Provider) {
//            provider.run(self.application)
//        }
//
//        public func use(
//            _ makeVerifier: @Sendable @escaping (Application) -> (PasswordHasher)
//        ) {
//            self.storage.makeVerifier.withLockedValue { $0 = .init(factory: makeVerifier) }
//        }
//
//        final class Storage: Sendable {
//            struct PasswordsFactory {
//                let factory: (@Sendable (Application) -> PasswordHasher)?
//            }
//            let makeVerifier: NIOLockedValueBox<PasswordsFactory>
//            init() {
//                self.makeVerifier = .init(.init(factory: nil))
//            }
//        }
//
//        var storage: Storage {
//            if let existing = self.application.storage[Key.self] {
//                return existing
//            } else {
//                let new = Storage()
//                self.application.storage[Key.self] = new
//                return new
//            }
//        }
//    }
//}
