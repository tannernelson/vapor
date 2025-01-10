import Foundation
import NIOHTTP1

// Comments on these properties are copied from the mozilla doc URL shown below.
extension HTTPHeaders {
    /// Represents the HTTP `Cache-Control` header.
    /// - See Also:
    /// [Cache-Control docs](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control)
    public struct CacheControl: Sendable {
        /// The max-stale option can be present with no value, or be present with a number of seconds.  By using
        /// a struct you can check the nullability of the `maxStale` variable as well as then check the nullability
        /// of the `seconds` to differentiate.
        public struct MaxStale: Sendable {
            /// The upper limit of staleness the client will accept.
            public var seconds: Int?
        }

        /// Indicates that once a resource becomes stale, caches must not use their stale copy without
        /// successful [validation](https://developer.mozilla.org/en-US/docs/Web/HTTP/Caching#Cache_validation) on the origin server.
        public var mustRevalidate: Bool

        /// Caches must check with the origin server for
        /// [validation](https://developer.mozilla.org/en-US/docs/Web/HTTP/Caching#Cache_validation) before using the cached copy.
        public var noCache: Bool

        /// The cache **should not store anything** about the client request or server response.
        public var noStore: Bool

        /// No transformations or conversions should be made to the resource. The Content-Encoding, Content-Range, Content-Type headers must not be modified
        /// by a proxy. A non-transparent proxy or browser feature such as
        /// [Google's Light Mode](https://support.google.com/webmasters/answer/6211428?hl=en) might, for example, convert between image
        /// formats in order to save cache space or to reduce the amount of traffic on a slow link. The `no-transform` directive disallows this.
        public var noTransform: Bool

        /// The response may be cached by any cache, even if the response is normally non-cacheable
        public var isPublic: Bool

        /// The response is for a single user and **must not** be stored by a shared cache. A private cache (like the user's browser cache) may store the response.
        public var isPrivate: Bool

        /// Like `must-revalidate`, but only for shared caches (e.g., proxies). Ignored by private caches.
        public var proxyRevalidate: Bool

        /// Indicates to not retrieve new data. This being the case, the server wishes the client to obtain a response only once and then cache. From this moment the
        /// client should keep releasing a cached copy and avoid contacting the origin-server to see if a newer copy exists.
        public var onlyIfCached: Bool

        /// Indicates that the response body **will not change** over time.
        ///
        /// The resource, if *unexpired*, is unchanged on the server and therefore the client should
        /// not send a conditional revalidation for it (e.g. `If-None-Match` or `If-Modified-Since`) to check for updates, even when the user explicitly refreshes
        /// the page. Clients that aren't aware of this extension must ignore them as per the HTTP specification. In Firefox, immutable is only honored on https:// transactions.
        /// For more information, see also this [blog post](https://bitsup.blogspot.de/2016/05/cache-control-immutable.html).
        public var immutable: Bool

        /// The maximum amount of time a resource is considered fresh. Unlike the`Expires` header, this directive is relative to the time of the request.
        public var maxAge: Int?

        /// Overrides max-age or the Expires header, but only for shared caches (e.g., proxies). Ignored by private caches.
        public var sMaxAge: Int?

        /// Indicates the client will accept a stale response. An optional value in seconds indicates the upper limit of staleness the client will accept.
        public var maxStale: MaxStale?

        /// Indicates the client wants a response that will still be fresh for at least the specified number of seconds.
        public var minFresh: Int?

        /// Indicates the client will accept a stale response, while asynchronously checking in the background for a fresh one. The value indicates how long the client will accept a stale response.
        public var staleWhileRevalidate: Int?

        /// Indicates the client will accept a stale response if the check for a fresh one fails. The value indicates how many *seconds* long the client will accept the stale response after the initial expiration.
        public var staleIfError: Int?

