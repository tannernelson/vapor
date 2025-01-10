import XCTVapor
import XCTest
import Vapor
import NIOCore
import NIOHTTP1

final class QueryTests: XCTestCase {
    
    var app: Application!
    
    override func setUp() async throws {
        self.app = await Application(.testing)
    }
    
    override func tearDown() async throws {
        try await self.app.shutdown()
    }
    
    func testQuery() throws {
        let request = Request(application: app, on: app.eventLoopGroup.next())
        request.headers.contentType = .json
        request.url.path = "/foo"
        request.url.query = "hello=world"
        try XCTAssertEqual(request.query.get(String.self, at: "hello"), "world")
    }

    func testQueryAsArray() throws {
        let request = Request(application: app, on: app.eventLoopGroup.next())
        request.headers.contentType = .json
        request.url.path = "/foo"
        request.url.query = "hello=world&hello[]=you"
        try XCTAssertEqual(request.query.get([String].self, at: "hello"), ["world", "you"])
        try XCTAssertEqual(request.query.get([String].self, at: "goodbye"), [])
    }

    // https://github.com/vapor/vapor/pull/2163
    func testWrappedSingleValueQueryDecoding() throws {
        let request = Request(application: app, on: app.eventLoopGroup.next())
        request.headers.contentType = .json
        request.url.path = "/foo"
        request.url.query = ""

        // Think of property wrappers, or MongoKitten's ObjectId
        struct StringWrapper: Decodable {
            let string: String

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                string = try container.decode(String.self)
            }
        }

