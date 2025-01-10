import Foundation
import Vapor
import XCTest
import AsyncHTTPClient
import NIOCore
import NIOPosix
import NIOConcurrencyHelpers
import NIOHTTP1
import NIOSSL
import Atomics


let markerHeader = HTTPHeaders.Name.xVaporResponseCompression.description

final class ConditionalResponseCompressionParsingTests: XCTestCase, @unchecked Sendable {
    func testEncodingEnable() {
        var headers = HTTPHeaders()
        headers.responseCompression = .enable
        XCTAssertEqual(headers, [markerHeader : "enable"])
    }
    
    func testEncodingDisable() {
        var headers = HTTPHeaders()
        headers.responseCompression = .disable
        XCTAssertEqual(headers, [markerHeader : "disable"])
    }
    
    func testEncodingUseDefault() {
        var headers = HTTPHeaders()
        headers.responseCompression = .useDefault
        XCTAssertEqual(headers, [markerHeader : "useDefault"])
    }
    
    func testEncodingUnset() {
        var headers = HTTPHeaders()
        headers.responseCompression = .unset
        XCTAssertEqual(headers, [:])
    }
    
    func testUpdating() {
        var headers = HTTPHeaders()
        headers.responseCompression = .enable
        XCTAssertEqual(headers, [markerHeader : "enable"])
        headers.responseCompression = .disable
        XCTAssertEqual(headers, [markerHeader : "disable"])
        headers.responseCompression = .unset
        XCTAssertEqual(headers, [:])
        headers.add(name: markerHeader, value: "enable")
        headers.add(name: markerHeader, value: "disable")
        XCTAssertEqual(headers, [markerHeader : "enable", markerHeader : "disable"])
        headers.responseCompression = .disable
        XCTAssertEqual(headers, [markerHeader : "disable"])
    }
    
    func testDecodingUnset() {
        let headers: HTTPHeaders = [:]
        XCTAssertEqual(headers.responseCompression, .unset)
    }
    
    func testDecodingEnabled() {
        let headers: HTTPHeaders = [markerHeader : "enable"]
        XCTAssertEqual(headers.responseCompression, .enable)
    }
    
    func testDecodingDisabled() {
        let headers: HTTPHeaders = [markerHeader : "disable"]
        XCTAssertEqual(headers.responseCompression, .disable)
    }
    
    func testDecodingUseDefault() {
        let headers: HTTPHeaders = [markerHeader : "useDefault"]
        XCTAssertEqual(headers.responseCompression, .useDefault)
    }
    
    func testDecodingLiteralUnset() {
        let headers: HTTPHeaders = [markerHeader : "unset"]
        XCTAssertEqual(headers.responseCompression, .unset)
    }
    
    func testDecodingOther() {
        let headers: HTTPHeaders = [markerHeader : "other"]
        XCTAssertEqual(headers.responseCompression, .unset)
    }
    
    func testDecodingMultipleValid() {
        let headers: HTTPHeaders = [markerHeader : "enable", markerHeader : "disable"]
        XCTAssertEqual(headers.responseCompression, .disable)
    }
    
    func testDecodingMultipleFirstInvalid() {
        let headers: HTTPHeaders = [markerHeader : "other", markerHeader : "enable"]
        XCTAssertEqual(headers.responseCompression, .enable)
    }
    
    func testDecodingMultipleLastInvalid() {
        let headers: HTTPHeaders = [markerHeader : "enable", markerHeader : "other"]
        XCTAssertEqual(headers.responseCompression, .unset)
    }
}


private let compressiblePayload = #"{"compressed": ["key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value", "key": "value"]}"#

private let unknownType = HTTPMediaType(type: "vapor-test", subType: "unknown")

