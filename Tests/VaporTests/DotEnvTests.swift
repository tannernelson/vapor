@testable import Vapor
import XCTVapor
import XCTest
import NIOPosix
import NIOCore

final class DotEnvTests: XCTestCase {
    func testReadFile() async throws {
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let pool = NIOThreadPool(numberOfThreads: 1)
        pool.start()
        let folder = #filePath.split(separator: "/").dropLast().joined(separator: "/")
        let path = "/" + folder + "/Utilities/test.env"
        let file = try await DotEnvFile.read(path: path)
        let test = file.lines.map { $0.description }.joined(separator: "\n")
        XCTAssertEqual(test, """
        NODE_ENV=development
        BASIC=basic
        AFTER_LINE=after_line
        UNDEFINED_EXPAND=$TOTALLY_UNDEFINED_ENV_KEY
        EMPTY=
        SINGLE_QUOTES=single_quotes
        DOUBLE_QUOTES=double_quotes
        EXPAND_NEWLINES=expand\nnewlines
        DONT_EXPAND_NEWLINES_1=dontexpand\\nnewlines
        DONT_EXPAND_NEWLINES_2=dontexpand\\nnewlines
        EQUAL_SIGNS=equals==
        RETAIN_INNER_QUOTES={"foo": "bar"}
        RETAIN_INNER_QUOTES_AS_STRING={"foo": "bar"}
        INCLUDE_SPACE=some spaced out string
        USERNAME=therealnerdybeast@example.tld
        """)
        try await pool.shutdownGracefully()
        try await elg.shutdownGracefully()
    }

    func testNoTrailingNewline() throws {
        let env = "FOO=bar\nBAR=baz"
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString(env)
        var parser = DotEnvFile.Parser(source: buffer)
        let lines = parser.parse()
        XCTAssertEqual(lines, [
            .init(key: "FOO", value: "bar"),
            .init(key: "BAR", value: "baz"),
        ])
    }
    func testCommentWithNoTrailingNewline() throws {
        let env = "FOO=bar\n#BAR=baz"
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString(env)
        var parser = DotEnvFile.Parser(source: buffer)
        let lines = parser.parse()
        XCTAssertEqual(lines, [
            .init(key: "FOO", value: "bar")
        ])
    }
}
