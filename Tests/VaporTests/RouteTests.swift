import XCTVapor
import XCTest
import Vapor
import NIOCore
import NIOHTTP1

final class RouteTests: XCTestCase {
    
    var app: Application!
    
    override func setUp() async throws {
        self.app = await Application(.testing)
    }
    
    override func tearDown() async throws {
        try await self.app.shutdown()
    }
    
    func testParameter() async throws {
        app.routes.get("hello", ":a") { req in
            return req.parameters.get("a") ?? ""
        }
        app.routes.get("hello", ":a", ":b") { req in
            return [req.parameters.get("a") ?? "", req.parameters.get("b") ?? ""]
        }
        try await app.testable().test(.GET, "/hello/vapor") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertContains(res.body.string, "vapor")
        }.test(.POST, "/hello/vapor") { res in
            XCTAssertEqual(res.status, .notFound)
        }.test(.GET, "/hello/vapor/development") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, #"["vapor","development"]"#)
        }
    }

    func testRequiredParameter() async throws {
        app.routes.get("string", ":value") { req in
            return try req.parameters.require("value")
        }

        app.routes.get("int", ":value") { req -> String in
            let value = try req.parameters.require("value", as: Int.self)
            return String(value)
        }

        app.routes.get("missing") { req in
            return try req.parameters.require("value")
        }

        try await app.testable().test(.GET, "/string/test") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertContains(res.body.string, "test")
        }.test(.GET, "/int/123") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "123")
        }.test(.GET, "/int/not-int") { res in
            XCTAssertEqual(res.status, .unprocessableEntity)
        }.test(.GET, "/missing") { res in
            XCTAssertEqual(res.status, .internalServerError)
        }
    }

    func testJSON() async throws {
        app.routes.get("json") { req -> [String: String] in
            return ["foo": "bar"]
        }

        try await app.testable().test(.GET, "/json") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, #"{"foo":"bar"}"#)
        }
    }

    func testRootGet() async throws {
        app.routes.get("") { req -> String in
                return "root"
        }
        app.routes.get("foo") { req -> String in
            return "foo"
        }

        try await app.testable().test(.GET, "/") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "root")
        }.test(.GET, "/foo") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "foo")
        }
    }
    
    func testInsensitiveRoutes() async throws {
        app.routes.caseInsensitive = true
        
        app.routes.get("foo") { req -> String in
            return "foo"
        }

        try await app.testable().test(.GET, "/foo") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "foo")
        }.test(.GET, "/FOO") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "foo")
        }
    }

    func testAnyResponse() async throws {
        app.get("foo") { req -> AnyResponse in
            if try req.query.get(String.self, at: "number") == "true" {
                return AnyResponse(42)
            } else {
                return AnyResponse("string")
            }
        }

        try await app.testable().test(.GET, "/foo", beforeRequest: { req in
            try req.query.encode(["number": "true"])
        }) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "42")
        }.test(.GET, "/foo", beforeRequest: { req in
            try req.query.encode(["number": "false"])
        }) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "string")
        }
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

        try await app.testable().test(.GET, "/foo?number=true") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "42")
        }.test(.GET, "/foo?number=false") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "string")
        }
    }

    func testValidationError() async throws {
        struct User: Content, Validatable {
            static func validations(_ v: inout Validations) {
                v.add("email", is: .email)
            }

            var name: String
            var email: String
        }

        app.post("users") { req -> User in
            try User.validate(content: req)
            return try req.content.decode(User.self)
        }

        try await app.testable().test(.POST, "/users", beforeRequest: { req in
            try req.content.encode([
                "name": "vapor",
                "email": "foo"
            ], as: .json)
        }) { res in
            XCTAssertEqual(res.status, .badRequest)
            XCTAssertContains(res.body.string, "email is not a valid email address")
        }.test(.POST, "/users") { res in
            XCTAssertEqual(res.status, .unprocessableEntity)
            XCTAssertContains(res.body.string.replacingOccurrences(of: "\\", with: ""), "Missing \"Content-Type\" header")
        }.test(.POST, "/users", headers: ["Content-Type":"application/json"]) { res in
            XCTAssertEqual(res.status, .unprocessableEntity)
            XCTAssertContains(res.body.string, "Empty Body")
        }
    }

    func testResponseEncodableStatus() async throws {
        struct User: Content {
            var name: String
        }

        app.post("users") { req in
            return try await req.content
                .decode(User.self)
                .encodeResponse(status: .created, for: req)
        }

        try await app.testable().test(.POST, "/users", beforeRequest: { req in
            try req.content.encode(["name": "vapor"], as: .json)
        }) { res in
            XCTAssertEqual(res.status, .created)
            XCTAssertEqual(res.headers.contentType, .json)
            XCTAssertEqual(res.body.string, """
            {"name":"vapor"}
            """)
        }
    }

    func testHeadRequestForwardedToGet() async throws {
        app.get("hello") { req -> String in
            XCTAssertEqual(req.method, .HEAD)
            return "hi"
        }

        try await app.testable(method: .running(port: 0)).test(.HEAD, "/hello") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.headers.first(name: .contentLength), "2")
            XCTAssertEqual(res.body.readableBytes, 0)
        }
    }

    func testExplicitHeadRouteOverridesForwardingToGet() async throws {
        app.get("hello") { req -> Response in
            return Response(status: .badRequest)
        }

        app.on(.HEAD, "hello") { req -> Response in
            return Response(status: .found)
        }

        try await app.testable(method: .running(port: 0)).test(.HEAD, "/hello") { res in
            XCTAssertEqual(res.status, .found)
            XCTAssertEqual(res.headers.first(name: .contentLength), "0")
            XCTAssertEqual(res.body.readableBytes, 0)
        }
    }
    
    func testInvalidCookie() async throws {
        app.grouped(SessionsMiddleware(session: app.sessions.driver))
            .get("get") { req -> String in
                return await req.session.data["name"] ?? "n/a"
            }

        var headers = HTTPHeaders()
        var cookies = HTTPCookies()
        cookies["vapor-session"] = "asdf"
        headers.cookie = cookies
        try await app.testable().test(.GET, "/get", headers: headers) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertNotNil(res.headers[.setCookie])
            XCTAssertEqual(res.body.string, "n/a")
        }
    }

    // https://github.com/vapor/vapor/issues/1787
    func testGH1787() async throws {
        app.get("no-content") { req -> String in
            throw Abort(.noContent)
        }

        try await app.testable(method: .running(port: 0)).test(.GET, "/no-content") { res in
            XCTAssertEqual(res.status.code, 204)
            XCTAssertEqual(res.body.readableBytes, 0)
        }
    }

    func testSimilarRoutingPath() async throws {
        app.get("api","addresses") { req in
            "a"
        }
        app.get("api", "addresses","search", ":id") { req in
            "b"
        }

        try await app.testable(method: .running(port: 0)).test(.GET, "/api/addresses/") { res in
            XCTAssertEqual(res.body.string, "a")
        }.test(.GET, "/api/addresses/search/test") { res in
            XCTAssertEqual(res.body.string, "b")
        }.test(.GET, "/api/addresses/search/") { res in
            XCTAssertEqual(res.status, .notFound)
        }.test(.GET, "/api/addresses/search") { res in
            XCTAssertEqual(res.status, .notFound)
        }
    }

    func testThrowingGroup() async throws {
        XCTAssertThrowsError(try app.routes.group("foo") { router in
            throw Abort(.internalServerError, reason: "Test")
        })
    }

    func testCollection() async throws {
        struct Foo: RouteCollection {
            func boot(routes: RoutesBuilder) throws {
                routes.get("foo") { _ in "bar" }
            }
        }
        
        try app.register(collection: Foo())

        try await app.test(.GET, "foo") { res in
            XCTAssertEqual(res.body.string, "bar")
        }
    }

    func testConfigurableMaxBodySize() async throws {
        XCTAssertEqual(app.routes.defaultMaxBodySize, 16384)
        app.routes.defaultMaxBodySize = 1
        XCTAssertEqual(app.routes.defaultMaxBodySize, 1)

        app.on(.POST, "default") { request in
            HTTPStatus.ok
        }
        app.on(.POST, "1kb", body: .collect(maxSize: "1kb")) { request in
            HTTPStatus.ok
        }
        app.on(.POST, "1mb", body: .collect(maxSize: "1mb")) { request in
            HTTPStatus.ok
        }
        app.on(.POST, "1gb", body: .collect(maxSize: "1gb")) { request in
            HTTPStatus.ok
        }

        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeBytes(Array(repeating: 0, count: 500_000))
        try await app.testable(method: .running(port: 0)).test(.POST, "/default", body: buffer) { res in
            XCTAssertEqual(res.status, .payloadTooLarge)
        }.test(.POST, "/1kb", body: buffer) { res in
            XCTAssertEqual(res.status, .payloadTooLarge)
        }.test(.POST, "/1mb", body: buffer) { res in
            XCTAssertEqual(res.status, .ok)
        }.test(.POST, "/1gb", body: buffer) { res in
            XCTAssertEqual(res.status, .ok)
        }
    }
    
    func testWebsocketUpgrade() async throws {
        let testMarkerHeaderKey = "TestMarker"
        let testMarkerHeaderValue = "addedInShouldUpgrade"
        
        app.routes.webSocket("customshouldupgrade", shouldUpgrade: { req in
            return [testMarkerHeaderKey: testMarkerHeaderValue]
        }, onUpgrade: { _, _ in })
        
        try await app.testable(method: .running(port: 0)).test(.GET, "customshouldupgrade", beforeRequest: { req in
            req.headers.replaceOrAdd(name: HTTPHeaders.Name.secWebSocketVersion, value: "13")
            req.headers.replaceOrAdd(name: HTTPHeaders.Name.secWebSocketKey, value: "zyFJtLIpI2ASsmMHJ4Cf0A==")
            req.headers.replaceOrAdd(name: .connection, value: "Upgrade")
            req.headers.replaceOrAdd(name: .upgrade, value: "websocket")
        }) { res in
            XCTAssertEqual(res.headers.first(name: testMarkerHeaderKey), testMarkerHeaderValue)
        }
    }
    
    // https://github.com/vapor/vapor/issues/2716
    func testGH2716() async throws {
        app.get("client") { req in
            let response = try await req.client.get("http://localhost/status/2 1")
            return response.description
        }
        
        try await app.testable(method: .running(port: 0)).test(.GET, "/client") { res in
            XCTAssertEqual(res.status.code, 500)
        }
    }
    
    // https://github.com/vapor/vapor/issues/3137
    // https://github.com/vapor/vapor/issues/3142
    func testDoubleSlashRouteAccess() async throws {
        app.get(":foo", ":bar", "buz") { req -> String in
            "\(try req.parameters.require("foo"))\(try req.parameters.require("bar"))"
        }
        
        try await app.testable(method: .running(port: 0)).test(.GET, "/foop/barp/buz") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "foopbarp")
        }.test(.GET, "//foop/barp/buz") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "foopbarp")
        }.test(.GET, "//foop//barp/buz") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "foopbarp")
        }.test(.GET, "//foop//barp//buz") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "foopbarp")
        }.test(.GET, "/foop//barp/buz") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "foopbarp")
        }.test(.GET, "/foop//barp//buz") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "foopbarp")
        }.test(.GET, "/foop/barp//buz") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "foopbarp")
        }.test(.GET, "//foop/barp//buz") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "foopbarp")
        }
    }
}
