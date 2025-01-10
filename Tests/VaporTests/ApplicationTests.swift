import Vapor
import XCTVapor
import AsyncHTTPClient
import XCTest
import NIOCore
import NIOEmbedded
import NIOConcurrencyHelpers

final class ApplicationTests: XCTestCase {
    
    var app: Application!
    
    override func setUp() async throws {
        app = await Application(.testing)
    }
    
    override func tearDown() async throws {
        try await app.shutdown()
    }
    
    func testApplicationStop() async throws {
        let test = Environment(name: "testing", arguments: ["vapor"])
        let app = await Application(test)
        app.environment.arguments = ["serve"]
        var config = app.http.server.configuration
        config.port = 0
        config.hostname = "127.0.0.1"
        await app.http.server.shared.updateConfiguration(config)

        try await app.start()
        guard let running = app.running else {
            XCTFail("app started without setting 'running'")
            return
        }
        running.stop()
        try await running.onStop.get()
        
        try await app.shutdown()
    }

    func testLifecycleHandler() async throws {
        final class Foo: LifecycleHandler {
            let willBootFlag: NIOLockedValueBox<Bool>
            let didBootFlag: NIOLockedValueBox<Bool>
            let shutdownFlag: NIOLockedValueBox<Bool>

            init() {
                self.willBootFlag = .init(false)
                self.didBootFlag = .init(false)
                self.shutdownFlag = .init(false)
            }
            
            func willBoot(_ application: Application) throws {
                self.willBootFlag.withLockedValue { $0 = true }
            }

            func didBoot(_ application: Application) throws {
                self.didBootFlag.withLockedValue { $0 = true }
            }

            func shutdown(_ application: Application) {
                self.shutdownFlag.withLockedValue { $0 = true }
            }
        }
        
        let app = await Application(.testing)

        let foo = Foo()
        app.lifecycle.use(foo)

        XCTAssertEqual(foo.willBootFlag.withLockedValue({ $0 }), false)
        XCTAssertEqual(foo.didBootFlag.withLockedValue({ $0 }), false)
        XCTAssertEqual(foo.shutdownFlag.withLockedValue({ $0 }), false)

        try await app.boot()

        XCTAssertEqual(foo.willBootFlag.withLockedValue({ $0 }), true)
        XCTAssertEqual(foo.didBootFlag.withLockedValue({ $0 }), true)
        XCTAssertEqual(foo.shutdownFlag.withLockedValue({ $0 }), false)

        try await app.shutdown()

        XCTAssertEqual(foo.willBootFlag.withLockedValue({ $0 }), true)
        XCTAssertEqual(foo.didBootFlag.withLockedValue({ $0 }), true)
        XCTAssertEqual(foo.shutdownFlag.withLockedValue({ $0 }), true)
    }

    func testBootDoesNotTriggerLifecycleHandlerMultipleTimes() async throws {
        final class Handler: LifecycleHandler, Sendable {
            let bootCount = NIOLockedValueBox(0)
            func willBoot(_ application: Application) async throws {
                bootCount.withLockedValue { $0 += 1 }
            }
        }
        
        let handler = Handler()
        app.lifecycle.use(handler)
        
        try await app.boot()
        try await app.boot()

        XCTAssertEqual(handler.bootCount.withLockedValue({ $0 }), 1)
    }
    
    func testAsyncBootDoesNotTriggerLifecycleHandlerMultipleTimes() async throws {
        final class Handler: LifecycleHandler, Sendable {
            let bootCount = NIOLockedValueBox(0)
            func willBoot(_ application: Application) async throws {
                bootCount.withLockedValue { $0 += 1 }
            }
        }
        
        let handler = Handler()
        app.lifecycle.use(handler)
        
        try await app.boot()
        try await app.boot()

        XCTAssertEqual(handler.bootCount.withLockedValue({ $0 }), 1)
    }
    
#warning("?")
    /*
    func testThrowDoesNotCrash() throws {
        enum Static {
            static let app: NIOLockedValueBox<Application?> = .init(nil)
        }
        Static.app.withLockedValue { $0 = await Application(.testing) }
        Static.app.withLockedValue { $0 = nil }
    }
*/
    func testSwiftError() async throws {
        struct Foo: Error { }
        
        app.get("error") { req -> String in
            throw Foo()
        }

        try await app.testable().test(.GET, "/error") { res in
            XCTAssertEqual(res.status, .internalServerError)
        }
    }