#warning("Fix")
/*
final class ConditionalResponseCompressionServerTests: XCTestCase, @unchecked Sendable {
    var app: Application!
    
    func assertCompressed(
        _ configuration: HTTPServer.Configuration.ResponseCompressionConfiguration,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        XCTAssertNotNil(app.http.server.shared.localAddress)
        guard let localAddress = app.http.server.shared.localAddress,
              let port = localAddress.port else {
            XCTFail("couldn't get ip/port from \(app.http.server.shared.localAddress.debugDescription)")
            return
        }
        
        app.http.server.configuration.responseCompression = configuration
        
        let response = try await app.client.get("http://localhost:\(port)/resource") { request in
            request.headers.replaceOrAdd(name: .acceptEncoding, value: "gzip")
        }
        XCTAssertEqual(response.headers.first(name: .contentEncoding), "gzip", file: file, line: line)
        XCTAssertNotEqual(response.headers.first(name: .contentLength), "\(compressiblePayload.count)", file: file, line: line)
        XCTAssertEqual(response.body?.string, compressiblePayload, file: file, line: line)
    }
    
    func assertUncompressed(
        _ configuration: HTTPServer.Configuration.ResponseCompressionConfiguration,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        XCTAssertNotNil(app.http.server.shared.localAddress)
        guard let localAddress = app.http.server.shared.localAddress,
              let port = localAddress.port else {
            XCTFail("couldn't get ip/port from \(app.http.server.shared.localAddress.debugDescription)")
            return
        }
        
        app.http.server.configuration.responseCompression = configuration
        
        let response = try await app.client.get("http://localhost:\(port)/resource") { request in
            request.headers.replaceOrAdd(name: .acceptEncoding, value: "gzip")
        }
        XCTAssertNotEqual(response.headers.first(name: .contentEncoding), "gzip", file: file, line: line)
        XCTAssertEqual(response.headers.first(name: .contentLength), "\(compressiblePayload.count)", file: file, line: line)
        XCTAssertEqual(response.body?.string, compressiblePayload, file: file, line: line)
    }
    
    override func setUp() async throws {
        let test = Environment(name: "testing", arguments: ["vapor"])
        app = await Application(test)
        app.http.server.configuration.hostname = "127.0.0.1"
        app.http.server.configuration.port = 0
        
        app.http.server.configuration.supportVersions = [.one]
        
        /// Make sure the client doesn't keep the server open by re-using the connection.
        app.http.client.configuration.maximumUsesPerConnection = 1
        app.http.client.configuration.decompression = .enabled(limit: .none)
    }
    
    override func tearDown() async throws {
        await app.server.shutdown()
        try await app.asyncShutdown()
    }
    
    func testAutoDetectedType() async throws {
        app.get("resource") { _ in compressiblePayload }
        
        try app.server.start()
        
        try await assertUncompressed(app.http.server.configuration.responseCompression) /// Default case
        try await assertUncompressed(.forceDisabled)
        try await assertUncompressed(.disabled)
        try await assertCompressed(.enabledForCompressibleTypes)
        try await assertCompressed(.enabled)
        
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: false))
        try await assertCompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: false))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: true))
        try await assertCompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: true))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: true))
        
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: false))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: true))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: true))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: true))
    }
    
    func testUnknownType() async throws {
        app.get("resource") { request in
            var headers = HTTPHeaders()
            headers.contentType = unknownType /// Not explicitely marked as compressible or not.
            return compressiblePayload.encodeResponse(status: .ok, headers: headers, for: request)
        }
        
        try app.server.start()
        
        try await assertUncompressed(app.http.server.configuration.responseCompression) /// Default case
        try await assertUncompressed(.forceDisabled)
        try await assertUncompressed(.disabled)
        try await assertUncompressed(.enabledForCompressibleTypes)
        try await assertCompressed(.enabled)
        
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: false))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: true))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: true))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: true))
        
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: false))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: true))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: true))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: true))
    }
    
    func testImage() async throws {
        app.get("resource") { request in
            var headers = HTTPHeaders()
            headers.contentType = .png /// PNGs are explicitely called out as incompressible.
            return compressiblePayload.encodeResponse(status: .ok, headers: headers, for: request)
        }
        
        try app.server.start()
        
        try await assertUncompressed(app.http.server.configuration.responseCompression) /// Default case
        try await assertUncompressed(.forceDisabled)
        try await assertUncompressed(.disabled)
        try await assertUncompressed(.enabledForCompressibleTypes)
        try await assertUncompressed(.enabled)
        
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: false))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: true))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: true))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: true))
        
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: false))
        try await assertUncompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: false))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: true))
        try await assertUncompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: true))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: true))
    }
    
    func testVideo() async throws {
        app.get("resource") { request in
            var headers = HTTPHeaders()
            headers.contentType = .mpeg /// Videos are explicitely called out as incompressible, but as a class.
            return compressiblePayload.encodeResponse(status: .ok, headers: headers, for: request)
        }
        
        try app.server.start()
        
        try await assertUncompressed(app.http.server.configuration.responseCompression) /// Default case
        try await assertUncompressed(.forceDisabled)
        try await assertUncompressed(.disabled)
        try await assertUncompressed(.enabledForCompressibleTypes)
        try await assertUncompressed(.enabled)
        
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: false))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: true))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: true))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: true))
        
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: false))
        try await assertUncompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: false))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: true))
        try await assertUncompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: true))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: true))
    }
    
    func testText() async throws {
        app.get("resource") { request in
            var headers = HTTPHeaders()
            headers.contentType = .plainText /// Text types are explicitely called out as compressible, but as a class.
            return compressiblePayload.encodeResponse(status: .ok, headers: headers, for: request)
        }
        
        try app.server.start()
        
        try await assertUncompressed(app.http.server.configuration.responseCompression) /// Default case
        try await assertUncompressed(.forceDisabled)
        try await assertUncompressed(.disabled)
        try await assertCompressed(.enabledForCompressibleTypes)
        try await assertCompressed(.enabled)
        
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: false))
        try await assertCompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: false))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: true))
        try await assertCompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: true))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: true))
        
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: false))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: true))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: true))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: true))
    }
    
    func testEnabledByResponse() async throws {
        app.get("resource") { request in
            var headers = HTTPHeaders()
            headers.contentType = unknownType
            headers.responseCompression = .enable
            return compressiblePayload.encodeResponse(status: .ok, headers: headers, for: request)
        }
        
        try app.server.start()
        
        try await assertCompressed(app.http.server.configuration.responseCompression) /// Default case
        try await assertUncompressed(.forceDisabled)
        try await assertCompressed(.disabled)
        try await assertCompressed(.enabledForCompressibleTypes)
        try await assertCompressed(.enabled)
        
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: false))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: false))
        try await assertCompressed(.disabled(allowedTypes: .none, allowRequestOverrides: true))
        try await assertCompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: true))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: true))
        
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: true))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: true))
        try await assertCompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: true))
    }
    
    func testDisabledByResponse() async throws {
        app.get("resource") { request in
            var headers = HTTPHeaders()
            headers.contentType = unknownType
            headers.responseCompression = .disable
            return compressiblePayload.encodeResponse(status: .ok, headers: headers, for: request)
        }
        
        try app.server.start()
        
        try await assertUncompressed(app.http.server.configuration.responseCompression) /// Default case
        try await assertUncompressed(.forceDisabled)
        try await assertUncompressed(.disabled)
        try await assertUncompressed(.enabledForCompressibleTypes)
        try await assertUncompressed(.enabled)
        
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: false))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: true))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: true))
        try await assertUncompressed(.disabled(allowedTypes: .all, allowRequestOverrides: true))
        
        try await assertUncompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: false))
        try await assertUncompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: false))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: false))
        try await assertUncompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: true))
        try await assertUncompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: true))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: true))
    }
    
    func testForceEnabledByResponse() async throws {
        app.responseCompression(HTTPHeaders.ResponseCompression.disable).get("resource") { request in
            var headers = HTTPHeaders()
            headers.contentType = unknownType
            headers.responseCompression = .enable
            return compressiblePayload.encodeResponse(status: .ok, headers: headers, for: request)
        }
        
        try app.server.start()
        
        try await assertCompressed(app.http.server.configuration.responseCompression) /// Default case
        try await assertUncompressed(.forceDisabled)
        try await assertCompressed(.disabled)
        try await assertCompressed(.enabledForCompressibleTypes)
        try await assertCompressed(.enabled)
        
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: false))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: false))
        try await assertCompressed(.disabled(allowedTypes: .none, allowRequestOverrides: true))
        try await assertCompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: true))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: true))
        
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: true))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: true))
        try await assertCompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: true))
    }
    
    func testForceDisabledByResponse() async throws {
        app.responseCompression(HTTPHeaders.ResponseCompression.enable).get("resource") { request in
            var headers = HTTPHeaders()
            headers.contentType = unknownType
            headers.responseCompression = .disable
            return compressiblePayload.encodeResponse(status: .ok, headers: headers, for: request)
        }
        
        try app.server.start()
        
        try await assertUncompressed(app.http.server.configuration.responseCompression) /// Default case
        try await assertUncompressed(.forceDisabled)
        try await assertUncompressed(.disabled)
        try await assertUncompressed(.enabledForCompressibleTypes)
        try await assertUncompressed(.enabled)
        
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: false))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: true))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: true))
        try await assertUncompressed(.disabled(allowedTypes: .all, allowRequestOverrides: true))
        
        try await assertUncompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: false))
        try await assertUncompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: false))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: false))
        try await assertUncompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: true))
        try await assertUncompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: true))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: true))
    }
    
    func testEnabledByRoute() async throws {
        app.responseCompression(HTTPHeaders.ResponseCompression.enable).get("resource") { request in
            var headers = HTTPHeaders()
            headers.contentType = unknownType
            return compressiblePayload.encodeResponse(status: .ok, headers: headers, for: request)
        }
        
        try app.server.start()
        
        try await assertCompressed(app.http.server.configuration.responseCompression) /// Default case
        try await assertUncompressed(.forceDisabled)
        try await assertCompressed(.disabled)
        try await assertCompressed(.enabledForCompressibleTypes)
        try await assertCompressed(.enabled)
        
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: false))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: false))
        try await assertCompressed(.disabled(allowedTypes: .none, allowRequestOverrides: true))
        try await assertCompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: true))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: true))
        
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: true))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: true))
        try await assertCompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: true))
    }
    
    func testDisabledByRoute() async throws {
        app.responseCompression(HTTPHeaders.ResponseCompression.disable).get("resource") { request in
            var headers = HTTPHeaders()
            headers.contentType = unknownType
            return compressiblePayload.encodeResponse(status: .ok, headers: headers, for: request)
        }
        
        try app.server.start()
        
        try await assertUncompressed(app.http.server.configuration.responseCompression) /// Default case
        try await assertUncompressed(.forceDisabled)
        try await assertUncompressed(.disabled)
        try await assertUncompressed(.enabledForCompressibleTypes)
        try await assertUncompressed(.enabled)
        
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: false))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: true))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: true))
        try await assertUncompressed(.disabled(allowedTypes: .all, allowRequestOverrides: true))
        
        try await assertUncompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: false))
        try await assertUncompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: false))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: false))
        try await assertUncompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: true))
        try await assertUncompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: true))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: true))
    }
    
    func testDisabledByRouteButReset() async throws {
        app.responseCompression(HTTPHeaders.ResponseCompression.disable).responseCompression(HTTPHeaders.ResponseCompression.useDefault).get("resource") { request in
            var headers = HTTPHeaders()
            headers.contentType = unknownType
            return compressiblePayload.encodeResponse(status: .ok, headers: headers, for: request)
        }
        
        try app.server.start()
        
        try await assertUncompressed(app.http.server.configuration.responseCompression) /// Default case
        try await assertUncompressed(.forceDisabled)
        try await assertUncompressed(.disabled)
        try await assertUncompressed(.enabledForCompressibleTypes)
        try await assertCompressed(.enabled)
        
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: false))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: true))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: true))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: true))
        
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: false))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: true))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: true))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: true))
    }
    
    func testEnabledByRouteButReset() async throws {
        app.responseCompression(HTTPHeaders.ResponseCompression.enable).responseCompression(HTTPHeaders.ResponseCompression.useDefault).get("resource") { request in
            var headers = HTTPHeaders()
            headers.contentType = unknownType
            return compressiblePayload.encodeResponse(status: .ok, headers: headers, for: request)
        }
        
        try app.server.start()
        
        try await assertUncompressed(app.http.server.configuration.responseCompression) /// Default case
        try await assertUncompressed(.forceDisabled)
        try await assertUncompressed(.disabled)
        try await assertUncompressed(.enabledForCompressibleTypes)
        try await assertCompressed(.enabled)
        
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: false))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: true))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: true))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: true))
        
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: false))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: true))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: true))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: true))
    }
    
    func testDisabledByRouteResetByResponse() async throws {
        app.responseCompression(HTTPHeaders.ResponseCompression.disable).get("resource") { request in
            var headers = HTTPHeaders()
            headers.responseCompression = .useDefault
            headers.contentType = unknownType
            return compressiblePayload.encodeResponse(status: .ok, headers: headers, for: request)
        }
        
        try app.server.start()
        
        try await assertUncompressed(app.http.server.configuration.responseCompression) /// Default case
        try await assertUncompressed(.forceDisabled)
        try await assertUncompressed(.disabled)
        try await assertUncompressed(.enabledForCompressibleTypes)
        try await assertCompressed(.enabled)
        
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: false))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: true))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: true))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: true))
        
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: false))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: true))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: true))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: true))
    }
    
    func testEnabledByRouteResetByResponse() async throws {
        app.responseCompression(HTTPHeaders.ResponseCompression.enable).get("resource") { request in
            var headers = HTTPHeaders()
            headers.responseCompression = .useDefault
            headers.contentType = unknownType
            return compressiblePayload.encodeResponse(status: .ok, headers: headers, for: request)
        }
        
        try app.server.start()
        
        try await assertUncompressed(app.http.server.configuration.responseCompression) /// Default case
        try await assertUncompressed(.forceDisabled)
        try await assertUncompressed(.disabled)
        try await assertUncompressed(.enabledForCompressibleTypes)
        try await assertCompressed(.enabled)
        
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: false))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: true))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: true))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: true))
        
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: false))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: true))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: true))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: true))
    }
    
    func testNoopsDisabledByRouteButReset() async throws {
        app
            .responseCompression(HTTPHeaders.ResponseCompression.unset)
            .responseCompression(HTTPHeaders.ResponseCompression.disable)
            .responseCompression(HTTPHeaders.ResponseCompression.unset)
            .responseCompression(HTTPHeaders.ResponseCompression.useDefault)
            .responseCompression(HTTPHeaders.ResponseCompression.unset)
            .get("resource") { request in
                var headers = HTTPHeaders()
                headers.contentType = unknownType
                return compressiblePayload.encodeResponse(status: .ok, headers: headers, for: request)
            }
        
        try app.server.start()
        
        try await assertUncompressed(app.http.server.configuration.responseCompression) /// Default case
        try await assertUncompressed(.forceDisabled)
        try await assertUncompressed(.disabled)
        try await assertUncompressed(.enabledForCompressibleTypes)
        try await assertCompressed(.enabled)
        
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: false))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: true))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: true))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: true))
        
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: false))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: true))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: true))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: true))
    }
    
    func testNoopsEnabledByRouteButReset() async throws {
        app
            .responseCompression(HTTPHeaders.ResponseCompression.unset)
            .responseCompression(HTTPHeaders.ResponseCompression.enable)
            .responseCompression(HTTPHeaders.ResponseCompression.unset)
            .responseCompression(HTTPHeaders.ResponseCompression.useDefault)
            .responseCompression(HTTPHeaders.ResponseCompression.unset)
            .get("resource") { request in
                var headers = HTTPHeaders()
                headers.contentType = unknownType
                return compressiblePayload.encodeResponse(status: .ok, headers: headers, for: request)
            }
        
        try app.server.start()
        
        try await assertUncompressed(app.http.server.configuration.responseCompression) /// Default case
        try await assertUncompressed(.forceDisabled)
        try await assertUncompressed(.disabled)
        try await assertUncompressed(.enabledForCompressibleTypes)
        try await assertCompressed(.enabled)
        
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: false))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: false))
        try await assertUncompressed(.disabled(allowedTypes: .none, allowRequestOverrides: true))
        try await assertUncompressed(.disabled(allowedTypes: .compressible, allowRequestOverrides: true))
        try await assertCompressed(.disabled(allowedTypes: .all, allowRequestOverrides: true))
        
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: false))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: false))
        try await assertCompressed(.enabled(disallowedTypes: .none, allowRequestOverrides: true))
        try await assertCompressed(.enabled(disallowedTypes: .incompressible, allowRequestOverrides: true))
        try await assertUncompressed(.enabled(disallowedTypes: .all, allowRequestOverrides: true))
    }
}
*/

