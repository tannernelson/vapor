import XCTest
import Vapor
import ConsoleKit

final class AsyncCommandsTests: XCTestCase {
    var app: Application!
    
    override func setUp() async throws {
        app = await Application(.testing)
    }
    
    override func tearDown() async throws {
        try await app.shutdown()
    }
    
    func testAsyncCommands() async throws {
        app.commands.use(FooCommand(), as: "foo")

        app.environment.arguments = ["vapor", "foo", "bar"]

        try await app.start()

        XCTAssertTrue(app.storage[TestStorageKey.self] ?? false)
    }
}

extension AsyncCommandsTests {
    struct TestStorageKey: StorageKey {
        typealias Value = Bool
    }

    struct FooCommand: AsyncCommand {
        struct Signature: CommandSignature {
            @Argument(name: "name")
            var name: String
        }

        let help = "Does the foo."

        func run(using context: CommandContext, signature: Signature) async throws {
            await context.application.storage.set(TestStorageKey.self, to: true)
        }
    }
}