        /// Creates a new `CacheControl`.
        public init(
            mustRevalidated: Bool = false,
            noCache: Bool = false,
            noStore: Bool = false,
            noTransform: Bool = false,
            isPublic: Bool = false,
            isPrivate: Bool = false,
            proxyRevalidate: Bool = false,
            onlyIfCached: Bool = false,
            immutable: Bool = false,
            maxAge: Int? = nil,
            sMaxAge: Int? = nil,
            maxStale: MaxStale? = nil,
            minFresh: Int? = nil,
            staleWhileRevalidate: Int? = nil,
            staleIfError: Int? = nil
        ) {
            self.mustRevalidate = mustRevalidated
            self.noCache = noCache
            self.noStore = noStore
            self.noTransform = noTransform
            self.isPublic = isPublic
            self.isPrivate = isPrivate
            self.proxyRevalidate = proxyRevalidate
            self.onlyIfCached = onlyIfCached
            self.immutable = immutable
            self.maxAge = maxAge
            self.sMaxAge = sMaxAge
            self.maxStale = maxStale
            self.minFresh = minFresh
            self.staleWhileRevalidate = staleWhileRevalidate
            self.staleIfError = staleIfError
        }

        public static func parse(_ value: String) -> CacheControl? {
            var set = CharacterSet.whitespacesAndNewlines
            set.insert(",")

            var foundSomething = false

            var cache = CacheControl()

            value
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "\t", with: "")
                .lowercased()
                .split(separator: ",")
                .forEach {
                    let str = String($0)

                    if let keyPath = Self.exactMatch[str] {
                        cache[keyPath: keyPath] = true
                        foundSomething = true
                        return
                    }

                    if value == "max-stale" {
                        cache.maxStale = .init()
                        foundSomething = true
                        return
                    }

                    let parts = str.components(separatedBy: "=")
                    guard parts.count == 2, let seconds = Int(parts[1]), seconds >= 0 else {
                        return
                    }

                    if parts[0] == "max-stale" {
                        cache.maxStale = .init(seconds: seconds)
                        foundSomething = true
                        return
                    }

                    guard let keyPath = Self.prefix[parts[0]] else {
                        return
                    }

                    cache[keyPath: keyPath] = seconds
                    foundSomething = true
            }

            return foundSomething ? cache : nil
        }

        /// Generates the header string for this instance.
        public func serialize() -> String {
            var options = Self.exactMatch
                .filter { self[keyPath: $0.value] == true }
                .map { $0.key }

            var optionsWithSeconds = Self.prefix
                .filter { self[keyPath: $0.value] != nil }
                .map { "\($0.key)=\(self[keyPath: $0.value]!)" }

            if let maxStale = self.maxStale {
                if let seconds = maxStale.seconds {
                    optionsWithSeconds.append("max-stale=\(seconds)")
                } else {
                    options.append("max-stale")
                }
            }
            
            return (options + optionsWithSeconds).joined(separator: ", ")
        }

        private static let exactMatch: [String: WritableKeyPath<Self, Bool>] = [
            "immutable": \.immutable,
            "must-revalidate": \.mustRevalidate,
            "no-cache": \.noCache,
            "no-store": \.noStore,
            "no-transform": \.noTransform,
            "public": \.isPublic,
            "private": \.isPrivate,
            "proxy-revalidate": \.proxyRevalidate,
            "only-if-cached": \.onlyIfCached
        ]

        private static let prefix: [String: WritableKeyPath<Self, Int?>] = [
            "max-age": \.maxAge,
            "s-maxage": \.sMaxAge,
            "min-fresh": \.minFresh,
            "stale-while-revalidate": \.staleWhileRevalidate,
            "stale-if-error": \.staleIfError
        ]
    }

    /// Gets the value of the `Cache-Control` header, if present.
    public var cacheControl: CacheControl? {
        get { self.first(name: .cacheControl).flatMap(CacheControl.parse) }
        set {
            if let new = newValue?.serialize() {
                self.replaceOrAdd(name: .cacheControl, value: new)
            } else {
                self.remove(name: .expires)
            }
        }
    }
}

#warning("Sort out")
extension Swift.WritableKeyPath: @unchecked Swift.Sendable {}
