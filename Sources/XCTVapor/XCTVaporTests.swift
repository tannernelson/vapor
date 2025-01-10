import Vapor
import XCTest

open class XCTVaporTests: XCTestCase {
    open var app: Application!

    open override func setUpWithError() throws {

        // The XCTest runner calls this function before setUp()

        try super.setUpWithError()

        // this optional check due to prior usage by users
        // see: https://github.com/vapor/vapor/pull/2585#issuecomment-802144636
        if let _app = XCTVapor.app {
            self.app = try _app()
        }
    }

    open override func setUp() {

        // The XCTest runner calls this after setupWithError()

        super.setUp()

        guard let _app = XCTVapor.app else {
            fatalError("implement static app generator")
        }

        if self.app == nil {
            // this was the behavior of this class pre 4.41.5
            // keeping for compatibility however it will crash if
            // the function throws. Provided the user assigns to
            // XCTVapor.app in the class setUp or setUpWithError everything will work
            // as we intend.
            self.app = try! _app()
        }
    }
    
    open override func tearDown() async throws {
        try await super.tearDown()
        try await self.app?.shutdown()
        self.app = nil
    }
}
