@testable import Vapor
import XCTVapor
import XCTest

final class EnvironmentSecretTests: XCTestCase {
    var app: Application!
    
    override func setUp() async throws {
        app = await Application(.testing)
    }
    
    override func tearDown() async throws {
        try await app.shutdown()
    }
    
    func testNonExistingSecretFile() async throws {
        let folder = #filePath.split(separator: "/").dropLast().joined(separator: "/")
        let path = "/" + folder + "/Utilities/non-existing-secret"
        let secretContent = try await Environment.secret(path: path, logger: app.logger)
        XCTAssertNil(secretContent)
    }

    func testExistingSecretFile() async throws {
        let folder = #filePath.split(separator: "/").dropLast().joined(separator: "/")
        let path = "/" + folder + "/Utilities/my-secret-env-content"
        let secretContent = try await Environment.secret(path: path, logger: app.logger)
        XCTAssertEqual(secretContent, "password")
    }

    func testExistingSecretFileFromEnvironmentKey() async throws {
        let folder = #filePath.split(separator: "/").dropLast().joined(separator: "/")
        let path = "/" + folder + "/Utilities/my-secret-env-content"

        let key = "MY_ENVIRONMENT_SECRET"
        setenv(key, path, 1)
        defer {
            unsetenv(key)
        }

        let secretContent = try await Environment.secret(key: key, logger: app.logger)
        XCTAssertEqual(secretContent, "password")
    }

    func testLoadingSecretFromEnvKeyWhichDoesNotExist() async throws {
        let key = "MY_NON_EXISTING_ENVIRONMENT_SECRET"
        let secretContent = try await Environment.secret(key: key, logger: app.logger)
        XCTAssertNil(secretContent)
    }
}
