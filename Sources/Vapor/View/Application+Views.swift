import NIOConcurrencyHelpers

extension Application {
    public var views: Views {
        .init(application: self)
    }

    public var view: ViewRenderer {
        guard let makeRenderer = self.views.storage.makeRenderer.withLockedValue({ $0.factory }) else {
            fatalError("No renderer configured. Configure with app.views.use(...)")
        }
        return makeRenderer(self)
    }

    public struct Views: Sendable {
        public struct Provider: Sendable {
            public static var plaintext: Self {
                .init {
                    $0.views.use { $0.views.plaintext }
                }
            }

            let run: @Sendable (Application) -> ()

            public init(_ run: @Sendable @escaping (Application) -> ()) {
                self.run = run
            }
        }
        
        final class Storage: Sendable {
            struct ViewRendererFactory {
                let factory: (@Sendable (Application) -> ViewRenderer)?
            }
            let makeRenderer: NIOLockedValueBox<ViewRendererFactory>
            init() {
                self.makeRenderer = .init(.init(factory: nil))
            }
        }

        struct Key: StorageKey {
            typealias Value = Storage
        }

        let application: Application

        public var plaintext: PlaintextRenderer {
            return .init(
                viewsDirectory: self.application.directory.viewsDirectory,
                logger: self.application.logger
            )
        }

        public func use(_ provider: Provider) {
            provider.run(self.application)
        }

        public func use(_ makeRenderer: @Sendable @escaping (Application) -> (ViewRenderer)) {
            self.storage.makeRenderer.withLockedValue { $0 = .init(factory: makeRenderer) }
        }

        func initialize() async {
            await self.application.storage.set(Key.self, to: .init())
            self.use(.plaintext)
        }

        var storage: Storage {
            guard let storage = self.application.storage[Key.self] else {
                fatalError("Views not configured. Configure with app.views.initialize()")
            }
            return storage
        }
    }
}
