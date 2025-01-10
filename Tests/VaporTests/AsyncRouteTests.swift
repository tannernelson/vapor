import XCTVapor
import XCTest
import Vapor
import NIOHTTP1

final class AsyncRouteTests: XCTestCase {
    var app: Application!
    
    override func setUp() async throws {
        app = await Application(.testing)
    }
    
    override func tearDown() async throws {
        try await app.shutdown()
    }
    
    func testEnumResponse() async throws {
        enum IntOrString: ResponseEncodable {
            case int(Int)
            case string(String)

            func encodeResponse(for request: Request) async throws -> Response {
                switch self {
                case .int(let i):
                    return try await i.encodeResponse(for: request)
                case .string(let s):
                    return try await s.encodeResponse(for: request)
                }
            }
        }

        app.routes.get("foo") { req -> IntOrString in
            if try req.query.get(String.self, at: "number") == "true" {
                return .int(42)
            } else {
                return .string("string")
            }
        }

        try await app.testable().test(.GET, "/foo?number=true") { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "42")
        }.test(.GET, "/foo?number=false") { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "string")
        }
    }

    func testResponseEncodableStatus() async throws {
        struct User: Content {
            var name: String
        }

        app.post("users") { req async throws -> Response in
            return try await req.content
                .decode(User.self)
                .encodeResponse(status: .created, for: req)
        }

        try await app.testable().test(.POST, "/users", beforeRequest: { req async throws in
            try req.content.encode(["name": "vapor"], as: .json)
        }) { res in
            XCTAssertEqual(res.status, .created)
            XCTAssertEqual(res.headers.contentType, .json)
            XCTAssertEqual(res.body.string, """
            {"name":"vapor"}
            """)
        }
    }

    func testWebsocketUpgrade() async throws {
        let testMarkerHeaderKey = "TestMarker"
        let testMarkerHeaderValue = "addedInShouldUpgrade"

        app.routes.webSocket("customshouldupgrade", shouldUpgrade: { req in
            [testMarkerHeaderKey: testMarkerHeaderValue]
        }, onUpgrade: { _, _ in })

        try await app.testable(method: .running(port: 0)).test(.GET, "customshouldupgrade", beforeRequest: { req async in
            req.headers.replaceOrAdd(name: HTTPHeaders.Name.secWebSocketVersion, value: "13")
            req.headers.replaceOrAdd(name: HTTPHeaders.Name.secWebSocketKey, value: "zyFJtLIpI2ASsmMHJ4Cf0A==")
            req.headers.replaceOrAdd(name: .connection, value: "Upgrade")
            req.headers.replaceOrAdd(name: .upgrade, value: "websocket")
        }) { res in
            XCTAssertEqual(res.headers.first(name: testMarkerHeaderKey), testMarkerHeaderValue)
        }
    }
}
