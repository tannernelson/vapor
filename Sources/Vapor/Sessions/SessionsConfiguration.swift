import Foundation

/// Configuration options for sessions.
public struct SessionsConfiguration: Sendable {
    /// Creates a new `HTTPCookieValue` for the supplied value `String`.
    public var cookieFactory: @Sendable (SessionID) -> HTTPCookies.Value

    /// Name of HTTP cookie, used as a key for the cookie value.
    public var cookieName: String

    /// Create a new `SessionsConfig` with the supplied cookie factory.
    ///
    ///     let sessionsConfig = SessionsConfig(cookieName: "vapor-session") { value in
    ///         return HTTPCookieValue(string: value, isSecure: true)
    ///     }
    ///
    /// - parameters:
    ///     - cookieName: Name of HTTP cookie, used as a key for the cookie value.
    ///     - cookieFactory: Creates a new `HTTPCookieValue` for the supplied value `String`.
    public init(cookieName: String, cookieFactory: @Sendable @escaping (SessionID) -> HTTPCookies.Value) {
        self.cookieName = cookieName
        self.cookieFactory = cookieFactory
    }

    /// `SessionsConfig` with basic cookie factory.
    public static func `default`() -> SessionsConfiguration {
        return .init(cookieName: "vapor-session") { sessionID in
            return HTTPCookies.Value(
                string: sessionID.string,
                expires: Date(
                    timeIntervalSinceNow: 60 * 60 * 24 * 7 // one week
                ),
                maxAge: nil,
                domain: nil,
                path: "/",
                isSecure: false,
                isHTTPOnly: false,
                sameSite: .lax
            )
        }
    }
}