final class ConditionalResponseCompressionRouteTests: XCTestCase, @unchecked Sendable {
    var app: Application!
    
    override func setUp() async throws {
        let test = Environment(name: "testing", arguments: ["vapor"])
        app = await Application(test)
    }
    
    override func tearDown() async throws {
        try await app.shutdown()
    }
    
    func assertResponseCompression(
        middleware: any Middleware,
        responder: any Responder,
        compressionValue: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let response = try await middleware.respond(to: Request(application: app, on: app.eventLoopGroup.next()), chainingTo: responder)
        let header = response.headers[canonicalForm: .xVaporResponseCompression]
        
        XCTAssertEqual(header, compressionValue.map { $0.components(separatedBy: ", ") }?.map { $0[...] } ?? [], file: file, line: line)
    }
    
    let enabledMiddleware = ResponseCompressionMiddleware(override: HTTPHeaders.ResponseCompression.enable)
    let disabledMiddleware = ResponseCompressionMiddleware(override: HTTPHeaders.ResponseCompression.disable)
    let defaultMiddleware = ResponseCompressionMiddleware(override: HTTPHeaders.ResponseCompression.useDefault)
    let unsetMiddleware = ResponseCompressionMiddleware(override: HTTPHeaders.ResponseCompression.unset)
    
