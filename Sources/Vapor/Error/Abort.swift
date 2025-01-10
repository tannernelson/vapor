import NIOHTTP1

/// Default implementation of `AbortError`. You can use this as a convenient method for throwing
/// `AbortError`s without having to conform your own error-type to `AbortError`.
///
///     throw Abort(.badRequest, reason: "Something's not quite right...")
///
public struct Abort: AbortError, DebuggableError {    
    /// Creates a redirecting `Abort` error.
    ///
    ///     throw Abort.redirect(to: "https://vapor.codes")
    ///
    /// Set type to '.permanently' to allow caching to automatically redirect from browsers.
    /// Defaulting to non-permanent to prevent unexpected caching.
    /// - Parameters:
    ///   - location: The path to redirect to
    ///   - redirectType: The type of redirect to perform
    /// - Returns: An abort error that provides a redirect to the specified location
    public static func redirect(to location: String, redirectType: RedirectType = .normal) -> Abort {
        var headers: HTTPHeaders = [:]
        headers.replaceOrAdd(name: .location, value: location)
        return .init(redirectType.status, headers: headers)
    }

    /// See `Debuggable`
    public var identifier: String

    /// See `AbortError`
    public var status: HTTPResponseStatus

    /// See `AbortError`.
    public var headers: HTTPHeaders

    /// See `AbortError`
    public var reason: String

    /// Source location where this error was created.
    public var source: ErrorSource?

    /// Create a new `Abort`, capturing current source location info.
    public init(
        _ status: HTTPResponseStatus,
        headers: HTTPHeaders = [:],
        reason: String? = nil,
        identifier: String? = nil,
        suggestedFixes: [String] = [],
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column,
        range: Range<UInt>? = nil
    ) {
        self.identifier = identifier ?? status.code.description
        self.headers = headers
        self.status = status
        self.reason = reason ?? status.reasonPhrase
        self.source = ErrorSource(
            file: file,
            function: function,
            line: line,
            column: column,
            range: range
        )
    }
}
