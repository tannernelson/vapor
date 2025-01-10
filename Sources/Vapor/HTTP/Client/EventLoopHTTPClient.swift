import NIOCore
import AsyncHTTPClient
import Logging
import Foundation

extension HTTPClient {
    func delegating(to eventLoop: EventLoop, logger: Logger, byteBufferAllocator: ByteBufferAllocator) -> Client {
        EventLoopHTTPClient(
            http: self,
            eventLoop: eventLoop,
            logger: logger,
            byteBufferAllocator: byteBufferAllocator
        )
    }
}

private struct EventLoopHTTPClient: Client {
    let http: HTTPClient
    let eventLoop: EventLoop
    var logger: Logger?
    var byteBufferAllocator: ByteBufferAllocator

    func send(
        _ client: ClientRequest
    ) async throws -> ClientResponse {
        let urlString = client.url.string
        guard let url = URL(string: urlString) else {
            self.logger?.debug("\(urlString) is an invalid URL")
            throw Abort(.internalServerError, reason: "\(urlString) is an invalid URL")
        }
        let request = try HTTPClient.Request(
            url: url,
            method: client.method,
            headers: client.headers,
            body: client.body.map { .byteBuffer($0) }
        )
        return try await self.http.execute(
            request: request,
            eventLoop: .delegate(on: self.eventLoop),
            deadline: client.timeout.map { .now() + $0 },
            logger: logger
        ).map { response in
            let client = ClientResponse(
                status: response.status,
                headers: response.headers,
                body: response.body,
                byteBufferAllocator: self.byteBufferAllocator
            )
            return client
        }.get()
    }

    func delegating(to eventLoop: EventLoop) -> Client {
        EventLoopHTTPClient(http: self.http, eventLoop: eventLoop, logger: self.logger, byteBufferAllocator: self.byteBufferAllocator)
    }

    func logging(to logger: Logger) -> Client {
        return EventLoopHTTPClient(http: self.http, eventLoop: self.eventLoop, logger: logger, byteBufferAllocator: self.byteBufferAllocator)
    }

    func allocating(to byteBufferAllocator: ByteBufferAllocator) -> Client {
        return EventLoopHTTPClient(http: self.http, eventLoop: self.eventLoop, logger: self.logger, byteBufferAllocator: byteBufferAllocator)
    }
}