    let forceEnabledMiddleware = ResponseCompressionMiddleware(override: HTTPHeaders.ResponseCompression.enable, force: true)
    let forceDisabledMiddleware = ResponseCompressionMiddleware(override: HTTPHeaders.ResponseCompression.disable, force: true)
    let forceDefaultMiddleware = ResponseCompressionMiddleware(override: HTTPHeaders.ResponseCompression.useDefault, force: true)
    let forceUnsetMiddleware = ResponseCompressionMiddleware(override: HTTPHeaders.ResponseCompression.unset, force: true)
    
    func testRoutingDoesNotPrioritizeUnsetResponse() async throws {
        let unsetResponse = TestResponder { _ in Response() }
        
        try await assertResponseCompression(middleware: enabledMiddleware, responder: unsetResponse, compressionValue: "enable")
        try await assertResponseCompression(middleware: disabledMiddleware, responder: unsetResponse, compressionValue: "disable")
        try await assertResponseCompression(middleware: defaultMiddleware, responder: unsetResponse, compressionValue: "useDefault")
        try await assertResponseCompression(middleware: unsetMiddleware, responder: unsetResponse, compressionValue: nil)
        
        try await assertResponseCompression(middleware: forceEnabledMiddleware, responder: unsetResponse, compressionValue: "enable")
        try await assertResponseCompression(middleware: forceDisabledMiddleware, responder: unsetResponse, compressionValue: "disable")
        try await assertResponseCompression(middleware: forceDefaultMiddleware, responder: unsetResponse, compressionValue: "useDefault")
        try await assertResponseCompression(middleware: forceUnsetMiddleware, responder: unsetResponse, compressionValue: nil)
    }
    