    func testBoilerplate() async throws {
        app.get("hello") { req in
            "Hello, world!"
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

        let res = try await app.client.get("http://localhost:\(port)/hello")
        XCTAssertEqual(res.body?.string, "Hello, world!")
    }

    func testAutomaticPortPickingWorks() async throws {
        var config = app.http.server.configuration
        config.port = 0
        config.hostname = "127.0.0.1"
        await app.http.server.shared.updateConfiguration(config)

        app.get("hello") { req in
            "Hello, world!"
        }

        XCTAssertNil(app.http.server.shared.localAddress)

        app.environment.arguments = ["serve"]
        try await app.start()

        XCTAssertNotNil(app.http.server.shared.localAddress)
        guard let localAddress = app.http.server.shared.localAddress,
              let ip = localAddress.ipAddress,
              let port = localAddress.port else {
            XCTFail("couldn't get ip/port from \(app.http.server.shared.localAddress.debugDescription)")
            return
        }

        XCTAssertEqual("127.0.0.1", ip)
        XCTAssertGreaterThan(port, 0)

        let response = try await app.client.get("http://localhost:\(port)/hello")
        XCTAssertEqual("Hello, world!", response.body?.string)
    }

    func testConfigurationAddressDetailsReflectedAfterBeingSet() async throws {
        var config = app.http.server.configuration
        config.port = 0
        config.hostname = "0.0.0.0"
        await app.http.server.shared.updateConfiguration(config)
        
        struct AddressConfig: Content {
            let hostname: String
            let port: Int
        }
        
        app.get("hello") { req -> AddressConfig in
            let config = AddressConfig(hostname: req.application.http.server.configuration.hostname, port: req.application.http.server.configuration.port)
            return config
        }

        app.environment.arguments = ["serve"]
        try await app.start()

        XCTAssertNotNil(app.http.server.shared.localAddress)
        XCTAssertEqual("0.0.0.0", app.http.server.configuration.hostname)
        XCTAssertEqual(app.http.server.shared.localAddress?.port, app.http.server.configuration.port)
        
        guard let localAddress = app.http.server.shared.localAddress,
              localAddress.ipAddress != nil,
              let port = localAddress.port else {
            XCTFail("couldn't get ip/port from \(app.http.server.shared.localAddress.debugDescription)")
            return
        }
        let response = try await app.client.get("http://localhost:\(port)/hello")
        let returnedConfig = try response.content.decode(AddressConfig.self)
        XCTAssertEqual(returnedConfig.hostname, "0.0.0.0")
        XCTAssertEqual(returnedConfig.port, port)
    }

    func testConfigurationAddressDetailsReflectedWhenProvidedThroughServeCommand() async throws {
        struct AddressConfig: Content {
            let hostname: String
            let port: Int
        }

        app.get("hello") { req -> AddressConfig in
            let config = AddressConfig(hostname: req.application.http.server.configuration.hostname, port: req.application.http.server.configuration.port)
            return config
        }

        app.environment.arguments = ["vapor", "serve", "--hostname", "0.0.0.0", "--port", "3000"]
        try await app.start()

        XCTAssertNotNil(app.http.server.shared.localAddress)
        XCTAssertEqual("0.0.0.0", app.http.server.configuration.hostname)
        XCTAssertEqual(3000, app.http.server.configuration.port)

        guard let localAddress = app.http.server.shared.localAddress,
              localAddress.ipAddress != nil,
              let port = localAddress.port else {
            XCTFail("couldn't get ip/port from \(app.http.server.shared.localAddress.debugDescription)")
            return
        }
        let response = try await app.client.get("http://localhost:\(port)/hello")
        let returnedConfig = try response.content.decode(AddressConfig.self)
        XCTAssertEqual(returnedConfig.hostname, "0.0.0.0")
        XCTAssertEqual(returnedConfig.port, 3000)
    }
}
