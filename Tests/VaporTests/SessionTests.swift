import XCTVapor
import XCTest
import Vapor
import NIOCore
import NIOHTTP1

final class SessionTests: XCTestCase {
    var app: Application!
    
    override func setUp() async throws {
        let test = Environment(name: "testing", arguments: ["vapor"])
        app = await Application(test)
    }
    
    override func tearDown() async throws {
        try await app.shutdown()
    }
    
    func testSessionDestroy() async throws {
        actor MockKeyedCache: SessionDriver {
            var ops: [String] = []
            init() { }

            func getOps() -> [String] {
                ops
            }
            
            func resetOps() {
                self.ops = []
            }

            func createSession(_ data: SessionData, for request: Request) async throws -> SessionID {
                self.ops.append("create \(data)")
                return .init(string: "a")
            }

            func readSession(_ sessionID: SessionID, for request: Request) async throws -> SessionData? {
                self.ops.append("read \(sessionID)")
                return SessionData()
            }

            func updateSession(_ sessionID: SessionID, to data: SessionData, for request: Request) async throws -> SessionID {
                self.ops.append("update \(sessionID) to \(data)")
                return sessionID
            }

            func deleteSession(_ sessionID: SessionID, for request: Request) async throws {
                self.ops.append("delete \(sessionID)")
                return
            }
        }

        var cookie: HTTPCookies.Value?

        let cache = MockKeyedCache()
        app.sessions.use { _ in cache }
        let sessions = app.routes.grouped(app.sessions.middleware)
        sessions.get("set") { req -> String in
            await req.session.set("foo", to: "bar")
            return "set"
        }
        sessions.get("del") { req  -> String in
            await req.session.destroy()
            return "del"
        }

        try await app.testable().test(.GET, "/set") { res in
            XCTAssertEqual(res.body.string, "set")
            cookie = res.headers.setCookie?["vapor-session"]
            XCTAssertNotNil(cookie)
            let ops = await cache.ops
            XCTAssertEqual(ops, [
                #"create SessionData(storage: ["foo": "bar"])"#,
            ])
            await cache.resetOps()
        }

        XCTAssertEqual(cookie?.string, "a")

        var headers = HTTPHeaders()
        var cookies = HTTPCookies()
        cookies["vapor-session"] = cookie
        headers.cookie = cookies
        try await app.testable().test(.GET, "/del", headers: headers) { res in
            XCTAssertEqual(res.body.string, "del")
            let ops = await cache.ops
            XCTAssertEqual(ops, [
                #"read SessionID(string: "a")"#,
                #"delete SessionID(string: "a")"#
            ])
        }
    }

    func testInvalidCookie() async throws {
        // Configure sessions.
        app.sessions.use(.memory)
        app.middleware.use(app.sessions.middleware)

        // Adds data to the request session.
        app.get("set") { req -> HTTPStatus in
            await req.session.set("foo", to: "bar")
            return .ok
        }

        // Fetches data from the request session.
        app.get("get") { req -> String in
            guard let foo = await req.session.data["foo"] else {
                throw Abort(.badRequest)
            }
            return foo
        }


        // Test accessing session with no cookie.
        try await app.test(.GET, "get") { res in
            XCTAssertEqual(res.status, .badRequest)
        }

        // Test setting session with invalid cookie.
        var newCookie: HTTPCookies.Value?
        try await app.test(.GET, "set", beforeRequest: { req in
            req.headers.cookie = ["vapor-session": "foo"]
        }, afterResponse: { res in
            // We should get a new cookie back.
            newCookie = res.headers.setCookie?["vapor-session"]
            XCTAssertNotNil(newCookie)
            // That is not the same as the invalid cookie we sent.
            XCTAssertNotEqual(newCookie?.string, "foo")
            XCTAssertEqual(res.status, .ok)
        })

        // Test accessing newly created session.
        try await app.test(.GET, "get", beforeRequest: { req in
            // Pass cookie from previous request.
            req.headers.cookie = ["vapor-session": newCookie!]
        }, afterResponse: { res in
            // Session access should be successful.
            XCTAssertEqual(res.body.string, "bar")
            XCTAssertEqual(res.status, .ok)
        })
    }

    func testCookieQuotes() throws {
        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .cookie, value: #"foo= "+cookie/value" "#)
        XCTAssertEqual(headers.cookie?["foo"]?.string, "+cookie/value")
    }
}