    func testRoutingDoesNotPrioritizeEmptyResponse() async throws {
        let emptyResponse = TestResponder { _ in Response(headers: [markerHeader : ""]) }
        
        try await assertResponseCompression(middleware: enabledMiddleware, responder: emptyResponse, compressionValue: "enable")
        try await assertResponseCompression(middleware: disabledMiddleware, responder: emptyResponse, compressionValue: "disable")
        try await assertResponseCompression(middleware: defaultMiddleware, responder: emptyResponse, compressionValue: "useDefault")
        try await assertResponseCompression(middleware: unsetMiddleware, responder: emptyResponse, compressionValue: nil)
        
        try await assertResponseCompression(middleware: forceEnabledMiddleware, responder: emptyResponse, compressionValue: "enable")
        try await assertResponseCompression(middleware: forceDisabledMiddleware, responder: emptyResponse, compressionValue: "disable")
        try await assertResponseCompression(middleware: forceDefaultMiddleware, responder: emptyResponse, compressionValue: "useDefault")
        try await assertResponseCompression(middleware: forceUnsetMiddleware, responder: emptyResponse, compressionValue: nil)
    }
    
    func testRoutingPrioritizesEnabledResponse() async throws {
        let enabledResponse = TestResponder { _ in Response(headers: [markerHeader : "enable"]) }
        
        try await assertResponseCompression(middleware: enabledMiddleware, responder: enabledResponse, compressionValue: "enable")
        try await assertResponseCompression(middleware: disabledMiddleware, responder: enabledResponse, compressionValue: "enable")
        try await assertResponseCompression(middleware: defaultMiddleware, responder: enabledResponse, compressionValue: "enable")
        try await assertResponseCompression(middleware: unsetMiddleware, responder: enabledResponse, compressionValue: "enable")
        
        try await assertResponseCompression(middleware: forceEnabledMiddleware, responder: enabledResponse, compressionValue: "enable")
        try await assertResponseCompression(middleware: forceDisabledMiddleware, responder: enabledResponse, compressionValue: "disable")
        try await assertResponseCompression(middleware: forceDefaultMiddleware, responder: enabledResponse, compressionValue: "useDefault")
        try await assertResponseCompression(middleware: forceUnsetMiddleware, responder: enabledResponse, compressionValue: nil)
    }
    
