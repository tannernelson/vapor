import Tracing

/// Creates a trace and metadata for every request
///
/// See https://opentelemetry.io/docs/specs/semconv/http/http-spans/
public final class TracingMiddleware: AsyncMiddleware {
    private let setCustomAttributes: @Sendable (inout SpanAttributes, Request) -> Void
    
    /// Create a TracingMiddleware
    public init() {
        self.setCustomAttributes = { _, _ in }
    }
    
    /// Create a TracingMiddleware
    /// - Parameter setCustomAttributes: Closure that allows setting custom span attributes for a particular request. A custom span attribute could be extracted from a request
    /// header, for example. This closure is called during span creation on every request, so should be lightweight.
    public init(
        setCustomAttributes: @escaping @Sendable (inout SpanAttributes, Request) -> Void
    ) {
        self.setCustomAttributes = setCustomAttributes
    }
    
    public func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        var parentContext = request.serviceContext
        InstrumentationSystem.instrument.extract(request.headers, into: &parentContext, using: HTTPHeadersExtractor())
        
        return try await withSpan(
            // Name: https://opentelemetry.io/docs/specs/semconv/http/http-spans/#name
            request.route?.description ?? "vapor_route_undefined",
            context: parentContext,
            ofKind: .server
        ) { span in
            // Set the request.serviceContext for the duration of this middleware & then reset it to parent
            // Using this pattern in `withSpan` allows spans to nest across sequential future chains
            request.serviceContext = span.context
            defer {
                request.serviceContext = parentContext
            }
            
            // Attributes: https://opentelemetry.io/docs/specs/semconv/http/http-spans/#http-server-semantic-conventions
            span.updateAttributes { attributes in
                // Required
                attributes["http.request.method"] = request.method.rawValue
                attributes["url.path"] = request.url.path
                attributes["url.scheme"] = request.url.scheme
                
                // Conditionally required
                if let route = request.route {
                    attributes["http.route"] = "/" + route.path.map { "\($0)" }.joined(separator: "/")
                }
                
                attributes["network.protocol.name"] = "http"
                switch request.application.http.server.configuration.address {
                    case let .hostname(address, port):
                        attributes["server.address"] = address
                        attributes["server.port"] = port
                    case let .unixDomainSocket(path):
                        attributes["server.address"] = path
                }
                attributes["url.query"] = request.url.query
                
                // Recommended
                attributes["client.address"] = request.peerAddress?.ipAddress
                attributes["network.peer.address"] = request.remoteAddress?.ipAddress
                attributes["network.peer.port"] = request.remoteAddress?.port
                attributes["network.protocol.version"] = "\(request.version.major).\(request.version.minor)"
                attributes["user_agent.original"] = request.headers[.userAgent].first
                
                // Custom defined
                setCustomAttributes(&attributes, request)
            }
            let response = try await next.respond(to: request)
            
            span.updateAttributes { attributes in
                // Conditionally required
                attributes["http.response.status_code"] = Int(response.status.code)
            }
            
            // Status: https://opentelemetry.io/docs/specs/semconv/http/http-spans/#status
            if 500 <= response.status.code && response.status.code < 600 {
                span.setStatus(.init(code: .error))
            }
            
            return response
        }
    }
}

// Allows backends to extract information from the request headers. For example, in OTel W3C, this allows frontend/backend
// correlation using the `traceparent` and `tracestate` headers. For more information, see
// https://swiftpackageindex.com/apple/swift-distributed-tracing/main/documentation/tracing/instrumentyourlibrary#Handling-inbound-requests
private struct HTTPHeadersExtractor: Extractor {
    func extract(key name: String, from headers: HTTPHeaders) -> String? {
        let headerValue = headers[name]
        if headerValue.isEmpty {
            return nil
        } else {
            return headerValue.joined(separator: ";")
        }
    }
}
