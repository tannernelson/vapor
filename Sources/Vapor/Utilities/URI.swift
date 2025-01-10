import Foundation

// MARK: - URI

/// A type for constructing and manipulating (most) Uniform Resource Indicators.
///
/// > Warning: This is **NOT** the same as Foundation's [`URL`] type!
///
/// Can be used to both parse strings containing well-formed URIs and to generate such strings from
/// a set of individual URI components.
///
/// Use of this type is (gently, for now) discouraged. Consider using Foundation's [`URL`] and/or
/// [`URLComponents`] types instead. See below for details.
///
/// ## URI is for URLs, not URIs
///
/// Thanks to both backwards compatibility requirements and name collision concerns, this type, despite
/// its name, does not actually represent a generic Uniform Resource Identifier as defined by [RFC 3986].
/// In particular, the underlying implementation is currently based on Foundation's [`URLComponents`] type,
/// whose semantics are inconsistent between different methods; in addition, its behavior has differed
/// drastically between the macOS and Linux implementations for most of its existence, and continues to do
/// so in Swift 5.9. This is not expected to be remedied until the [`swift-foundation`] package reaches a
/// 1.0 release, which as of this writing will not for quite some time yet). In short, instances of `URI`
/// may not always behave as expected according to either the spec or what Foundation does.
///
/// [RFC 3986]: https://datatracker.ietf.org/doc/html/rfc3986
/// [`swift-foundation`]: https://github.com/apple/swift-foundation
/// [`URL`]: https://developer.apple.com/documentation/foundation/url
/// [`URLComponents`]: https://developer.apple.com/documentation/foundation/urlcomponents
public struct URI: CustomStringConvertible, ExpressibleByStringInterpolation, Hashable, Codable, Sendable {
    private var components: URLComponents?
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        
        self.init(string: string)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.string)
    }
    
    /// Create a ``URI`` by parsing a given string according to the semantics of [RFC 3986].
    ///
    /// [RFC 3986]: https://datatracker.ietf.org/doc/html/rfc3986
    public init(string: String = "/") {
        self.components = URL(string: string).flatMap { .init(url: $0, resolvingAgainstBaseURL: true) }
    }

    public init(
        scheme: String?,
        userinfo: String?,
        host: String? = nil,
        port: Int? = nil,
        path: String,
        query: String? = nil,
        fragment: String? = nil
    ) {
        self.init(
            scheme: Scheme(scheme),
            userinfo: userinfo,
            host: host,
            port: port,
            path: path,
            query: query,
            fragment: fragment
        )
    }

    public init(scheme: String?, host: String? = nil, port: Int? = nil, path: String, query: String? = nil, fragment: String? = nil) {
        self.init(scheme: scheme, userinfo: nil, host: host, port: port, path: path, query: query, fragment: fragment)
    }
    
    public init(scheme: Scheme = .init(), host: String? = nil, port: Int? = nil, path: String, query: String? = nil, fragment: String? = nil) {
        self.init(scheme: scheme, userinfo: nil, host: host, port: port, path: path, query: query, fragment: fragment)
    }
    
    /// Construct a ``URI`` from various subcomponents.
    ///
    /// Percent encoding is added to each component (if necessary) automatically. There is currently no
    /// way to change this behavior; use `URLComponents` instead if this is insufficient.
    ///
    /// > Important: For backwards compatibility reasons, if the `path` component is specified in isolation
    /// > (e.g. all other components are `nil`), the path is parsed as if by the ``init(string:)`` initializer,
    /// > _EXCEPT_ that if the path begins with `//`, it will be treated as beginning with `/` instead, thus
    /// > parsing the first path component as part of the path rather than as a host component. These semantics
    /// > are suitable for parsing URI-like strings which are known to lack an authority component, such as the
    /// > URI part of the first line of an HTTP request.
    /// >
    /// > In all cases, a `/` is prepended to the path if it does not begin with one, irrespective of whether or
    /// > not the path has been specified in isolation as described above.
    public init(
        scheme: Scheme = .init(),
        userinfo: String?,
        host: String? = nil,
        port: Int? = nil,
        path: String,
        query: String? = nil,
        fragment: String? = nil
    ) {
        let path = path.first == "/" ? path : "/\(path)"
        var components: URLComponents!
        
        if scheme.value == nil, userinfo == nil, host == nil, port == nil, query == nil, fragment == nil {
            // If only a path is given, treat it as a string to parse. (This behavior is awful, but must be kept for compatibility.)
            // In order to do this in a fully compatible way (where in this case "compatible" means "being stuck with
            // systematic misuse of both the URI type and concept"), we must collapse any non-zero number of
            // leading `/` characters into a single character (thus breaking the ability to parse what is otherwise a
            // valid URI format according to spec) to avoid weird routing misbehaviors.
            components = URL(string: "/\(path.drop(while: { $0 == "/" }))").flatMap { .init(url: $0, resolvingAgainstBaseURL: true) }
        } else {
            // N.B.: We perform percent encoding manually and unconditionally on each non-nil component because the
            // behavior of URLComponents is completely different on Linux than on macOS for inputs which are already
            // fully or partially percent-encoded, as well as inputs which contain invalid characters (especially
            // for the host component). This is the only way to provide consistent behavior (and to avoid various
            // fatalError()s in URLComponents on Linux).
            components = .init()
            components.scheme = scheme.value?.addingPercentEncoding(withAllowedCharacters: .urlSchemeAllowed)
            if let host {
                if let creds = userinfo?.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false), !creds[0].isEmpty {
                    components.percentEncodedUser = creds[0].addingPercentEncoding(withAllowedCharacters: .urlUserAllowed)
                    if creds.count > 1, !creds[1].isEmpty {
                        components.percentEncodedPassword = creds[1].addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed)
                    }
                }
                components.encodedHost = host.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
                components.port = port
            } else {
                // TODO: Should this be enforced?
                // assert(userinfo == nil, "Can't provide userinfo without an authority (hostname)")
                // assert(port == nil, "Can't provide userinfo without an authority (hostname)")
            }
            components.percentEncodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlCorrectPathAllowed) ?? "/"
            components.percentEncodedQuery = query?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            components.percentEncodedFragment = fragment?.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
        }
        self.components = components
    }

    public var scheme: String? {
        get { self.components?.scheme }
        set { self.components?.scheme = newValue }
    }
    
    public var userinfo: String? {
        get { self.components?.percentEncodedUser.map { "\($0)\(self.components?.percentEncodedPassword.map { ":\($0)" } ?? "")" } }
        set {
            if let userinfoData = newValue?.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false) {
                self.components?.percentEncodedUser = .init(userinfoData[0])
                self.components?.percentEncodedPassword = userinfoData.count > 1 ? .init(userinfoData[1]) : nil
            } else {
                self.components?.percentEncodedUser = nil
            }
        }
    }

    public var host: String? {
        get { self.components?.percentEncodedHost }
        set { self.components?.percentEncodedHost = newValue }
    }

    public var port: Int? {
        get { self.components?.port }
        set { self.components?.port = newValue }
    }

    public var path: String {
        get { self.components?.percentEncodedPath.replacingOccurrences(of: "%3B", with: ";", options: .literal) ?? "/" }
        set { self.components?.percentEncodedPath = newValue.withAllowedUrlDelimitersEncoded }
    }

    public var query: String? {
        get { self.components?.percentEncodedQuery }
        set { self.components?.percentEncodedQuery = newValue?.withAllowedUrlDelimitersEncoded }
    }

    public var fragment: String? {
        get { self.components?.percentEncodedFragment }
        set { self.components?.percentEncodedFragment = newValue?.withAllowedUrlDelimitersEncoded }
    }

    public var string: String {
        if urlPathAllowedIsBroken {
            // On Linux and in older Xcode versions, URLComponents incorrectly treats `;` as *not* allowed in the path component.
            let string = self.components?.string ?? ""
            return string.replacingOccurrences(
                of: "%3B", with: ";",
                options: .literal, // N.B.: `rangeOfPath` never actually returns `nil`
                range: self.components?.rangeOfPath ?? (string.startIndex..<string.startIndex)
            )
        } else {
            return self.components?.string ?? ""
        }
    }
    
    // See `ExpressibleByStringInterpolation.init(stringLiteral:)`.
    public init(stringLiteral value: String) {
        self.init(string: value)
    }

    // See `CustomStringConvertible.description`.
    public var description: String {
        self.string
    }
}

