import XCTVapor
import Vapor
import XCTest

final class LoggingTests: XCTestCase {
    func testChangeRequestLogLevel() async throws {
        let app = await Application(.testing)

        app.get("trace") { req -> String in
            req.logger.logLevel = .trace
            req.logger.trace("foo")
            return "done"
        }

        try await app.testable().test(.GET, "trace") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "done")
        }
        
        try await app.shutdown()
    }
}
