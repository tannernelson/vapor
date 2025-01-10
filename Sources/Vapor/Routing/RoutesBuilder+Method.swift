import RoutingKit
import NIOHTTP1

/// Determines how an incoming HTTP request's body is collected.
public enum HTTPBodyStreamStrategy: Sendable {
    /// The HTTP request's body will be collected into memory up to a maximum size
    /// before the route handler is called. The application's configured default max body
    /// size will be used unless otherwise specified.
    ///
    /// See `collect(maxSize:)` to specify a custom max collection size.
    public static var collect: HTTPBodyStreamStrategy {
        return .collect(maxSize: nil)
    }

    /// The HTTP request's body will not be collected first before the route handler is called
    /// and will arrive in zero or more chunks.
    case stream

    /// The HTTP request's body will be collected into memory before the route handler is
    /// called.
    ///
    /// `maxSize` Limits the maximum amount of memory in bytes that will be used to
    /// collect a streaming body. Streaming requests exceeding that size will result in an error.
    /// Passing `nil` results in the application's default max body size being used. This
    /// parameter does not affect non-streaming requests.
    case collect(maxSize: ByteCount?)
}

extension RoutesBuilder {
    @discardableResult
    public func get<Response>(
        _ path: PathComponent...,
        use closure: @Sendable @escaping (Request) async throws -> Response
    ) -> Route
    where Response: ResponseEncodable
    {
        return self.on(.GET, path, use: closure)
    }
    
    @discardableResult
    public func get<Response>(
        _ path: [PathComponent],
        use closure: @Sendable @escaping (Request) async throws -> Response
    ) -> Route
    where Response: ResponseEncodable
    {
        return self.on(.GET, path, use: closure)
    }
    
    @discardableResult
    public func post<Response>(
        _ path: PathComponent...,
        use closure: @Sendable @escaping (Request) async throws -> Response
    ) -> Route
    where Response: ResponseEncodable
    {
        return self.on(.POST, path, use: closure)
    }
    
    @discardableResult
    public func post<Response>(
        _ path: [PathComponent],
        use closure: @Sendable @escaping (Request) async throws -> Response
    ) -> Route
    where Response: ResponseEncodable
    {
        return self.on(.POST, path, use: closure)
    }
    
    @discardableResult
    public func patch<Response>(
        _ path: PathComponent...,
        use closure: @Sendable @escaping (Request) async throws -> Response
    ) -> Route
    where Response: ResponseEncodable
    {
        return self.on(.PATCH, path, use: closure)
    }
    
    @discardableResult
    public func patch<Response>(
        _ path: [PathComponent],
        use closure: @Sendable @escaping (Request) async throws -> Response
    ) -> Route
    where Response: ResponseEncodable
    {
        return self.on(.PATCH, path, use: closure)
    }
    
    @discardableResult
    public func put<Response>(
        _ path: PathComponent...,
        use closure: @Sendable @escaping (Request) async throws -> Response
    ) -> Route
    where Response: ResponseEncodable
    {
        return self.on(.PUT, path, use: closure)
    }
    
    @discardableResult
    public func put<Response>(
        _ path: [PathComponent],
        use closure: @Sendable @escaping (Request) async throws -> Response
    ) -> Route
    where Response: ResponseEncodable
    {
        return self.on(.PUT, path, use: closure)
    }
    
    @discardableResult
    public func delete<Response>(
        _ path: PathComponent...,
        use closure: @Sendable @escaping (Request) async throws -> Response
    ) -> Route
    where Response: ResponseEncodable
    {
        return self.on(.DELETE, path, use: closure)
    }
    
    @discardableResult
    public func delete<Response>(
        _ path: [PathComponent],
        use closure: @Sendable @escaping (Request) async throws -> Response
    ) -> Route
    where Response: ResponseEncodable
    {
        return self.on(.DELETE, path, use: closure)
    }
    
    @discardableResult
    public func on<Response>(
        _ method: HTTPMethod,
        _ path: PathComponent...,
        body: HTTPBodyStreamStrategy = .collect,
        use closure: @Sendable @escaping (Request) async throws -> Response
    ) -> Route
    where Response: ResponseEncodable
    {
        return self.on(method, path, body: body, use: { request in
            return try await closure(request)
        })
    }
    
    @discardableResult
    public func on<Response>(
        _ method: HTTPMethod,
        _ path: [PathComponent],
        body: HTTPBodyStreamStrategy = .collect,
        use closure: @Sendable @escaping (Request) async throws -> Response
    ) -> Route
    where Response: ResponseEncodable
    {
        let responder = BasicResponder { request in
            if case .collect(let max) = body, request.body.data == nil {
                _ = try await request.eventLoop.flatSubmit {
                    request.body.collect(max: max?.value ?? request.application.routes.defaultMaxBodySize.value)
                }.get()
                
            }
            return try await closure(request).encodeResponse(for: request)
        }
        let route = Route(
            method: method,
            path: path,
            responder: responder,
            requestType: Request.self,
            responseType: Response.self
        )
        self.add(route)
        return route
    }
}
