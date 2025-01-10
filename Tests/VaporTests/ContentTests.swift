import NIOCore
import NIOEmbedded
import NIOHTTP1
import Vapor
import XCTest
import XCTVapor

final class ContentTests: XCTestCase {
    
    var app: Application!
    
    override func setUp() async throws {
        self.app = await Application(.testing)
    }
    
    override func tearDown() async throws {
        try await self.app.shutdown()
    }
    
    func testContent() async throws {
        let request = Request(
            application: app,
            collectedBody: .init(string: #"{"hello": "world"}"#),
            on: EmbeddedEventLoop()
        )
        request.headers.contentType = .json
        try XCTAssertEqual(request.content.get(at: "hello"), "world")
    }

    func testComplexContent() async throws {
        // http://adobe.github.io/Spry/samples/data_region/JSONDataSetSample.html
        let complexJSON = """
        {
            "id": "0001",
            "type": "donut",
            "name": "Cake",
            "ppu": 0.55,
            "batters":
                {
                    "batter":
                        [
                            { "id": "1001", "type": "Regular" },
                            { "id": "1002", "type": "Chocolate" },
                            { "id": "1003", "type": "Blueberry" },
                            { "id": "1004", "type": "Devil's Food" }
                        ]
                },
            "topping":
                [
                    { "id": "5001", "type": "None" },
                    { "id": "5002", "type": "Glazed" },
                    { "id": "5005", "type": "Sugar" },
                    { "id": "5007", "type": "Powdered Sugar" },
                    { "id": "5006", "type": "Chocolate with Sprinkles" },
                    { "id": "5003", "type": "Chocolate" },
                    { "id": "5004", "type": "Maple" }
                ]
        }
        """
        let request = Request(
            application: app,
            collectedBody: .init(string: complexJSON),
            on: app.eventLoopGroup.any()
        )
        request.headers.contentType = .json
        try XCTAssertEqual(request.content.get(at: "batters", "batter", 1, "type"), "Chocolate")
    }

    func testGH1534() async throws {
        let data = """
        {"name":"hi","bar":"asdf"}
        """

        app.routes.get("decode_error") { _ -> String in
            struct Foo: Decodable {
                var name: String
                var bar: Int
            }
            let foo = try JSONDecoder().decode(Foo.self, from: Data(data.utf8))
            return foo.name
        }

        try await app.testable().test(.GET, "/decode_error") { res in
            XCTAssertEqual(res.status, .badRequest)
            XCTAssertContains(res.body.string, #"Value was not of type 'Int' at path 'bar'. Expected to decode Int but found a string"#)
        }
    }

    func testContentContainerEncode() async throws {
        struct FooContent: Content {
            var message: String = "hi"
        }
        struct FooEncodable: Encodable {
            var message: String = "hi"
        }

        app.routes.get("encode") { _ -> Response in
            let res = Response()
            try res.content.encode(FooContent())
            try res.content.encode(FooContent(), as: .json)
            try res.content.encode(FooEncodable(), as: .json)
            return res
        }

        try await app.testable().test(.GET, "/encode") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertContains(res.body.string, "hi")
        }
    }

    func testContentContainerDecode() async throws {
        struct FooContent: Content, Equatable {
            var message: String = "hi"
        }
        struct FooDecodable: Decodable, Equatable {
            var message: String = "hi"
        }

        app.routes.post("decode") { req async throws -> String in
            XCTAssertEqual(try req.content.decode(FooContent.self), FooContent())
            XCTAssertEqual(try req.content.decode(FooDecodable.self, as: .json), FooDecodable())
            return "decoded!"
        }

        try await app.testable().test(.POST, "/decode") { req in
            try req.content.encode(FooContent())
        } afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertContains(res.body.string, "decoded!")
        }

        app.routes.post("decode-bad-header") { req async throws -> String in
            XCTAssertEqual(req.headers.contentType, .audio)
            XCTAssertThrowsError(try req.content.decode(FooContent.self)) { error in
                guard let abort = error as? Abort, abort.status == .unsupportedMediaType else {
                    XCTFail("Unexpected error: \(error)")
                    return
                }
            }
            XCTAssertEqual(try req.content.decode(FooDecodable.self, as: .json), FooDecodable())
            return "decoded!"
        }

        try await app.testable().test(.POST, "/decode-bad-header") { req in
            try req.content.encode(FooContent())
            req.headers.contentType = .audio
        } afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertContains(res.body.string, "decoded!")
        }
    }

    func testMultipartDecode() async throws {
        let data = """
        --123\r
        Content-Disposition: form-data; name="name"\r
        \r
        Vapor\r
        --123\r
        Content-Disposition: form-data; name="age"\r
        \r
        4\r
        --123\r
        Content-Disposition: form-data; name="image"; filename="droplet.png"\r
        \r
        <contents of image>\r
        --123--\r

        """
        let expected = User(
            name: "Vapor",
            age: 4,
            image: File(data: "<contents of image>", filename: "droplet.png")
        )

        struct User: Content, Equatable {
            var name: String
            var age: Int
            var image: File
        }

        app.routes.get("multipart") { req -> User in
            let decoded = try req.content.decode(User.self)
            XCTAssertEqual(decoded, expected)
            return decoded
        }

        try await app.testable().test(.GET, "/multipart", headers: [
            "Content-Type": "multipart/form-data; boundary=123"
        ], body: .init(string: data)) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqualJSON(res.body.string, expected)
        }
    }

    func testMultipartDecodedEmptyMultipartForm() async throws {
        let data = """
        --123\r
        --123--\r
        """
        let expected = User(
            name: "Vapor"
        )

        struct User: Content, Equatable {
            var name: String
        }

        app.routes.get("multipart") { req -> User in
            let decoded = try req.content.decode(User.self)
            XCTAssertEqual(decoded, expected)
            return decoded
        }

        try await app.testable().test(.GET, "/multipart", headers: [
            "Content-Type": "multipart/form-data; boundary=123"
        ], body: .init(string: data)) { res in
            XCTAssertEqual(res.status, .unprocessableEntity)
        }
    }

    func testMultipartDecodedEmptyBody() async throws {
        let data = ""
        let expected = User(
            name: "Vapor"
        )

        struct User: Content, Equatable {
            var name: String
        }

        app.routes.get("multipart") { req -> User in
            let decoded = try req.content.decode(User.self)
            XCTAssertEqual(decoded, expected)
            return decoded
        }

        try await app.testable().test(.GET, "/multipart", headers: [
            "Content-Type": "multipart/form-data; boundary=123"
        ], body: .init(string: data)) { res in
            XCTAssertEqual(res.status, .unprocessableEntity)
        }
    }

    func testMultipartDecodeUnicode() async throws {
        let data = """
        --123\r
        Content-Disposition: form-data; name="name"\r
        \r
        Vapor\r
        --123\r
        Content-Disposition: form-data; name="age"\r
        \r
        4\r
        --123\r
        Content-Disposition: form-data; name="image"; filename="她在吃水果.png"; filename*="UTF-8\'\'%E5%A5%B9%E5%9C%A8%E5%90%83%E6%B0%B4%E6%9E%9C.png"\r
        \r
        <contents of image>\r
        --123--\r

        """
        let expected = User(
            name: "Vapor",
            age: 4,
            image: File(data: "<contents of image>", filename: "UTF-8\'\'%E5%A5%B9%E5%9C%A8%E5%90%83%E6%B0%B4%E6%9E%9C.png")
        )

        struct User: Content, Equatable, Sendable {
            var name: String
            var age: Int
            var image: File
        }

        app.routes.get("multipart") { req -> User in
            let decoded = try req.content.decode(User.self)
            XCTAssertEqual(decoded, expected)
            return decoded
        }

        try await app.testable().test(.GET, "/multipart", headers: [
            "Content-Type": "multipart/form-data; boundary=123"
        ], body: .init(string: data)) { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqualJSON(res.body.string, expected)
        }
    }

    func testMultipartEncode() async throws {
        struct User: Content {
            static let defaultContentType: HTTPMediaType = .formData
            var name: String
            var age: Int
            var image: File
        }

        app.get("multipart") { _ -> User in
            User(
                name: "Vapor",
                age: 4,
                image: File(data: "<contents of image>", filename: "droplet.png")
            )
        }
        try await app.testable().test(.GET, "/multipart") { res in
            XCTAssertEqual(res.status, .ok)
            let boundary = res.headers.contentType?.parameters["boundary"] ?? "none"
            XCTAssertContains(res.body.string, "Content-Disposition: form-data; name=\"name\"")
            XCTAssertContains(res.body.string, "--\(boundary)")
            XCTAssertContains(res.body.string, "filename=\"droplet.png\"")
            XCTAssertContains(res.body.string, "name=\"image\"")
        }
    }

    func testMultiPartEncodeUnicode() async throws {
        struct User: Content {
            static let defaultContentType: HTTPMediaType = .formData
            var name: String
            var age: Int
            var image: File
        }

        app.get("multipart") { _ -> User in
            User(
                name: "Vapor",
                age: 4,
                image: File(data: "<contents of image>", filename: "UTF-8\'\'%E5%A5%B9%E5%9C%A8%E5%90%83%E6%B0%B4%E6%9E%9C.png")
            )
        }
        try await app.testable().test(.GET, "/multipart") { res in
            XCTAssertEqual(res.status, .ok)
            let boundary = res.headers.contentType?.parameters["boundary"] ?? "none"
            XCTAssertContains(res.body.string, "Content-Disposition: form-data; name=\"name\"")
            XCTAssertContains(res.body.string, "--\(boundary)")
            XCTAssertContains(res.body.string, "filename=\"UTF-8\'\'%E5%A5%B9%E5%9C%A8%E5%90%83%E6%B0%B4%E6%9E%9C.png\"")
            XCTAssertContains(res.body.string, "name=\"image\"")
        }
    }

    func testURLEncodedFormDecode() async throws {
        struct User: Content {
            var name: String
            var age: Int
            var luckyNumbers: [Int]
        }

        app.get("urlencodedform") { req -> HTTPStatus in
            let foo = try req.content.decode(User.self)
            XCTAssertEqual(foo.name, "Vapor")
            XCTAssertEqual(foo.age, 3)
            XCTAssertEqual(foo.luckyNumbers, [5, 7])
            return .ok
        }

        var headers = HTTPHeaders()
        headers.contentType = .urlEncodedForm
        var body = ByteBufferAllocator().buffer(capacity: 0)
        body.writeString("name=Vapor&age=3&luckyNumbers[]=5&luckyNumbers[]=7")

        try await app.testable().test(.GET, "/urlencodedform", headers: headers, body: body) { res in
            XCTAssertEqual(res.status.code, 200)
        }
    }

    func testURLEncodedFormEncode() async throws {
        struct User: Content {
            static let defaultContentType: HTTPMediaType = .urlEncodedForm
            var name: String
            var age: Int
            var luckyNumbers: [Int]
        }

        app.get("urlencodedform") { _ -> User in
            User(name: "Vapor", age: 3, luckyNumbers: [5, 7])
        }
        try await app.testable().test(.GET, "/urlencodedform") { res in
            XCTAssertEqual(res.status.code, 200)
            XCTAssertEqual(res.headers.contentType, .urlEncodedForm)
            XCTAssertContains(res.body.string, "luckyNumbers[]=5")
            XCTAssertContains(res.body.string, "luckyNumbers[]=7")
            XCTAssertContains(res.body.string, "age=3")
            XCTAssertContains(res.body.string, "name=Vapor")
        }
    }

    func testJSONPreservesHTTPHeaders() async throws {
        app.get("check") { (req: Request) -> String in
            "\(req.headers.first(name: .init("X-Test-Value")) ?? "MISSING").\(req.headers.first(name: .contentType) ?? "?")"
        }

        try await app.test(.GET, "/check", headers: ["X-Test-Value": "PRESENT"], beforeRequest: { req in
            try req.content.encode(["foo": "bar"], as: .json)
        }) { res in
            XCTAssertEqual(res.body.string, "PRESENT.application/json; charset=utf-8")
        }
    }

    func testJSONAllowsContentTypeOverride() async throws {
        app.get("check") { (req: Request) -> String in
            "\(req.headers.first(name: .init("X-Test-Value")) ?? "MISSING").\(req.headers.first(name: .contentType) ?? "?")"
        }
        // Me and my sadistic sense of humor.
        ContentConfiguration.global.use(decoder: try! ContentConfiguration.global.requireDecoder(for: .json), for: .xml)

        try await app.testable().test(.GET, "/check", headers: [
            "X-Test-Value": "PRESENT"
        ], beforeRequest: { req in
            try req.content.encode(["foo": "bar"], as: .json)
            req.headers.contentType = .xml
        }) { res in
            XCTAssertEqual(res.body.string, "PRESENT.application/xml; charset=utf-8")
        }
    }

    func testBeforeEncodeContent() async throws {
        let content = SampleContent()
        XCTAssertEqual(content.name, "old name")

        let response = Response(status: .ok)
        try response.content.encode(content)

        let body = try XCTUnwrap(response.body.string)
        XCTAssertEqual(body, #"{"name":"new name"}"#)
    }

    func testAfterContentEncode() async throws {
        var body = ByteBufferAllocator().buffer(capacity: 0)
        body.writeString(#"{"name": "before decode"}"#)

        let request = Request(
            application: app,
            collectedBody: body,
            on: EmbeddedEventLoop()
        )

        request.headers.contentType = .json

        let content = try request.content.decode(SampleContent.self)
        XCTAssertEqual(content.name, "new name after decode")
    }

    func testSupportsJsonApi() async throws {
        var body = ByteBufferAllocator().buffer(capacity: 0)
        body.writeString(#"{"data": ["entity0", "entity1"], "meta": {}}"#)

        let request = Request(
            application: app,
            collectedBody: body,
            on: EmbeddedEventLoop()
        )

        request.headers.contentType = .jsonAPI

        let content = try request.content.decode(JsonApiContent.self)
        XCTAssertEqual(content.data, ["entity0", "entity1"])
    }

    func testQueryHooks() async throws {
        let request = Request(
            application: app,
            collectedBody: .init(string: ""),
            on: app.eventLoopGroup.any()
        )
        request.url.query = "name=before+decode"
        request.headers.contentType = .json

        let query = try request.query.decode(SampleContent.self)
        XCTAssertEqual(query.name, "new name after decode")
        try request.query.encode(query)
        XCTAssertEqual(request.url.query, "name=new%20name")
    }

    /// https://github.com/vapor/vapor/issues/3135
    func testDecodePercentEncodedQuery() async throws {
        let request = Request(
            application: app,
            collectedBody: .init(string: ""),
            on: app.eventLoopGroup.any()
        )
        request.url = .init(string: "/?name=value%20has%201%25%20of%20its%20percents")
        request.headers.contentType = .urlEncodedForm

        XCTAssertEqual(try request.query.get(String.self, at: "name"), "value has 1% of its percents")
    }

    /// https://github.com/vapor/vapor/issues/3133
    func testEncodePercentEncodedQuery() async throws {
        struct Foo: Content {
            var status: String
        }

        var request = ClientRequest(url: .init(scheme: "https", host: "example.com", path: "/api"))
        try request.query.encode(Foo(status:
            "⬆️ taylorswift just released swift-mongodb v0.10.1 – use BSON and MongoDB in pure Swift\n\nhttps://swiftpackageindex.com/tayloraswift/swift-mongodb#releases"
        ))

        XCTAssertEqual(request.url.string, "https://example.com/api?status=%E2%AC%86%EF%B8%8F%20taylorswift%20just%20released%20swift-mongodb%20v0.10.1%20%E2%80%93%20use%20BSON%20and%20MongoDB%20in%20pure%20Swift%0A%0Ahttps%3A%2F%2Fswiftpackageindex.com%2Ftayloraswift%2Fswift-mongodb%23releases")
    }

    func testSnakeCaseCodingKeyError() async throws {
        let req = Request(application: app, on: app.eventLoopGroup.any())
        try req.content.encode([
            "title": "The title"
        ], as: .json)

        struct PostInput: Content {
            enum CodingKeys: String, CodingKey {
                case id, title, isFree = "is_free"
            }

            let id: UUID?
            let title: String
            let isFree: Bool
        }
        XCTAssertThrowsError(try req.content.decode(PostInput.self)) { error in
            XCTAssertEqual(
                (error as? AbortError)?.reason,
                #"No such key 'is_free' at path ''. No value associated with key CodingKeys(stringValue: "is_free", intValue: nil) ("is_free")."#
            )
        }
    }

    func testDataCorruptionError() async throws {
        let req = Request(
            application: app,
            method: .GET,
            url: URI(string: "https://vapor.codes"),
            headersNoUpdate: ["Content-Type": "application/json"],
            collectedBody: ByteBuffer(string: #"{"badJson: "Key doesn't have a trailing quote"}"#),
            on: app.eventLoopGroup.any()
        )

        struct DecodeModel: Content {
            let badJson: String
        }
        XCTAssertThrowsError(try req.content.decode(DecodeModel.self)) { error in
            #if compiler(>=6.0)
            XCTAssertContains(
                (error as? AbortError)?.reason,
                #"Data corrupted at path ''. The given data was not valid JSON"#
            )
            #else
            XCTAssertContains(
                (error as? AbortError)?.reason,
                #"Data corrupted at path ''. The given data was not valid JSON. Underlying error: "#
            )
            #endif
        }
    }

    func testValueNotFoundError() async throws {
        let req = Request(application: app, on: app.eventLoopGroup.any())
        try req.content.encode([
            "items": ["1"]
        ], as: .json)

        struct DecodeModel: Content {
            struct Item: Content {
                init(from decoder: Decoder) throws {
                    var container = try decoder.unkeyedContainer()
                    _ = try container.decode(String.self)
                    _ = try container.decode(String.self)
                    fatalError()
                }
            }

            let items: Item
        }
        XCTAssertThrowsError(try req.content.decode(DecodeModel.self)) { error in
            XCTAssertEqual(
                (error as? AbortError)?.reason,
                #"No value found (expected type 'String') at path 'items.Index 1'. Unkeyed container is at end."#
            )
        }
    }

    func testTypeMismatchError() async throws {
        let req = Request(application: app, on: app.eventLoopGroup.any())
        try req.content.encode([
            "item": [
                "title": "The title"
            ]
        ], as: .json)

        struct DecodeModel: Content {
            struct Item: Content {
                let title: Int
            }

            let item: Item
        }
        XCTAssertThrowsError(try req.content.decode(DecodeModel.self)) { error in
            XCTAssertContains(
                (error as? AbortError)?.reason,
                #"Value was not of type 'Int' at path 'item.title'. Expected to decode Int but found a string"#
            )
        }
    }

    func testPlaintextDecode() async throws {
        let data = "255"

        app.routes.get("plaintext") { _ -> Response in
            let res = Response()
            try res.content.encode(data, as: .plainText)
            return res
        }

        app.routes.get("empty-plaintext") { _ -> Response in
            let res = Response()
            try res.content.encode("", as: .plainText)
            return res
        }

        try await app.testable().test(.GET, "/plaintext") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(try res.content.decode(UInt8.self), 255)
            XCTAssertEqual(try res.content.decode(String.self), "255")
        }

        try await app.testable().test(.GET, "/empty-plaintext") { res in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(try res.content.decode(String.self), "")
        }
    }

    func testPlaintextDecoderDoesntCrash() async throws {
        struct WrongType: Content {
            let example: String
        }

        app.routes.post("plaintext") { req -> String in
            _ = try req.content.decode(WrongType.self)
            return "OK"
        }

        let body = """
        {
          "example": "example"
        }
        """

        let byteBuffer = ByteBuffer(string: body)
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "text/plain")

        try await app.testable().test(.POST, "/plaintext", headers: headers, body: byteBuffer) { res in
            // This should return a 400 Bad Request and not crash
            XCTAssertEqual(res.status, .badRequest)
        }
    }

    func testContentIsBool() async throws {
        app.routes.get("success") { _ in
            true
        }

        try await app.testable().test(.GET, "/success") { res in
            XCTAssertEqual(try res.content.decode(Bool.self), true)
        }
    }
}

private struct SampleContent: Content {
    var name = "old name"

    mutating func beforeEncode() async throws {
        name = "new name"
    }

    mutating func afterDecode() async throws {
        name = "new name after decode"
    }
}

private struct JsonApiContent: Content {
    struct Meta: Codable {}

    var data: [String]
    var meta = Meta()
}
