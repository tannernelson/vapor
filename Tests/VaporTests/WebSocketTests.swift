import Vapor
import NIOConcurrencyHelpers
import XCTest
import WebSocketKit
import NIOPosix

final class WebSocketTests: XCTestCase {
    
    var app: Application!
    
    override func setUp() async throws {
        app = await Application(.testing)
    }
    
    override func tearDown() async throws {
        try await app.shutdown()
    }
    
    func testWebSocketClient() async throws {
        var config = app.http.server.configuration
        config.port = 0
        await app.http.server.shared.updateConfiguration(config)

        app.webSocket("echo") { req, ws in
            ws.onText { ws.send($1) }
        }
        app.environment.arguments = ["serve"]
        try await app.start()

        guard let localAddress = app.http.server.shared.localAddress, let port = localAddress.port else {
            XCTFail("couldn't get port from \(app.http.server.shared.localAddress.debugDescription)")
            return
        }

        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        let promise = elg.next().makePromise(of: String.self)
        let string = try await WebSocket.connect(
            to: "ws://localhost:\(port)/echo",
            on: elg.next()
        ) { ws in
            ws.send("Hello, world!")
            ws.onText { ws, text in
                promise.succeed(text)
                ws.close().cascadeFailure(to: promise)
            }
        }.flatMap {
            return promise.futureResult
        }.flatMapError { error in
            promise.fail(error)
            return promise.futureResult
        }.get()
        XCTAssertEqual(string, "Hello, world!")
    }


    // https://github.com/vapor/vapor/issues/1997
    func testWebSocket404() async throws {
        app.webSocket("bar") { req, ws in
            ws.close(promise: nil)
        }

        var config = app.http.server.configuration
        config.port = 0
        await app.http.server.shared.updateConfiguration(config)
        app.environment.arguments = ["serve"]

        try await app.start()
        
        XCTAssertNotNil(app.http.server.shared.localAddress)
        guard let localAddress = app.http.server.shared.localAddress,
              let port = localAddress.port else {
            XCTFail("couldn't get ip/port from \(app.http.server.shared.localAddress.debugDescription)")
            return
        }

        do {
            try await WebSocket.connect(
                to: "ws://localhost:\(port)/foo",
                on: app.eventLoopGroup.next()
            ) { _ in  }.get()
            XCTFail("should have failed")
        } catch {
            // pass
        }
    }

    // https://github.com/vapor/vapor/issues/2009
    func testWebSocketServer() async throws {
        app.webSocket("foo") { req, ws in
            ws.send("foo")
            ws.close(promise: nil)
        }
        app.environment.arguments = ["serve"]
        var config = app.http.server.configuration
        config.port = 0
        await app.http.server.shared.updateConfiguration(config)

        try await app.start()
        
        XCTAssertNotNil(app.http.server.shared.localAddress)
        guard let localAddress = app.http.server.shared.localAddress,
              let port = localAddress.port else {
            XCTFail("couldn't get ip/port from \(app.http.server.shared.localAddress.debugDescription)")
            return
        }
        
        let promise = app.eventLoopGroup.next().makePromise(of: String.self)
        WebSocket.connect(
            to: "ws://localhost:\(port)/foo",
            on: app.eventLoopGroup.next()
        ) { ws in
            // do nothing
            ws.onText { ws, string in
                promise.succeed(string)
            }
        }.cascadeFailure(to: promise)

        try XCTAssertEqual(promise.futureResult.wait(), "foo")
    }

    func testManualUpgradeToWebSocket() async throws {
        var config = app.http.server.configuration
        config.port = 0
        await app.http.server.shared.updateConfiguration(config)

        app.get("foo") { req in
            return req.webSocket { req, ws in
                ws.send("foo")
                ws.close(promise: nil)
            }
        }

        app.environment.arguments = ["serve"]

        try await app.start()
        
        XCTAssertNotNil(app.http.server.shared.localAddress)
        guard let localAddress = app.http.server.shared.localAddress,
              let port = localAddress.port else {
            XCTFail("couldn't get ip/port from \(app.http.server.shared.localAddress.debugDescription)")
            return
        }
        
        let promise = app.eventLoopGroup.next().makePromise(of: String.self)
        WebSocket.connect(
            to: "ws://localhost:\(port)/foo",
            on: app.eventLoopGroup.next()
        ) { ws in
            ws.onText { ws, string in
                promise.succeed(string)
            }
        }.cascadeFailure(to: promise)

        try XCTAssertEqual(promise.futureResult.wait(), "foo")
    }

    override class func setUp() {
        XCTAssertTrue(isLoggingConfigured)
    }
}

extension WebSocketKit.WebSocket: Swift.Hashable {
    public static func == (lhs: WebSocket, rhs: WebSocket) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        ObjectIdentifier(self).hash(into: &hasher)
    }
}
