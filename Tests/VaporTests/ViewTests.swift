import XCTVapor
import XCTest
import Vapor
import NIOCore

final class ViewTests: XCTestCase {
    func testViewResponse() async throws {
        let app = await Application(.testing)

        app.get("view") { req -> View in
            var data = ByteBufferAllocator().buffer(capacity: 0)
            data.writeString("<h1>hello</h1>")
            return View(data: data)
        }

        try await app.testable().test(.GET, "/view") { res in
            XCTAssertEqual(res.status.code, 200)
            XCTAssertEqual(res.headers.contentType, .html)
            XCTAssertEqual(res.body.string, "<h1>hello</h1>")
        }
        
        try await app.shutdown()
    }
}
