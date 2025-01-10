import NIOCore

public protocol Responder: Sendable {
    func respond(to request: Request) async throws -> Response
}