        XCTAssertThrowsError(try request.query.get(StringWrapper.self, at: "hello"))
    }

    func testNotCrashingArrayWithPercentEncoding() throws {
        let request = Request(application: app, on: app.eventLoopGroup.next())
        request.headers.contentType = .json
        request.url.path = "/"
        request.url.query = "emailsToSearch%5B%5D=xyz"
        let parsed = try request.query.get([String].self, at: "emailsToSearch")
        XCTAssertEqual(parsed, ["xyz"])
    }

    func testQueryGet() async throws {
        var req = Request(
            application: app,
            method: .GET,
            url: .init(string: "/path?foo=a"),
            on: app.eventLoopGroup.next()
        )

        XCTAssertEqual(try req.query.get(String.self, at: "foo"), "a")
        XCTAssertThrowsError(try req.query.get(Int.self, at: "foo")) { error in
            if case .typeMismatch(_, let context) = error as? DecodingError {
                XCTAssertEqual(context.debugDescription, "Data found at 'foo' was not Int")
            } else {
                XCTFail("Caught error \"\(error)\", but not the expected: \"DecodingError.typeMismatch\"")
            }
        }
        XCTAssertThrowsError(try req.query.get(String.self, at: "bar")) { error in
            if case .valueNotFound(_, let context) = error as? DecodingError {
                XCTAssertEqual(context.debugDescription, "No String was found at 'bar'")
            } else {
                XCTFail("Caught error \"\(error)\", but not the expected: \"DecodingError.valueNotFound\"")
            }
        }

        XCTAssertEqual(req.query[String.self, at: "foo"], "a")
        XCTAssertEqual(req.query[String.self, at: "bar"], nil)

        //
        req = Request(
            application: app,
            method: .GET,
            url: .init(string: "/path"),
            on: app.eventLoopGroup.next()
        )
        XCTAssertThrowsError(try req.query.get(Int.self, at: "foo")) { error in
            if let error = error as? DecodingError {
                XCTAssertEqual(error.status, .badRequest)
            } else {
                XCTFail("Caught error \"\(error)\"")
            }
        }
        XCTAssertEqual(req.query[String.self, at: "foo"], nil)
    }

    // https://github.com/vapor/vapor/issues/1537
    func testQueryStringRunning() async throws {
        app.routes.get("todos") { req in
            return "hi"
        }

        try await app.testable().test(.GET, "/todos?a=b") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "hi")
        }
    }

    func testURLEncodedFormDecodeQuery() async throws {
        struct User: Content {
            var name: String
            var age: Int
            var luckyNumbers: [Int]
            var pet: Pet
        }

        struct Pet: Content {
            var name: String
            var age: Int
        }

        app.get("urlencodedform") { req -> HTTPStatus in
            let foo = try req.query.decode(User.self)
            XCTAssertEqual(foo.name, "Vapor")
            XCTAssertEqual(foo.age, 3)
            XCTAssertEqual(foo.luckyNumbers, [5, 7])
            XCTAssertEqual(foo.pet.name, "Fido")
            XCTAssertEqual(foo.pet.age, 3)
            return .ok
        }

        let data = "name=Vapor&age=3&luckyNumbers[]=5&luckyNumbers[]=7&pet[name]=Fido&pet[age]=3"
        try await app.testable().test(.GET, "/urlencodedform?\(data)") { res in
            XCTAssertEqual(res.status.code, 200)
        }
    }

    func testURLPercentEncodedFormDecodeQuery() async throws {
        struct User: Content {
            var name: String
            var age: Int
            var luckyNumbers: [Int]
            var pet: Pet
        }

        struct Pet: Content {
            var name: String
            var age: Int
        }

        app.get("urlencodedform") { req -> HTTPStatus in
            let foo = try req.query.decode(User.self)
            XCTAssertEqual(foo.name, "Vapor")
            XCTAssertEqual(foo.age, 3)
            XCTAssertEqual(foo.luckyNumbers, [5, 7])
            XCTAssertEqual(foo.pet.name, "Fido")
            XCTAssertEqual(foo.pet.age, 3)
            return .ok
        }

        let data = "name=Vapor&age=3&luckyNumbers[]=5&luckyNumbers[]=7&pet[name]=Fido&pet[age]=3".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        try await app.testable().test(.GET, "/urlencodedform?\(data)") { res in
            XCTAssertEqual(res.status.code, 200)
        }
    }

    func testCustomEncode() async throws {
        app.get("custom-encode") { req -> Response in
            let res = Response(status: .ok)
            let jsonEncoder = JSONEncoder()
            jsonEncoder.outputFormatting = .prettyPrinted
            try res.content.encode(["hello": "world"], using: jsonEncoder)
            return res
        }

        try await app.testable().test(.GET, "/custom-encode") { res in
            XCTAssertEqual(res.body.string, """
            {
              "hello" : "world"
            }
            """)
        }
    }

    // https://github.com/vapor/vapor/issues/1609
    func testGH1609() async throws {
        struct DecodeFail: Content {
            var here: String
            var missing: String
        }

        app.post("decode-fail") { req -> String in
            _ = try req.content.decode(DecodeFail.self)
            return "ok"
        }

        var body = ByteBufferAllocator().buffer(capacity: 0)
        body.writeString(#"{"here":"hi"}"#)
        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .contentLength, value: body.readableBytes.description)
        headers.contentType = .json

        try await app.testable().test(.POST, "/decode-fail", headers: headers, body: body) { res in
            XCTAssertEqual(res.status, .badRequest)
            XCTAssertContains(res.body.string, "missing")
        }
    }

    // https://github.com/vapor/vapor/issues/1687
    func testRequestQueryStringPercentEncoding() throws {
        struct TestQueryStringContainer: Content {
            var name: String
        }
        let req = Request(application: app, on: app.eventLoopGroup.next())
        try req.query.encode(TestQueryStringContainer(name: "Vapor Test"))
        XCTAssertEqual(req.url.query, "name=Vapor%20Test")
    }

    // https://github.com/vapor/vapor/issues/2383
    func testQueryKeyDecoding() throws {
        struct Test: Codable, Equatable {
            struct Page: Codable, Equatable {
                var offset: Int
                var limit: Int
            }
            let page: Page
            struct Filter: Codable, Equatable {
                var ids: [String]
            }
            let filter: Filter
        }

        let query = "page[offset]=0&page[limit]=50&filter[ids]=auth0,abc123"
        let a = try URLEncodedFormDecoder().decode(Test.self, from: query)
        XCTAssertEqual(a.page.offset, 0)
        XCTAssertEqual(a.page.limit, 50)
        XCTAssertEqual(a.filter.ids, ["auth0", "abc123"])
        let b = try URLEncodedFormDecoder().decode(Test.self, from: query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)
        XCTAssertEqual(a, b)
    }

    func testOptionalGet() throws {
        let req = Request(
            application: app,
            method: .GET,
            url: URI(string: "/"),
            on: app.eventLoopGroup.next()
        )
        do {
            req.url = .init(path: "/foo?bar=baz")
            let page = try req.query.get(Int?.self, at: "page")
            XCTAssertEqual(page, nil)
        }
        do {
            req.url = .init(path: "/foo?bar=baz&page=1")
            let page = try req.query.get(Int?.self, at: "page")
            XCTAssertEqual(page, 1)
        }
        do {
            req.url = .init(path: "/foo?bar=baz&page=a")
            XCTAssertThrowsError(try req.query.get(Int?.self, at: "page"))
        }
    }

    func testValuelessParamGet() throws {
        let req = Request(
            application: app,
            method: .GET,
            url: URI(string: "/"),
            on: app.eventLoopGroup.next()
        )
        struct BarStruct : Content {
            let bar: Bool
        }
        struct OptionalBarStruct : Content {
            let bar: Bool?
            let baz: String?
        }

        req.url = .init(path: "/foo?bar")
        XCTAssertTrue(try req.query.get(Bool.self, at: "bar"))
        XCTAssertTrue(try req.query.decode(BarStruct.self).bar)
        XCTAssertEqual(try req.query.decode(OptionalBarStruct.self).bar, true)

        req.url = .init(path: "/foo?bar&baz=bop")
        XCTAssertTrue(try req.query.get(Bool.self, at: "bar"))
        XCTAssertTrue(try req.query.decode(BarStruct.self).bar)
        XCTAssertEqual(try req.query.decode(OptionalBarStruct.self).bar, true)

        req.url = .init(path: "/foo")
        XCTAssertFalse(try req.query.get(Bool.self, at: "bar"))
        XCTAssertFalse(try req.query.decode(BarStruct.self).bar)
        XCTAssertNil(try req.query.decode(OptionalBarStruct.self).bar)

        req.url = .init(path: "/foo?baz=bop")
        XCTAssertFalse(try req.query.get(Bool.self, at: "bar"))
        XCTAssertFalse(try req.query.decode(BarStruct.self).bar)
        XCTAssertNil(try req.query.decode(OptionalBarStruct.self).bar)
    }
    
    func testNotCrashingWhenUnkeyedContainerIsAtEnd() async throws {
        struct Query: Decodable {
            let closedRange: ClosedRange<Double>
        }
        
        let app = await Application()
        
        let request = Request(application: app, on: app.eventLoopGroup.next())
        request.headers.contentType = .json
        request.url.path = "/"
        request.url.query = "closedRange=1"
        
        XCTAssertThrowsError(try request.query.decode(Query.self)) { error in
            if case .valueNotFound(_, let context) = error as? DecodingError {
                XCTAssertEqual(context.debugDescription, "Unkeyed container is at end.")
            } else {
                XCTFail("Caught error \"\(error)\", but not the expected: \"DecodingError.valueNotFound\"")
            }
        }
        
        try await app.shutdown()
    }
}
