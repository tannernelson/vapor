import XCTVapor
import XCTest
import Vapor

final class AsyncMiddlewareTests: XCTestCase {
    var app: Application!
    
    override func setUp() async throws {
        app = await Application(.testing)
    }
    
    override func tearDown() async throws {
        try await app.shutdown()
    }
    
    actor OrderStore {
        var order: [String] = []
        
        func addOrder(_ orderValue: String) {
            self.order.append(orderValue)
        }
        
        func getOrder() -> [String] {
            self.order
        }
    }
    
    final class OrderMiddleware: Middleware {
        let pos: String
        let store: OrderStore
        init(_ pos: String, store: OrderStore) {
            self.pos = pos
            self.store = store
        }
        func respond(to request: Request, chainingTo next: Responder) async throws -> Response {
            await store.addOrder(pos)
            return try await next.respond(to: request)
        }
    }

    func testMiddlewareOrder() async throws {
        let store = OrderStore()
        app.grouped(
            OrderMiddleware("a", store: store), OrderMiddleware("b", store: store), OrderMiddleware("c", store: store)
        ).get("order") { req -> String in
            return "done"
        }

        try await app.testable().test(.GET, "/order") { res in
            let order = await store.getOrder()
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(order, ["a", "b", "c"])
            XCTAssertEqual(res.body.string, "done")
        }
    }

    func testPrependingMiddleware() async throws {
        let store = OrderStore()
        app.middleware.use(OrderMiddleware("b", store: store))
        app.middleware.use(OrderMiddleware("c", store: store))
        app.middleware.use(OrderMiddleware("a", store: store), at: .beginning)
        app.middleware.use(OrderMiddleware("d", store: store), at: .end)

        app.get("order") { req -> String in
            return "done"
        }

        try await app.testable().test(.GET, "/order") { res in
            let order = await store.getOrder()
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(order, ["a", "b", "c", "d"])
            XCTAssertEqual(res.body.string, "done")
        }
    }

    func testCORSMiddlewareVariedByRequestOrigin() async throws {
        app.grouped(
            CORSMiddleware(configuration: .init(allowedOrigin: .originBased, allowedMethods: [.GET], allowedHeaders: [.origin]))
        ).get("order") { req -> String in
            return "done"
        }

        try await app.testable().test(.GET, "/order", headers: ["Origin": "foo"]) { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "done")
            XCTAssertEqual(res.headers[.vary], ["origin"])
            XCTAssertEqual(res.headers[.accessControlAllowOrigin], ["foo"])
            XCTAssertEqual(res.headers[.accessControlAllowHeaders], ["origin"])
        }
    }

    func testCORSMiddlewareNoVariationByRequestOriginAllowed() async throws {
        app.grouped(
            CORSMiddleware(configuration: .init(allowedOrigin: .none, allowedMethods: [.GET], allowedHeaders: []))
        ).get("order") { req -> String in
            return "done"
        }

        try await app.testable().test(.GET, "/order", headers: ["Origin": "foo"]) { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "done")
            XCTAssertEqual(res.headers[.vary], [])
            XCTAssertEqual(res.headers[.accessControlAllowOrigin], [])
            XCTAssertEqual(res.headers[.accessControlAllowHeaders], [""])
        }
    }
    
    func testFileMiddlewareFromBundleInvalidPublicDirectory() async throws {
        XCTAssertThrowsError(try FileMiddleware(bundle: .module, publicDirectory: "/totally-real/folder")) { error in
            guard let error = error as? FileMiddleware.BundleSetupError else {
                return XCTFail("Error should be of type FileMiddleware.SetupError")
            }
            XCTAssertEqual(error, .publicDirectoryIsNotAFolder)
        }
    }
}
