import Vapor
import NIOCore

struct ResponderClient: Client {
    let responder: Responder
    let application: Application

    var eventLoop: EventLoop {
        self.application.eventLoopGroup.next()
    }

    func delegating(to eventLoop: EventLoop) -> Client {
        self
    }

    func send(_ request: ClientRequest) async throws -> ClientResponse {
        let response = try await self.responder.respond(to: .init(
            application: self.application,
            method: request.method,
            url: request.url,
            version: .init(major: 1, minor: 1),
            headersNoUpdate: request.headers,
            collectedBody: request.body,
            remoteAddress: nil,
            logger: application.logger,
            on: application.eventLoopGroup.next()
        ))
        return ClientResponse(status: response.status, headers: response.headers, body: response.body.buffer)
    }
}

extension Application.Clients.Provider {
    static var responder: Self {
        .init {
            $0.clients.use {
                ResponderClient(responder: $0.responder, application: $0)
            }
        }
    }
}
