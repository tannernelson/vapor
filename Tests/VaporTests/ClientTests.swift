import Dispatch
import Foundation
import XCTest
import Vapor
import NIOCore
import Logging
import AsyncHTTPClient
import NIOEmbedded
import NIOConcurrencyHelpers

final class ClientTests: XCTestCase {
    var remoteAppPort: Int!
    var remoteApp: Application!
    var app: Application!
    
    override func setUp() async throws {
        remoteApp = await Application(.testing)
        var config = app.http.server.configuration
        config.port = 0
        await app.http.server.shared.updateConfiguration(config)

        
        app = await Application(.testing)
        
        remoteApp.get("json") { _ in
            SomeJSON()
        }
        
        remoteApp.get("status", ":status") { req -> HTTPStatus in
            let status = try req.parameters.require("status", as: Int.self)
            return HTTPStatus(statusCode: status)
        }
        
        remoteApp.post("anything") { req -> AnythingResponse in
            let headers = req.headers.reduce(into: [String: String]()) {
                $0[$1.0] = $1.1
            }
            
            guard let json:[String:Any] = try JSONSerialization.jsonObject(with: req.body.data!) as? [String:Any] else {
                throw Abort(.badRequest)
            }
            
            let jsonResponse = json.mapValues {
                return "\($0)"
            }
            
            return AnythingResponse(headers: headers, json: jsonResponse)
        }

        remoteApp.get("stalling") { req in
            try await Task.sleep(for: .seconds(5))
            return SomeJSON()
        }
        
        remoteApp.environment.arguments = ["serve"]
        try await remoteApp.boot()
        try await remoteApp.start()
        
        XCTAssertNotNil(remoteApp.http.server.shared.localAddress)
        guard let localAddress = remoteApp.http.server.shared.localAddress,
              let port = localAddress.port else {
            XCTFail("couldn't get ip/port from \(remoteApp.http.server.shared.localAddress.debugDescription)")
            return
        }
        
        self.remoteAppPort = port
    }
    
    override func tearDown() async throws {
        try await remoteApp.shutdown()
        try await app.shutdown()
    }
    
#warning("Fix")
    /*
    func testClientConfigurationChange() async throws {
        app.http.client.configuration.redirectConfiguration = .disallow

        app.get("redirect") {
            $0.redirect(to: "foo")
        }

        try app.server.start(address: .hostname("localhost", port: 0))
        
        guard let port = app.http.server.shared.localAddress?.port else {
            XCTFail("Failed to get port for app")
            return
        }

        let res = try await app.client.get("http://localhost:\(port)/redirect")

        XCTAssertEqual(res.status, .seeOther)
    }
    
    func testClientConfigurationCantBeChangedAfterClientHasBeenUsed() async throws {
        let app = await Application(.testing)
        defer { app.shutdown() }

        app.http.client.configuration.redirectConfiguration = .disallow

        app.get("redirect") {
            $0.redirect(to: "foo")
        }

        try app.server.start(address: .hostname("localhost", port: 0))
        defer { app.server.shutdown() }
        
        guard let port = app.http.server.shared.localAddress?.port else {
            XCTFail("Failed to get port for app")
            return
        }

        _ = try await app.client.get("http://localhost:\(port)/redirect")
        
        app.http.client.configuration.redirectConfiguration = .follow(max: 1, allowCycles: false)
        let res = try await app.client.get("http://localhost:\(port)/redirect")
        XCTAssertEqual(res.status, .seeOther)
    }
*/
    func testClientResponseCodable() async throws {
        let res = try await app.client.get("http://localhost:\(remoteAppPort!)/json")

        let encoded = try JSONEncoder().encode(res)
        let decoded = try JSONDecoder().decode(ClientResponse.self, from: encoded)
        
        XCTAssertEqual(res, decoded)
    }
    
    func testClientBeforeSend() async throws {
        try await app.boot()
        
        let res = try await app.client.post("http://localhost:\(remoteAppPort!)/anything") { req in
            try req.content.encode(["hello": "world"])
        }

        let data = try res.content.decode(AnythingResponse.self)
        XCTAssertEqual(data.json, ["hello": "world"])
        XCTAssertEqual(data.headers["content-type"], "application/json; charset=utf-8")
    }
    
    func testClientContent() async throws {
        try await app.boot()
        
        let res = try await app.client.post("http://localhost:\(remoteAppPort!)/anything", content: ["hello": "world"])

        let data = try res.content.decode(AnythingResponse.self)
        XCTAssertEqual(data.json, ["hello": "world"])
        XCTAssertEqual(data.headers["content-type"], "application/json; charset=utf-8")
    }

    func testClientTimeout() async throws {
        try await app.boot()

        _ = try await app.client.get("http://localhost:\(remoteAppPort!)/json") { $0.timeout = .seconds(1) }
        var errorThrown = false
        do {
            _ = try await app.client.get("http://localhost:\(remoteAppPort!)/stalling") { $0.timeout = .seconds(1) }
        } catch {
            errorThrown = true
            XCTAssertTrue(type(of: error) == HTTPClientError.self, "\(type(of: error)) is not a \(HTTPClientError.self)")
            XCTAssertEqual(error as? HTTPClientError, .deadlineExceeded)
        }
        XCTAssertTrue(errorThrown)
    }
    
    func testBoilerplateClient() async throws {
        let remotePort = self.remoteAppPort!

        app.get("foo") { req in
            do {
                let res = try await req.client.get("http://localhost:\(remotePort)/status/201")
                XCTAssertEqual(res.status.code, 201)
                req.application.running?.stop()
                return "bar"
            } catch {
                req.application.running?.stop()
                throw error
            }
        }

        app.environment.arguments = ["serve"]
        var config = app.http.server.configuration
        config.port = 0
        await app.http.server.shared.updateConfiguration(config)

        try await app.boot()
        try await app.start()
        
        XCTAssertNotNil(app.http.server.shared.localAddress)
        guard let localAddress = app.http.server.shared.localAddress,
              let port = localAddress.port else {
            XCTFail("couldn't get ip/port from \(app.http.server.shared.localAddress.debugDescription)")
            return
        }

        let res = try await app.client.get("http://localhost:\(port)/foo")
        XCTAssertEqual(res.body?.string, "bar")

        try await app.running?.onStop.get()
    }
    
#warning("Fix")
    /*
    func testApplicationClientThreadSafety() async throws {
        let startingPistol = DispatchGroup()
        startingPistol.enter()
        startingPistol.enter()

        let finishLine = DispatchGroup()
        finishLine.enter()
        Thread.async {
            startingPistol.leave()
            startingPistol
            XCTAssert(type(of: app.http.client.shared) == HTTPClient.self)
            finishLine.leave()
        }

        finishLine.enter()
        Thread.async {
            startingPistol.leave()
            startingPistol
            XCTAssert(type(of: app.http.client.shared) == HTTPClient.self)
            finishLine.leave()
        }

        finishLine
    }
*/
    func testCustomClient() async throws {
        app.clients.use(.custom)
        _ = try await app.client.get("https://vapor.codes")

        XCTAssertEqual(app.customClient.requests.count, 1)
        XCTAssertEqual(app.customClient.requests.first?.url.host, "vapor.codes")
    }

    func testClientLogging() async throws {
        let logs = TestLogHandler()
        app.logger = logs.logger

        _ = try await app.client.get("http://localhost:\(remoteAppPort!)/status/201")

        let metadata = logs.getMetadata()
        XCTAssertNotNil(metadata["ahc-request-id"])
    }
}