    func testRoutingPrioritizesDisabledResponse() async throws {
        let disabledResponse = TestResponder { _ in Response(headers: [markerHeader : "disable"]) }
        
        try await assertResponseCompression(middleware: enabledMiddleware, responder: disabledResponse, compressionValue: "disable")
        try await assertResponseCompression(middleware: disabledMiddleware, responder: disabledResponse, compressionValue: "disable")
        try await assertResponseCompression(middleware: defaultMiddleware, responder: disabledResponse, compressionValue: "disable")
        try await assertResponseCompression(middleware: unsetMiddleware, responder: disabledResponse, compressionValue: "disable")
        
        try await assertResponseCompression(middleware: forceEnabledMiddleware, responder: disabledResponse, compressionValue: "enable")
        try await assertResponseCompression(middleware: forceDisabledMiddleware, responder: disabledResponse, compressionValue: "disable")
        try await assertResponseCompression(middleware: forceDefaultMiddleware, responder: disabledResponse, compressionValue: "useDefault")
        try await assertResponseCompression(middleware: forceUnsetMiddleware, responder: disabledResponse, compressionValue: nil)
    }
    
    func testRoutingDoesNotPrioritizeOtherResponse() async throws {
        let otherResponse = TestResponder { _ in Response(headers: [markerHeader : "other"]) }
        
        try await assertResponseCompression(middleware: enabledMiddleware, responder: otherResponse, compressionValue: "enable")
        try await assertResponseCompression(middleware: disabledMiddleware, responder: otherResponse, compressionValue: "disable")
        try await assertResponseCompression(middleware: defaultMiddleware, responder: otherResponse, compressionValue: "useDefault")
        try await assertResponseCompression(middleware: unsetMiddleware, responder: otherResponse, compressionValue: nil)
        
        try await assertResponseCompression(middleware: forceEnabledMiddleware, responder: otherResponse, compressionValue: "enable")
        try await assertResponseCompression(middleware: forceDisabledMiddleware, responder: otherResponse, compressionValue: "disable")
        try await assertResponseCompression(middleware: forceDefaultMiddleware, responder: otherResponse, compressionValue: "useDefault")
        try await assertResponseCompression(middleware: forceUnsetMiddleware, responder: otherResponse, compressionValue: nil)
    }
    
