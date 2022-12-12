import Vapor

struct Creds: Content {
    var email: String
    var password: String
}

public func routes(_ app: Application) throws {
    app.on(.GET, "ping") { req -> StaticString in
        return "123" as StaticString
    }


    // ( echo -e 'POST /slow-stream HTTP/1.1\r\nContent-Length: 1000000000\r\n\r\n'; dd if=/dev/zero; ) | nc localhost 8080
    app.on(.POST, "slow-stream", body: .stream) { req -> EventLoopFuture<String> in
        let done = req.eventLoop.makePromise(of: String.self)

        var total = 0
        req.body.drain { result in
            let promise = req.eventLoop.makePromise(of: Void.self)

            switch result {
            case .buffer(let buffer):
                req.eventLoop.scheduleTask(in: .milliseconds(1000)) {
                    total += buffer.readableBytes
                    promise.succeed(())
                }
            case .error(let error):
                done.fail(error)
            case .end:
                promise.succeed(())
                done.succeed(total.description)
            }

            // manually return pre-completed future
            // this should balloon in memory
            // return req.eventLoop.makeSucceededFuture(())
            
            // return real future that indicates bytes were handled
            // this should use very little memory
            return promise.futureResult
        }

        return done.futureResult
    }

    app.get("test", "head") { req -> String in
        return "OK!"
    }

    app.post("test", "head") { req -> String in
        return "OK!"
    }
    
    app.post("login") { req -> String in
        let creds = try req.content.decode(Creds.self)
        return "\(creds)"
    }
    
    app.on(.POST, "large-file", body: .collect(maxSize: 1_000_000_000)) { req -> String in
        return req.body.data?.readableBytes.description  ?? "none"
    }

    app.get("json") { req -> [String: String] in
        return ["foo": "bar"]
    }.description("returns some test json")
    
    app.webSocket("ws") { req, ws in
        ws.onText { ws, text in
            ws.send(text.reversed())
            if text == "close" {
                ws.close(promise: nil)
            }
        }

        let ip = req.remoteAddress?.description ?? "<no ip>"
        ws.send("Hello 👋 \(ip)")
    }
    
    app.on(.POST, "file", body: .stream) { req -> EventLoopFuture<String> in
        let promise = req.eventLoop.makePromise(of: String.self)
        req.body.drain { result in
            switch result {
            case .buffer(let buffer):
                debugPrint(buffer)
            case .error(let error):
                promise.fail(error)
            case .end:
                promise.succeed("Done")
            }
            return req.eventLoop.makeSucceededFuture(())
        }
        return promise.futureResult
    }

    app.get("shutdown") { req -> HTTPStatus in
        guard let running = req.application.running else {
            throw Abort(.internalServerError)
        }
        running.stop()
        return .ok
    }

    let cache = MemoryCache()
    app.get("cache", "get", ":key") { req -> String in
        guard let key = req.parameters.get("key") else {
            throw Abort(.internalServerError)
        }
        return "\(key) = \(cache.get(key) ?? "nil")"
    }
    app.get("cache", "set", ":key", ":value") { req -> String in
        guard let key = req.parameters.get("key") else {
            throw Abort(.internalServerError)
        }
        guard let value = req.parameters.get("value") else {
            throw Abort(.internalServerError)
        }
        cache.set(key, to: value)
        return "\(key) = \(value)"
    }

    app.get("hello", ":name") { req in
        return req.parameters.get("name") ?? "<nil>"
    }

    app.get("search") { req in
        return req.query["q"] ?? "none"
    }

    let sessions = app.grouped("sessions")
        .grouped(app.sessions.middleware)
    sessions.get("set", ":value") { req -> HTTPStatus in
        req.session.data["name"] = req.parameters.get("value")
        return .ok
    }
    sessions.get("get") { req -> String in
        req.session.data["name"] ?? "n/a"
    }
    sessions.get("del") { req -> String in
        req.session.destroy()
        return "done"
    }

    app.get("client") { req in
        return req.client.get("http://httpbin.org/status/201").map { $0.description }
    }

    app.get("client-json") { req -> EventLoopFuture<String> in
        struct HTTPBinResponse: Decodable {
            struct Slideshow: Decodable {
                var title: String
            }
            var slideshow: Slideshow
        }
        return req.client.get("http://httpbin.org/json")
            .flatMapThrowing { try $0.content.decode(HTTPBinResponse.self) }
            .map { $0.slideshow.title }
    }
    
    let users = app.grouped("users")
    users.get { req in
        return "users"
    }
    users.get(":userID") { req in
        return req.parameters.get("userID") ?? "no id"
    }
    
    app.directory.viewsDirectory = "/Users/tanner/Desktop"
    app.get("view") { req in
        req.view.render("hello.txt", ["name": "world"])
    }

    app.get("error") { req -> String in
        throw TestError()
    }

    app.get("secret") { (req) -> EventLoopFuture<String> in
        return Environment
            .secret(key: "PASSWORD_SECRET", fileIO: req.application.fileio, on: req.eventLoop)
            .unwrap(or: Abort(.badRequest))
    }

    app.on(.POST, "max-256", body: .collect(maxSize: 256)) { req -> HTTPStatus in
        print("in route")
        return .ok
    }

    app.on(.POST, "upload", body: .stream) { req -> EventLoopFuture<HTTPStatus> in
        enum BodyStreamWritingToDiskError: Error {
            case streamFailure(Error)
            case fileHandleClosedFailure(Error)
            case multipleFailures([BodyStreamWritingToDiskError])
        }
        return req.application.fileio.openFile(
            path: "/Users/tanner/Desktop/foo.txt",
            mode: .write,
            flags: .allowFileCreation(),
            eventLoop: req.eventLoop
        ).flatMap { fileHandle in
            let promise = req.eventLoop.makePromise(of: HTTPStatus.self)
            req.body.drain { part in
                switch part {
                case .buffer(let buffer):
                    return req.application.fileio.write(
                        fileHandle: fileHandle,
                        buffer: buffer,
                        eventLoop: req.eventLoop
                    )
                case .error(let drainError):
                    do {
                        try fileHandle.close()
                        promise.fail(BodyStreamWritingToDiskError.streamFailure(drainError))
                    } catch {
                        promise.fail(BodyStreamWritingToDiskError.multipleFailures([
                            .fileHandleClosedFailure(error),
                            .streamFailure(drainError)
                        ]))
                    }
                    return req.eventLoop.makeSucceededFuture(())
                case .end:
                    do {
                        try fileHandle.close()
                        promise.succeed(.ok)
                    } catch {
                        promise.fail(BodyStreamWritingToDiskError.fileHandleClosedFailure(error))
                    }
                    return req.eventLoop.makeSucceededFuture(())
                }
            }
            return promise.futureResult
        }
    }

    #if compiler(>=5.5) && canImport(_Concurrency)
    if #available(macOS 12, *) {
        let asyncRoutes = app.grouped("async").grouped(TestAsyncMiddleware(number: 1))
        asyncRoutes.get("client") { req async throws -> String in
            let response = try await req.client.get("https://www.google.com")
            guard let body = response.body else {
                throw Abort(.internalServerError)
            }
            return String(buffer: body)
        }

        func asyncRouteTester(_ req: Request) async throws -> String {
            let response = try await req.client.get("https://www.google.com")
            guard let body = response.body else {
                throw Abort(.internalServerError)
            }
            return String(buffer: body)
        }
        asyncRoutes.get("client2", use: asyncRouteTester)
        
        asyncRoutes.get("content", use: asyncContentTester)
        
        func asyncContentTester(_ req: Request) async throws -> Creds {
            return Creds(email: "name", password: "password")
        }
        
        asyncRoutes.get("content2") { req async throws -> Creds in
            return Creds(email: "name", password: "password")
        }
        
        asyncRoutes.get("contentArray") { req async throws -> [Creds] in
            let cred1 = Creds(email: "name", password: "password")
            return [cred1]
        }
        
        func opaqueRouteTester(_ req: Request) async throws -> some AsyncResponseEncodable {
            "Hello World"
        }
        asyncRoutes.get("opaque", use: opaqueRouteTester)
        
        // Make sure jumping between multiple different types of middleware works
        asyncRoutes.grouped(TestAsyncMiddleware(number: 2), TestMiddleware(number: 3), TestAsyncMiddleware(number: 4), TestMiddleware(number: 5)).get("middleware") { req async throws -> String in
            return "OK"
        }
        
        let basicAuthRoutes = asyncRoutes.grouped(Test.authenticator(), Test.guardMiddleware())
        basicAuthRoutes.get("auth") { req async throws -> String in
            return try req.auth.require(Test.self).name
        }
    }
    
    @available(macOS 10.15, iOS 15, watchOS 8, tvOS 15, *)
    struct Test: Authenticatable {
        static func authenticator() -> AsyncAuthenticator {
            TestAuthenticator()
        }

        var name: String
    }

    @available(macOS 10.15, iOS 15, watchOS 8, tvOS 15, *)
    struct TestAuthenticator: AsyncBasicAuthenticator {
        typealias User = Test

        func authenticate(basic: BasicAuthorization, for request: Request) async throws {
            if basic.username == "test" && basic.password == "secret" {
                let test = Test(name: "Vapor")
                request.auth.login(test)
            }
        }
    }
    #endif
}

struct TestError: AbortError, DebuggableError {
    var status: HTTPResponseStatus {
        .internalServerError
    }

    var reason: String {
        "This is a test."
    }

    var source: ErrorSource?
    var stackTrace: StackTrace?

    init(
        file: String = #file,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column,
        range: Range<UInt>? = nil,
        stackTrace: StackTrace? = .capture(skip: 1)
    ) {
        self.source = .init(
            file: file,
            function: function,
            line: line,
            column: column,
            range: range
        )
        self.stackTrace = stackTrace
    }
}

#if compiler(>=5.5) && canImport(_Concurrency)
@available(macOS 10.15, iOS 15, watchOS 8, tvOS 15, *)
struct TestAsyncMiddleware: AsyncMiddleware {
    let number: Int
    
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        request.logger.debug("In async middleware - \(number)")
        let response = try await next.respond(to: request)
        request.logger.debug("In async middleware way out - \(number)")
        return response
    }
}
#endif

struct TestMiddleware: Middleware {
    let number: Int
    
    func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
        request.logger.debug("In non-async middleware - \(number)")
        return next.respond(to: request).map { response in
            request.logger.debug("In non-async middleware way out - \(self.number)")
            return response
        }
    }
}
