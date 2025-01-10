import XCTVapor
import XCTest
import Vapor
import NIOCore
import NIOPosix

final class AuthenticationTests: XCTestCase {
    
    var app: Application!
    
    override func setUp() async throws {
        app = await Application(.testing)
    }
    
    override func tearDown() async throws {
        try await app.shutdown()
    }
    
    func testBearerAuthenticator() async throws {
        struct Test: Authenticatable {
            static func authenticator() -> Authenticator {
                TestAuthenticator()
            }

            var name: String
        }

        struct TestAuthenticator: BearerAuthenticator {
            func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
                if bearer.token == "test" {
                    let test = Test(name: "Vapor")
                    await request.auth.login(test)
                }
            }
        }
        
        app.routes.grouped([
            Test.authenticator(), Test.guardMiddleware()
        ]).get("test") { req -> String in
            return try await req.auth.require(Test.self).name
        }

        try await app.testable().test(.GET, "/test") { res in
            XCTAssertEqual(res.status, .unauthorized)
        }
        .test(.GET, "/test", headers: ["Authorization": "Bearer test"]) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "Vapor")
        }
        .test(.GET, "/test", headers: ["Authorization": "bearer test"]) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "Vapor")
        }
    }

    func testBasicAuthenticator() async throws {
        struct Test: Authenticatable {
            static func authenticator() -> Authenticator {
                TestAuthenticator()
            }

            var name: String
        }

        struct TestAuthenticator: BasicAuthenticator {
            typealias User = Test

            func authenticate(basic: BasicAuthorization, for request: Request) async throws {
                if basic.username == "test" && basic.password == "secret" {
                    let test = Test(name: "Vapor")
                    await request.auth.login(test)
                }
            }
        }

        app.routes.grouped([
            Test.authenticator(), Test.guardMiddleware()
        ]).get("test") { req -> String in
            return try await req.auth.require(Test.self).name
        }
        
        let basic = "test:secret".data(using: .utf8)!.base64EncodedString()
        try await app.testable().test(.GET, "/test") { res in
            XCTAssertEqual(res.status, .unauthorized)
        }.test(.GET, "/test", headers: ["Authorization": "Basic \(basic)"]) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "Vapor")
        }.test(.GET, "/test", headers: ["Authorization": "basic \(basic)"]) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "Vapor")
        }
    }
    
    func testBasicAuthenticatorWithColonInPassword() async throws {
        struct Test: Authenticatable {
            static func authenticator() -> Authenticator {
                TestAuthenticator()
            }

            var name: String
        }

        struct TestAuthenticator: BasicAuthenticator {
            typealias User = Test

            func authenticate(basic: BasicAuthorization, for request: Request) async throws {
                if basic.username == "test" && basic.password == "secret:with:colon" {
                    let test = Test(name: "Vapor")
                    await request.auth.login(test)
                }
            }
        }
        
        app.routes.grouped([
            Test.authenticator(), Test.guardMiddleware()
        ]).get("test") { req -> String in
            return try await req.auth.require(Test.self).name
        }
        
        let basic = "test:secret:with:colon".data(using: .utf8)!.base64EncodedString()
        try await app.testable().test(.GET, "/test") { res in
            XCTAssertEqual(res.status, .unauthorized)
        }.test(.GET, "/test", headers: ["Authorization": "Basic \(basic)"]) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "Vapor")
        }
    }
    
    func testBasicAuthenticatorWithEmptyPassword() async throws {
        struct Test: Authenticatable {
            static func authenticator() -> Authenticator {
                TestAuthenticator()
            }

            var name: String
        }

        struct TestAuthenticator: BasicAuthenticator {
            typealias User = Test

            func authenticate(basic: BasicAuthorization, for request: Request) async throws {
                if basic.username == "test" && basic.password == "" {
                    let test = Test(name: "Vapor")
                    await request.auth.login(test)
                }
            }
        }

        app.routes.grouped([
            Test.authenticator(), Test.guardMiddleware()
        ]).get("test") { req -> String in
            return try await req.auth.require(Test.self).name
        }
        
        let basic = Data("test:".utf8).base64EncodedString()
        try await app.testable().test(.GET, "/test") { res in
            XCTAssertEqual(res.status, .unauthorized)
        }.test(.GET, "/test", headers: ["Authorization": "Basic \(basic)"]) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "Vapor")
        }
    }
    
    func testBasicAuthenticatorWithRedirect() async throws {
        struct Test: Authenticatable {
            static func authenticator() -> Authenticator {
                TestAuthenticator()
            }

            var name: String
        }

        struct TestAuthenticator: BasicAuthenticator {
            typealias User = Test

            func authenticate(basic: BasicAuthorization, for request: Request) async throws {
                if basic.username == "test" && basic.password == "secret" {
                    let test = Test(name: "Vapor")
                    await request.auth.login(test)
                }
            }
        }
        
        let redirectMiddleware = Test.redirectMiddleware { req -> String in
            return "/redirect?orig=\(req.url.path)"
        }

        app.routes.grouped([
            Test.authenticator(), redirectMiddleware
        ]).get("test") { req -> String in
            return try await req.auth.require(Test.self).name
        }
        
        let basic = "test:secret".data(using: .utf8)!.base64EncodedString()
        try await app.testable().test(.GET, "/test") { res in
            XCTAssertEqual(res.status, .seeOther)
            XCTAssertEqual(res.headers["Location"].first, "/redirect?orig=/test")
        }.test(.GET, "/test", headers: ["Authorization": "Basic \(basic)"]) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "Vapor")
        }
    }

    func testSessionAuthentication() async throws {
        struct Test: Authenticatable, SessionAuthenticatable {
            static func bearerAuthenticator() -> Authenticator {
                TestBearerAuthenticator()
            }

            static func sessionAuthenticator() -> Authenticator {
                TestSessionAuthenticator()
            }

            var sessionID: String {
                self.name
            }
            var name: String
        }

        struct TestBearerAuthenticator: BearerAuthenticator {
            func authenticate(bearer: BearerAuthorization, for request: Request) async throws {
                if bearer.token == "test" {
                    let test = Test(name: "Vapor")
                    await request.auth.login(test)
                }
            }
        }

        struct TestSessionAuthenticator: SessionAuthenticator {
            typealias User = Test

            func authenticate(sessionID: String, for request: Request) async throws {
                let test = Test(name: sessionID)
                await request.auth.login(test)
            }
        }
        
        app.routes.grouped([
            app.sessions.middleware,
            Test.sessionAuthenticator(),
            Test.bearerAuthenticator(),
            Test.guardMiddleware(),
        ]).get("test") { req -> String in
            try await req.auth.require(Test.self).name
        }

        var sessionCookie: HTTPCookies.Value?
        try await app.testable().test(.GET, "/test") { res in
            XCTAssertEqual(res.status, .unauthorized)
            XCTAssertNil(res.headers.first(name: .setCookie))
        }.test(.GET, "/test", headers: ["Authorization": "Bearer test"]) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "Vapor")
            if let cookie = res.headers.setCookie?["vapor-session"] {
                sessionCookie = cookie
            } else {
                XCTFail("No set cookie header")
            }
        }
        .test(.GET, "/test", headers: ["Cookie": sessionCookie!.serialize(name: "vapor-session")]) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "Vapor")
            XCTAssertNotNil(res.headers.first(name: .setCookie))
        }
    }

    func testMiddlewareConfigExistential() {
        struct Test: Authenticatable {
            static func authenticator() -> Authenticator {
                TestAuthenticator()
            }
            var name: String
        }

        struct TestAuthenticator: BearerAuthenticator {
            typealias User = Test

            func authenticate(bearer: BearerAuthorization, for request: Request) async throws { }
        }

        var config = Middlewares()
        config.use(Test.authenticator())
    }

    func testAsyncAuthenticator() async throws {
        struct Test: Authenticatable {
            static func authenticator(threadPool: NIOThreadPool) -> Authenticator {
                TestAuthenticator(threadPool: threadPool)
            }
            var name: String
        }

        struct TestAuthenticator: BasicAuthenticator {
            typealias User = Test
            let threadPool: NIOThreadPool

            func authenticate(basic: BasicAuthorization, for request: Request) async throws {
                try await Task.sleep(for: .milliseconds(10))
                if basic.username == "test" && basic.password == "secret" {
                    let test = Test(name: "Vapor")
                    await request.auth.login(test)
                }
            }
        }
        
        app.routes.grouped([
            Test.authenticator(threadPool: app.threadPool),
            Test.guardMiddleware()
        ]).get("test") { req -> String in
            return try await req.auth.require(Test.self).name
        }

        let basic = "test:secret".data(using: .utf8)!.base64EncodedString()
        try await app.testable().test(.GET, "/test") { res in
            XCTAssertEqual(res.status, .unauthorized)
        }.test(.GET, "/test", headers: ["Authorization": "Basic \(basic)"]) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "Vapor")
        }
    }
}