// MARK: - URI.Scheme

extension URI {
    /// A URI scheme, as defined by [RFC 3986 § 3.1] and [RFC 7595].
    ///
    /// [RFC 3986 § 3.1]: https://datatracker.ietf.org/doc/html/rfc3986#section-3.1
    /// [RGC 7595]: https://datatracker.ietf.org/doc/html/rfc7595
    public struct Scheme: CustomStringConvertible, ExpressibleByStringInterpolation, Hashable, Codable, Sendable {
        /// The string representation of the scheme.
        public let value: String?
        
        /// Designated initializer.
        ///
        /// - Parameter value: The string representation for the desired scheme.
        public init(_ value: String? = nil) { self.value = value }

        // MARK: - "Well-known" schemes
        
        /// HyperText Transfer Protocol (HTTP)
        ///
        /// > Registration: [RFC 9110 § 4.2.1](https://www.rfc-editor.org/rfc/rfc9110.html#section-4.2.1)
        public static let http: Self = "http"
        
        /// Secure HyperText Transfer Protocol (HTTPS)
        ///
        /// > Registration: [RFC 9110 § 4.2.2](https://www.rfc-editor.org/rfc/rfc9110.html#section-4.2.2)
        public static let https: Self = "https"
        
        /// HyperText Transfer Protocol (HTTP) over Unix Domain Sockets.
        ///
        /// The socket path must be given as the URI's "host" component, appropriately percent-encoded. The
        /// ``URI/init(scheme:userinfo:host:port:path:query:fragment:)`` initializer adds such encoding
        /// automatically. To manually apply the correct encoding, use:
        ///
        /// ```swift
        /// socketPath.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        /// ```
        /// 
        /// > Registration: None (non-standard)
        public static let httpUnixDomainSocket: Self = "http+unix"
        
