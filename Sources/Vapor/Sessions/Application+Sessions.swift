import NIOConcurrencyHelpers

extension Application {
    public var sessions: Sessions {
        .init(application: self)
    }

    public struct Sessions: Sendable {
        public struct Provider: Sendable {
            public static var memory: Self {
                .init {
                    $0.sessions.use { $0.sessions.memory }
                }
            }

            let run: @Sendable (Application) -> ()

            public init(_ run: @Sendable @escaping (Application) -> ()) {
                self.run = run
            }
        }

        final class Storage: Sendable {
            struct SessionDriverFactory {
                let factory: (@Sendable (Application) -> SessionDriver)?
            }
            let memory: MemorySessions
            let makeDriver: NIOLockedValueBox<SessionDriverFactory>
            let configuration: NIOLockedValueBox<SessionsConfiguration>
            init() {
                self.memory = .init()
                self.configuration = .init(.default())
                self.makeDriver = .init(.init(factory: nil))
            }
        }

        struct Key: StorageKey {
            typealias Value = Storage
        }

        let application: Application

        public var configuration: SessionsConfiguration {
            get {
                self.storage.configuration.withLockedValue { $0 }
            }
            nonmutating set {
                self.storage.configuration.withLockedValue { $0 = newValue }
            }
        }

        public var middleware: SessionsMiddleware {
            .init(
                session: self.driver,
                configuration: self.configuration
            )
        }

        public var driver: SessionDriver {
            guard let makeDriver = self.storage.makeDriver.withLockedValue({ $0.factory }) else {
                fatalError("No driver configured. Configure with app.sessions.use(...)")
            }
            return makeDriver(self.application)
        }

        public var memory: MemorySessions {
            .init()
        }

        public func use(_ provider: Provider) {
            provider.run(self.application)
        }

        public func use(_ makeDriver: @Sendable @escaping (Application) -> (SessionDriver)) {
            self.storage.makeDriver.withLockedValue { $0 = .init(factory: makeDriver) }
        }

        var storage: Storage {
            guard let storage = self.application.storage[Key.self] else {
                fatalError("Sessions not configured. Configure with app.sessions.initialize()")
            }
            return storage
        }

        func initialize() {
            self.application.storage.setFirstTime(Key.self, to: .init())
        }
    }
}