    func testRoutingPrioritizesMultipleResponse() async throws {
        let multipleResponse = TestResponder { _ in Response(headers: [markerHeader : "enable", markerHeader : "disable"]) }
        
        try await assertResponseCompression(middleware: enabledMiddleware, responder: multipleResponse, compressionValue: "enable, disable")
        try await assertResponseCompression(middleware: disabledMiddleware, responder: multipleResponse, compressionValue: "enable, disable")
        try await assertResponseCompression(middleware: defaultMiddleware, responder: multipleResponse, compressionValue: "enable, disable")
        try await assertResponseCompression(middleware: unsetMiddleware, responder: multipleResponse, compressionValue: "enable, disable")
        
        try await assertResponseCompression(middleware: forceEnabledMiddleware, responder: multipleResponse, compressionValue: "enable")
        try await assertResponseCompression(middleware: forceDisabledMiddleware, responder: multipleResponse, compressionValue: "disable")
        try await assertResponseCompression(middleware: forceDefaultMiddleware, responder: multipleResponse, compressionValue: "useDefault")
        try await assertResponseCompression(middleware: forceUnsetMiddleware, responder: multipleResponse, compressionValue: nil)
    }
}

private struct TestResponder: Responder {
    let transform: @Sendable (_ request: Request) -> Response
    
    func respond(to request: Request) async throws -> Response {
        transform(request)
    }
}
