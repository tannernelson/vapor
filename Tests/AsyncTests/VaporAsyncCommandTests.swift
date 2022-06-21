//
//  VaporAsyncCommandTests.swift
//  
//
//  Created by Josercc on 2022/6/21.
//

#if compiler(>=5.5) && canImport(_Concurrency)
import XCTVapor
import Vapor

final class VaporAsyncCommandTests: XCTestCase {
    func testVaporAsyncCommand() async throws {
        struct TestCommandSignature: CommandSignature {
            @Argument(name: "age")
            var age: Int
        }
        struct TestCommand: VaporAsyncCommand {
            typealias Signature = TestCommandSignature
            
            var help: String { "print age number" }
            
            func runAsync(using context: CommandContext, signature: TestCommandSignature) async throws {
                context.console.output("I'm \(signature.age) years old".consoleText(color: .green))
            }
        }
        let app = Application(.testing)
        defer { app.shutdown() }
        let commandInput = CommandInput(arguments: ["vapor", "30"])
        var context = CommandContext(console: app.console, input: commandInput)
        context.application = app
        try app.console.run(TestCommand(), with: context)
        
    }
}

#endif
