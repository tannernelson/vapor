import NIOCore

/// A type erased response useful for routes that can return more than one type.
///
///     app.get("foo") { req -> AnyResponse in
///         if /* something */ {
///             return AnyResponse(42)
///         } else {
///             return AnyResponse("string")
///         }
///     }
///
/// This can also be done using a `ResponseEncodable` enum.
///
///     enum IntOrString: ResponseEncodable {
///         case int(Int)
///         case string(String)
///
///         func encode(for req: Request) async throws -> Response {
///             switch self {
///             case .int(let i): return try await i.encode(for: req)
///             case .string(let s): return try await s.encode(for: req)
///             }
///         }
///     }
///
///     app.get("foo") { req -> IntOrString in
///         if /* something */ {
///             return .int(42)
///         } else {
///             return .string("string")
///         }
///     }
///
public struct AnyResponse: ResponseEncodable {
    /// The wrapped `ResponseEncodable` type.
    private let encodable: ResponseEncodable

    /// Creates a new `AnyResponse`.
    ///
    /// - parameters:
    ///     - encodable: Something `ResponseEncodable`.
    public init(_ encodable: ResponseEncodable) {
        self.encodable = encodable
    }

    public func encodeResponse(for request: Request) async throws -> Response {
        return try await self.encodable.encodeResponse(for: request)
    }
}