        /// Secure HyperText Transfer Protocol (HTTPS) over Unix Domain Sockets.
        ///
        /// The socket path must be given as the URI's "host" component, appropriately percent-encoded. The
        /// ``URI/init(scheme:userinfo:host:port:path:query:fragment:)`` initializer adds such encoding
        /// automatically. To manually apply the correct encoding, use:
        ///
        /// ```swift
        /// socketPath.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        /// ```
        ///
        /// > Note: The primary use case for this scheme is for local communication with servers (most
        /// > often database servers) which require TLS client certificate authentication. In most other
        /// > situations, the added encryption is unnecessary and will just slow things down.
        /// >
        /// > (Well, unless your security concerns include other processes spying on your server's
        /// > communications when using UNIX sockets. But since doing that would require having already
        /// > compromised the host kernel ("It rather involved being on the other side of this airtight
        /// > hatchway."), it seems fairly safe to say such a concern would be moot.)
        ///
        /// > Registration: None (non-standard)
        public static let httpsUnixDomainSocket: Self = "https+unix"
        
        // MARK: End of "well-known" schemes -

        // See `ExpressibleByStringInterpolation.init(stringLiteral:)`.
        public init(stringLiteral value: String) { self.init(value) }

        // See `CustomStringConvertible.description`.
        public var description: String { self.value ?? "" }
    }
}

// MARK: - Utilities

extension StringProtocol {
    /// Apply percent-encoding to any unencoded instances of `[` and `]` in the string
    ///
    /// The `[` and `]` characters are considered "general delimiters" by [RFC 3986 § 2.2], and thus
    /// part of the "reserved" set. As such, Foundation's URL handling logic rejects them if they
    /// appear unencoded when setting a "percent-encoded" component. However, in practice neither
    /// character presents any possible ambiguity in parsing unless it appears as part of the "authority"
    /// component, and they are often used unencoded in paths. They appear even more commonly as "array"
    /// syntax in query strings. As such, we need to sidestep Foundation's complaints by manually encoding
    /// them when they show up.
    ///
    /// > Note: Fortunately, we don't have to perform the corresponding decoding when going in the other
    /// > direction, as it will be taken care of by standard percent encoding logic. If this were not the
    /// > case, doing this with 100% correctness would require a nontrivial amount of shadow state tracking.
    ///
    /// [RFC 3986 § 2.2]: https://datatracker.ietf.org/doc/html/rfc3986#section-2.2
    fileprivate var withAllowedUrlDelimitersEncoded: String {
        self.replacingOccurrences(of: "[", with: "%5B", options: .literal)
            .replacingOccurrences(of: "]", with: "%5D", options: .literal)
    }
}

extension CharacterSet {
    /// The set of characters allowed in a URI scheme, as per [RFC 3986 § 3.1].
    ///
    /// [RFC 3986 § 3.1]: https://datatracker.ietf.org/doc/html/rfc3986#section-3.1
    fileprivate static var urlSchemeAllowed: Self {
        // Intersect the alphanumeric set plus additional characters with the host-allowed set to ensure
        // we get only ASCII codepoints in the result.
        .urlHostAllowed.intersection(.alphanumerics.union(.init(charactersIn: "+-.")))
    }
    
    /// The set of characters allowed in a URI path, as per [RFC 3986 § 3.3].
    ///
    /// > Note: This is identical to the built-in `urlPathAllowed` on macOS; on Linux it adds the missing
    /// > semicolon character to the set.
    ///
    /// [RFC 3986 § 3.3]: https://datatracker.ietf.org/doc/html/rfc3986#section-3.3
    fileprivate static var urlCorrectPathAllowed: Self {
        .urlPathAllowed.union(.init(charactersIn: ";"))
    }
}

/// On Linux and in older Xcode versions, URLComponents incorrectly treats `;` as *not* allowed in the path component.
private let urlPathAllowedIsBroken: Bool = {
    CharacterSet.urlPathAllowed != CharacterSet.urlCorrectPathAllowed
}()
