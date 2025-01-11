import XCTVapor
import XCTest
import Vapor
import NIOCore
import Tracing

final class MiddlewareTests: XCTestCase {
    var app: Application!
    
    override func setUp() async throws {
        let test = Environment(name: "testing", arguments: ["vapor"])
        app = try await Application.make(test)
    }
    
    override func tearDown() async throws {
        try await app.asyncShutdown()
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
        func respond(to req: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
            req.eventLoop.makeFutureWithTask {
                await self.store.addOrder(self.pos)
            }.flatMap {
                next.respond(to: req)
            }
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

    func testCORSMiddlewareVariedByRequestOrigin() throws {
        app.grouped(
            CORSMiddleware(configuration: .init(allowedOrigin: .originBased, allowedMethods: [.GET], allowedHeaders: [.origin]))
        ).get("order") { req -> String in
            return "done"
        }

        try app.testable().test(.GET, "/order", headers: ["Origin": "foo"]) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "done")
            XCTAssertEqual(res.headers[.vary], ["origin"])
            XCTAssertEqual(res.headers[.accessControlAllowOrigin], ["foo"])
            XCTAssertEqual(res.headers[.accessControlAllowHeaders], ["origin"])
        }
    }

    func testCORSMiddlewareNoVariationByRequestOriginAllowed() throws {
        app.grouped(
            CORSMiddleware(configuration: .init(allowedOrigin: .none, allowedMethods: [.GET], allowedHeaders: []))
        ).get("order") { req -> String in
            return "done"
        }

        try app.testable().test(.GET, "/order", headers: ["Origin": "foo"]) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "done")
            XCTAssertEqual(res.headers[.vary], [])
            XCTAssertEqual(res.headers[.accessControlAllowOrigin], [])
            XCTAssertEqual(res.headers[.accessControlAllowHeaders], [""])
        }
    }
    
    func testFileMiddlewareFromBundle() async throws {
        var fileMiddleware: FileMiddleware!
        
        XCTAssertNoThrow(fileMiddleware = try FileMiddleware(bundle: .module, publicDirectory: "/"), "FileMiddleware instantiation from Bundle should not fail")
        
        app.middleware.use(fileMiddleware)
        
        try await app.testable().test(.GET, "/foo.txt") { result async in
            XCTAssertEqual(result.status, .ok)
            XCTAssertEqual(result.body.string, "bar\n")
        }
    }
    
    func testFileMiddlewareFromBundleSubfolder() async throws {
        var fileMiddleware: FileMiddleware!
        
        XCTAssertNoThrow(fileMiddleware = try FileMiddleware(bundle: .module, publicDirectory: "SubUtilities"), "FileMiddleware instantiation from Bundle should not fail")
        
        app.middleware.use(fileMiddleware)
        
        try await app.testable().test(.GET, "/index.html") { result async in
            XCTAssertEqual(result.status, .ok)
            XCTAssertEqual(result.body.string, "<h1>Subdirectory Default</h1>\n")
        }
    }
    
    func testFileMiddlewareFromBundleInvalidPublicDirectory() {
        XCTAssertThrowsError(try FileMiddleware(bundle: .module, publicDirectory: "/totally-real/folder")) { error in
            guard let error = error as? FileMiddleware.BundleSetupError else {
                return XCTFail("Error should be of type FileMiddleware.SetupError")
            }
            XCTAssertEqual(error, .publicDirectoryIsNotAFolder)
        }
    }
    
    func testTracingMiddleware() async throws {
        app.traceAutoPropagation = true
        let tracer = TestTracer()
        InstrumentationSystem.bootstrap(tracer)
        
        struct TestServiceContextMiddleware: Middleware {
            func respond(to request: Request, chainingTo next: any Responder) -> EventLoopFuture<Response> {
                XCTAssertNotNil(ServiceContext.current)
                return next.respond(to: request)
            }
        }
        
        app.grouped(
            TracingMiddleware() { attributes, _ in
                attributes["custom"] = "custom"
            }
        ).grouped(
            TestServiceContextMiddleware()
        ).get("testTracing") { req -> String in
            // Validates that TracingMiddleware sets the serviceContext
            XCTAssertNotNil(req.serviceContext)
            // Validates that TracingMiddleware exposes header extraction to backend
            XCTAssertEqual(req.serviceContext.extracted, "extracted")
            // Validates that the span's service context is propagated into the
            // Task.local storage of the responder closure, thereby ensuring that
            // spans created in the closure are nested under the request span.
            // Requires Application.traceAutoPropagation to be enabled
            XCTAssertNotNil(ServiceContext.current)
            return "done"
        }

        try await app.testable(method: .running(hostname: "127.0.0.1", port: 8080)).test(
            .GET,
            "/testTracing?foo=bar",
            beforeRequest: { request async in
                request.headers.add(name: HTTPHeaders.Name.userAgent.description, value: "test")
                request.headers.add(name: TestTracer.extractKey, value: "extracted")
            },
            afterResponse: { response async in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.body.string, "done")
            }
        )
        
        let span = try XCTUnwrap(tracer.spans.first)
        XCTAssertEqual(span.operationName, "GET /testTracing")
        
        XCTAssertEqual(span.attributes["http.request.method"]?.toSpanAttribute(), "GET")
        XCTAssertEqual(span.attributes["url.path"]?.toSpanAttribute(), "/testTracing")
        XCTAssertEqual(span.attributes["url.scheme"]?.toSpanAttribute(), nil)
        
        XCTAssertEqual(span.attributes["http.route"]?.toSpanAttribute(), "/testTracing")
        XCTAssertEqual(span.attributes["network.protocol.name"]?.toSpanAttribute(), "http")
        XCTAssertEqual(span.attributes["server.address"]?.toSpanAttribute(), "127.0.0.1")
        XCTAssertEqual(span.attributes["server.port"]?.toSpanAttribute(), 8080)
        XCTAssertEqual(span.attributes["url.query"]?.toSpanAttribute(), "foo=bar")
        
        XCTAssertEqual(span.attributes["client.address"]?.toSpanAttribute(), "127.0.0.1")
        XCTAssertEqual(span.attributes["network.peer.address"]?.toSpanAttribute(), "127.0.0.1")
        XCTAssertNotNil(span.attributes["network.peer.port"]?.toSpanAttribute())
        XCTAssertEqual(span.attributes["network.protocol.version"]?.toSpanAttribute(), "1.1")
        XCTAssertEqual(span.attributes["user_agent.original"]?.toSpanAttribute(), "test")
        
        XCTAssertEqual(span.attributes["custom"]?.toSpanAttribute(), "custom")
        
        XCTAssertEqual(span.attributes["http.response.status_code"]?.toSpanAttribute(), 200)
    }
}
