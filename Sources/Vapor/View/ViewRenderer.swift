import NIOCore

public protocol ViewRenderer {
    func `for`(_ request: Request) -> ViewRenderer
    func render<E>(_ name: String, _ context: E) async throws -> View where E: Encodable
    func render(_ name: String) async throws -> View
}

extension ViewRenderer {
    public func render(_ name: String) async throws -> View {
        try await self.render(name, [String: String]())
    }
}
