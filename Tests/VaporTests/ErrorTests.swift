import XCTest
import Vapor
import Logging

final class ErrorTests: XCTestCase {
    func testPrintable() throws {
        let expectedPrintable = """
        FooError.noFoo: You do not have a `foo`.
        Here are some possible causes:
        - You did not set the flongwaffle.
        - The session ended before a `Foo` could be made.
        - The universe conspires against us all.
        - Computers are hard.
        These suggestions could address the issue:
        - You really want to use a `Bar` here.
        - Take up the guitar and move to the beach.
        Vapor's documentation talks about this:
        - http://documentation.com/Foo
        - http://documentation.com/foo/noFoo

        """
        XCTAssertEqual(FooError.noFoo.debugDescription, expectedPrintable)
    }

    func testOmitEmptyFields() {
        XCTAssertTrue(FooError.noFoo.stackOverflowQuestions.isEmpty)
        XCTAssertFalse(
            FooError.noFoo.debugDescription.contains("Stack Overflow")
        )
    }

    func testReadableName() {
        XCTAssertEqual(FooError.readableName, "Foo Error")
    }

    func testIdentifier() {
        XCTAssertEqual(FooError.noFoo.identifier, "noFoo")
    }

    func testCausesAndSuggestions() {
        XCTAssertEqual(FooError.noFoo.possibleCauses, [
            "You did not set the flongwaffle.",
            "The session ended before a `Foo` could be made.",
            "The universe conspires against us all.",
            "Computers are hard."
        ])

        XCTAssertEqual(FooError.noFoo.suggestedFixes, [
            "You really want to use a `Bar` here.",
            "Take up the guitar and move to the beach."
        ])

        XCTAssertEqual(FooError.noFoo.documentationLinks, [
            "http://documentation.com/Foo",
            "http://documentation.com/foo/noFoo"
        ])
    }

    func testMinimumConformance() {
        let minimum = MinimumError.alpha
        let description = minimum.debugDescription
        let expectation = """
        MinimumError.alpha: Not enabled
        
        """
        XCTAssertEqual(description, expectation)
    }

    func testAbortError() async throws {
        let app = await Application(.testing)

        app.get("foo") { req -> String in
            throw Abort(.internalServerError, reason: "Foo")
        }

        app.post("foo") { req -> Foo in
            try req.content.decode(Foo.self)
        }

        struct AbortResponse: Content {
            var reason: String
        }

        try await app.test(.GET, "foo") { res in
            XCTAssertEqual(res.status, .internalServerError)
            let abort = try res.content.decode(AbortResponse.self)
            XCTAssertEqual(abort.reason, "Foo")
        }.test(.POST, "foo", beforeRequest: { req in
            try req.content.encode(Foo(bar: 42))
        }, afterResponse: { res in
            XCTAssertEqual(res.status, .internalServerError)
            let abort = try res.content.decode(AbortResponse.self)
            XCTAssertEqual(abort.reason, "After decode")
        })
        
        try await app.shutdown()
    }
    
    func testErrorMiddlewareUsesContentConfiguration() async throws {
        let app = await Application(.testing)
        
        app.get("foo") { req -> String in
            throw Abort(.internalServerError, reason: "Foo")
        }
        
        ContentConfiguration.global.use(encoder: URLEncodedFormEncoder(), for: .json)
        
        try await app.test(.GET, "foo") { res in
            XCTAssertEqual(res.status, HTTPStatus.internalServerError)
            let option1 = "error=true&reason=Foo"
            let option2 = "reason=Foo&error=true"
            guard res.body.string == option1 || res.body.string == option2 else {
                XCTFail("Response does not match")
                return
            }
        }
        
        // Clean up
        ContentConfiguration.global.use(encoder: JSONEncoder(), for: .json)
        
        try await app.shutdown()
    }
}

func XCTAssertContains(
    _ haystack: String?,
    _ needle: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let file = (file)
    guard let haystack = haystack else {
        XCTFail("\(needle) not found in: nil", file: file, line: line)
        return
    }
    if !haystack.contains(needle) {
        XCTFail("\(needle) not found in: \(haystack)", file: file, line: line)
    }
}

private struct Foo: Content {
    let bar: Int

    func afterDecode() throws {
        throw Abort(.internalServerError, reason: "After decode")
    }
}

private enum MinimumError: String, DebuggableError {
    case alpha, bravo, charlie

    /// The reason for the error.
    /// Typical implementations will switch over `self`
    /// and return a friendly `String` describing the error.
    /// - note: It is most convenient that `self` be a `Swift.Error`.
    ///
    /// Here is one way to do this:
    ///
    ///     switch self {
    ///     case someError:
    ///        return "A `String` describing what went wrong including the actual error: `Error.someError`."
    ///     // other cases
    ///     }
    var reason: String {
        switch self {
            case .alpha:
                return "Not enabled"
            case .bravo:
                return "Enabled, but I'm not configured"
            case .charlie:
                return "Broken beyond repair"
        }
    }

    var identifier: String {
        return rawValue
    }

    /// A `String` array describing the possible causes of the error.
    /// - note: Defaults to an empty array.
    /// Provide a custom implementation to give more context.
    var possibleCauses: [String] {
        return []
    }

    var suggestedFixes: [String] {
        return []
    }
}


private enum FooError: String, DebuggableError {
    case noFoo

    static var readableName: String {
        return "Foo Error"
    }

    var identifier: String {
        return rawValue
    }

    var reason: String {
        switch self {
        case .noFoo:
            return "You do not have a `foo`."
        }
    }

    var possibleCauses: [String] {
        switch self {
        case .noFoo:
            return [
                "You did not set the flongwaffle.",
                "The session ended before a `Foo` could be made.",
                "The universe conspires against us all.",
                "Computers are hard."
            ]
        }
    }

    var suggestedFixes: [String] {
        switch self {
        case .noFoo:
            return [
                "You really want to use a `Bar` here.",
                "Take up the guitar and move to the beach."
            ]
        }
    }

    var documentationLinks: [String] {
        switch self {
        case .noFoo:
            return [
                "http://documentation.com/Foo",
                "http://documentation.com/foo/noFoo"
            ]
        }
    }
}
