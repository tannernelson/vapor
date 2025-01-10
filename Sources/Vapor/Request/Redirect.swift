extension Request {    
    /// Creates a redirect `Response`.
    ///
    ///     router.get("redirect") { req in
    ///         return req.redirect(to: "https://vapor.codes")
    ///     }
    ///
    /// Set type to '.permanently' to allow caching to automatically redirect from browsers.
    /// Defaulting to non-permanent to prevent unexpected caching.
    /// - Parameters:
    ///   - location: The path to redirect to
    ///   - redirectType: The type of redirect to perform
    /// - Returns: A response that redirects the client to the specified location
    public func redirect(to location: String, redirectType: RedirectType = .normal) -> Response {
        let response = Response()
        response.responseBox.withLockedValue { box in
            box.status = redirectType.status
            box.headers.replaceOrAdd(name: .location, value: location)
        }
        return response
    }
}

/// Specifies the type of redirect that the client should receive.
public struct RedirectType {
    let kind: Kind
    
    /// A cacheable redirect. Not all user-agents preserve request method and body, so
    /// this should only be used for GET or HEAD requests
    /// `301 permanent`
    public static var permanent: RedirectType {
        return Self(kind: .permanent)
    }
    
    /// Forces the redirect to come with a GET, regardless of req method.
    /// `303 see other`
    public static var normal: RedirectType {
        return Self(kind: .normal)
    }
    
    /// Maintains original request method, ie: PUT will call PUT on redirect.
    /// `307 Temporary`
    public static var temporary: RedirectType {
        return Self(kind: .temporary)
    }
    
    /// Redirect where the request method and the body will not be altered. This should
    /// be used for POST redirects.
    /// `308 Permanent Redirect`
    public static var permanentPost: RedirectType {
        return Self(kind: .permanentPost)
    }

    /// Associated `HTTPStatus` for this redirect type.
    public var status: HTTPStatus {
        switch self.kind {
        case .permanent: return .movedPermanently
        case .normal: return .seeOther
        case .temporary: return .temporaryRedirect
        case .permanentPost: return .permanentRedirect
        }
    }
    
    enum Kind {
        case permanent
        case normal
        case temporary
        case permanentPost
    }
}
