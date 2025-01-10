import NIOHTTP1

/// Overrides the response compression settings for a route.
///
/// This is useful when a set of static routes does not need compression, or a set of dynamic routes does.
///
/// When the ``HTTPServer/Configuration-swift.struct/ResponseCompressionConfiguration`` is set to be disabled by default, ``HTTPHeaders/ResponseCompression/enable`` can be set to explicitly enable compression. Likewise, when the configuration is set to be enabled by default, ``HTTPHeaders/ResponseCompression/disable`` can be set to explicitly disable compression.
///
/// To ignore a preference a downstream middleware (ie. closer to the root route than to the original response) may propose in favor of the server defaults, use ``HTTPHeaders/ResponseCompression/useDefault``.
///
/// - Note: Response compression is only actually used if the client indicates it supports it via an `Accept` header.
public struct ResponseCompressionMiddleware: Middleware {
    /// The response compression override to use over the base configuration.
    ///
    /// Overrides are only used when the server's ``HTTPServer/Configuration-swift.struct/ResponseCompressionConfiguration/allowRequestOverrides`` property is enabled, otherwise they are ignored.
    ///
    /// To clear an override set previously in the chain (ie. closer to the root route than to the original response), set ``HTTPHeaders/ResponseCompression/useDefault``.
    ///
    /// - Note: Middleware that come after this one, or responses with a ``HTTPHeaders/ResponseCompression`` header, will take priority over the override set here, unless ``shouldForce`` is set to true.
    public var responseCompressionOverride: HTTPHeaders.ResponseCompression
    
    /// A flag to force the override atop whatever the response or output of middleware that process the response before this one.
    public var shouldForce: Bool
    
    /// Initialize a response compression middleware with an override.
    /// 
    /// - Parameters:
    ///   - override: The compression preference to apply if none is already set.
    ///   - shouldForce: Wether to force the compression preference over what the response prefers.
    ///
    /// - SeeAlso: Please see ``responseCompressionOverride`` for more details.
    public init(override: HTTPHeaders.ResponseCompression, force shouldForce: Bool = false) {
        self.responseCompressionOverride = override
        self.shouldForce = shouldForce
    }
    
    public func respond(to request: Request, chainingTo next: any Responder) async throws -> Response {
        let response = try await next.respond(to: request)
        /// Only set the header if it is unset, and prefer the next responder's header over our own override, as _it_ is overriding ours.
        if response.headers.responseCompression == .unset || shouldForce {
            response.headers.responseCompression = responseCompressionOverride
        }
        return response
    }
}

extension RoutesBuilder {
    /// Override the response compression settings for a route.
    /// 
    /// This is useful when a set of static routes does not need compression, or a set of dynamic routes does.
    /// 
    /// When the ``HTTPServer/Configuration-swift.struct/ResponseCompressionConfiguration`` is set to be disabled by default, ``HTTPHeaders/ResponseCompression/enable`` can be set to explicitly enable compression. Likewise, when the configuration is set to be enabled by default, ``HTTPHeaders/ResponseCompression/disable`` can be set to explicitly disable compression.
    ///
    /// To ignore a preference a downstream middleware (ie. closer to the root route than to the original response) may propose in favor of the server defaults, use ``HTTPHeaders/ResponseCompression/useDefault``.
    ///
    /// - Note: Response compression is only actually used if the client indicates it supports it via an `Accept` header.
    /// - Note: Setting the override to ``HTTPHeaders/ResponseCompression/unset`` has no effect here unless `force` is set to true.
    ///
    /// - Parameters:
    ///   - override: The compression preference to apply if none is already set.
    ///   - shouldForce: Wether to force the compression preference over what the response prefers.
    /// - Returns: A route with the specified response compression preferences.
    public func responseCompression(_ override: HTTPHeaders.ResponseCompression, force shouldForce: Bool = false) -> RoutesBuilder {
        self.grouped(ResponseCompressionMiddleware(override: override, force: shouldForce))
    }
}
