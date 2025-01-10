import XCTVapor
import XCTest
import Vapor
import NIOCore
import Algorithms

func XCTAssertURIComponents(
       scheme: @autoclosure () throws -> URI.Scheme?,
     userinfo: @autoclosure () throws -> String? = nil,
         host: @autoclosure () throws -> String? = nil,
         port: @autoclosure () throws -> Int?    = nil,
         path: @autoclosure () throws -> String,
        query: @autoclosure () throws -> String? = nil,
     fragment: @autoclosure () throws -> String? = nil,
     generate expected: @autoclosure () throws -> String,
    _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertURIComponents(
        scheme: try scheme()?.value,
        userinfo: try userinfo(),
        host: try host(),
        port: try port(),
        path: try path(),
        query: try query(),
        fragment: try fragment(),
        generate: try expected(),
        message(), file: file, line: line
    )
}

func XCTAssertURIComponents(
       scheme: @autoclosure () throws -> String? = nil,
     userinfo: @autoclosure () throws -> String? = nil,
         host: @autoclosure () throws -> String? = nil,
         port: @autoclosure () throws -> Int?    = nil,
         path: @autoclosure () throws -> String,
        query: @autoclosure () throws -> String? = nil,
     fragment: @autoclosure () throws -> String? = nil,
     generate expected: @autoclosure () throws -> String,
    _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line
) {
    do {
        let scheme = try scheme(), rawuserinfo = try userinfo(), host = try host(), port = try port(),
            path = try path(), query = try query(), fragment = try fragment()
        let uri = URI(scheme: scheme, userinfo: rawuserinfo, host: host, port: port, path: path, query: query, fragment: fragment)
        
        let userinfo = rawuserinfo.map {
            !$0.contains(":") ? $0 :
                $0.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).enumerated()
                  .map { $1.addingPercentEncoding(withAllowedCharacters: $0 == 0 ? .urlUserAllowed : .urlPasswordAllowed)! }
                  .joined(separator: ":")
        }
        
        // All components should be identical to their input counterparts with percent encoding.
        XCTAssertEqual(uri.scheme,   scheme,   "(scheme) \(message())", file: file, line: line)
        XCTAssertEqual(uri.userinfo, userinfo, "(userinfo) \(message())", file: file, line: line)
        XCTAssertEqual(uri.host,     host?.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),     "(host) \(message())", file: file, line: line)
        XCTAssertEqual(uri.port,     port,     "(port) \(message())", file: file, line: line)
        XCTAssertEqual(uri.path,     path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),     "(path) \(message())", file: file, line: line)
        XCTAssertEqual(uri.query,    query?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),    "(query) \(message())", file: file, line: line)
        XCTAssertEqual(uri.fragment, fragment?.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed), "(fragment) \(message())", file: file, line: line)
        
        // The URI's generated string should match the expected input.
        XCTAssertEqual(uri.string,   try expected(), "(string) \(message())", file: file, line: line)
    } catch {
        XCTAssertEqual(try { throw error }(), false, message(), file: file, line: line)
    }
}

func XCTAssertURIString(
     _ string: @autoclosure () throws -> String,
     hasScheme scheme:     @autoclosure () throws -> String? = nil,
     hasUserinfo userinfo: @autoclosure () throws -> String? = nil,
     hasHost host:         @autoclosure () throws -> String? = "",
     hasPort port:         @autoclosure () throws -> Int?    = nil,
     hasPath path:         @autoclosure () throws -> String,
     hasQuery query:       @autoclosure () throws -> String? = nil,
     hasFragment fragment: @autoclosure () throws -> String? = nil,
     hasEqualString exact: @autoclosure () throws -> Bool = true,
    _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line
) {
    do {
        let string = try string()
        let uri = URI(string: string)

        // Each component should match its expected value.
        XCTAssertEqual(uri.scheme,   try scheme(),   "(scheme) \(message())", file: file, line: line)
        XCTAssertEqual(uri.userinfo, try userinfo(), "(userinfo) \(message())", file: file, line: line)
        XCTAssertEqual(uri.host,     try host(),     "(host) \(message())", file: file, line: line)
        XCTAssertEqual(uri.port,     try port(),     "(port) \(message())", file: file, line: line)
        XCTAssertEqual(uri.path,     try path(),     "(path) \(message())", file: file, line: line)
        XCTAssertEqual(uri.query,    try query(),    "(query) \(message())", file: file, line: line)
        XCTAssertEqual(uri.fragment, try fragment(), "(fragment) \(message())", file: file, line: line)
        
        // The URI's generated string should come out identical to the input string, unless explicitly stated otherwise.
        if try exact() {
            XCTAssertEqual(uri.string,   string,     "(string) \(message())", file: file, line: line)
        }
    } catch {
        XCTAssertEqual(try { throw error }(), false, message(), file: file, line: line)
    }
}

final class URITests: XCTestCase {
    func testBasicConstruction() {
        XCTAssertURIString(
            "https://user:pass@vapor.codes:1234/foo?bar=baz#qux",
            hasScheme: "https",
            hasUserinfo: "user:pass",
            hasHost: "vapor.codes",
            hasPort: 1234,
            hasPath: "/foo",
            hasQuery: "bar=baz",
            hasFragment: "qux"
        )
        XCTAssertURIComponents(
            scheme: "https",
            userinfo: "user:pass",
            host: "vapor.codes",
            port: 1234,
            path: "/foo",
            query: "bar=baz",
            fragment: "qux",
            generate: "https://user:pass@vapor.codes:1234/foo?bar=baz#qux"
        )

        XCTAssertURIString("wss://echo.websocket.org/", hasScheme: "wss", hasHost: "echo.websocket.org", hasPath: "/")
        XCTAssertURIComponents(scheme: "wss", host: "echo.websocket.org", path: "/", generate: "wss://echo.websocket.org/")
    }
    
    func testSemicolonIsNotEncodedInPathComponent() {
        XCTAssertURIString(
            "https://user:pass@vapor.codes:1234/foo;?bar=abcd%3B%C3%A4%2B;efg#qux%3B",
            hasScheme: "https",
            hasUserinfo: "user:pass",
            hasHost: "vapor.codes",
            hasPort: 1234,
            hasPath: "/foo;",
            hasQuery: "bar=abcd%3B%C3%A4%2B;efg",
            hasFragment: "qux%3B"
        )
    }
    
    func testMutation() {
        var uri = URI(string: "https://user:pass@vapor.codes:1234/foo?bar=baz#qux")
    
        // Mutate query
        uri.query = "bar=baz&test=1"
        XCTAssertEqual(uri.string, "https://user:pass@vapor.codes:1234/foo?bar=baz&test=1#qux")

        // Remove query
        uri.query = nil
        XCTAssertEqual(uri.string, "https://user:pass@vapor.codes:1234/foo#qux")
    }
    
    func testPathStrings() {
        // Absolute path string
        let uri = URI(string: "/foo/bar/baz")
        XCTAssertEqual(uri.path, "/foo/bar/baz")
    }
    
    func testNonAbsolutePath() {
        let uri = URI(string: "foo")

        // N.B.: This test previously asserted that the _scheme_ of the resulting URI was `foo`. This was
        // a semantically incorrect parse (per RFC 3986) and should have been considered a bug; hence it
        // is not considered source-breaking to have fixed it.
        XCTAssertEqual(uri.scheme, nil)
        XCTAssertEqual(uri.host, nil)
        XCTAssertEqual(uri.path, "foo")
    }
    
    func testStringInterpolation() {
        let foo = "foo"
        XCTAssertEqual(("/\(foo)/bar/baz" as URI).path, "/foo/bar/baz")

        let bar = "bar"
        let uri = URI(scheme: "foo\(bar)", host: "host", port: 1, path: "test", query: "query", fragment: "fragment")
        XCTAssertEqual(uri.string, "foobar://host:1/test?query#fragment")
    }
    
    // Disable tests on Linux 6.0 until behaviour is fixed
    #if compiler(<6.0)
    func testVariousSchemesAndWeirdHosts() {
        // N.B.: This test previously asserted that the resulting string did _not_ start with the `//` "authority"
        // prefix. Again, according to RFC 3986, this was always semantically incorrect.
        XCTAssertURIComponents(
            host: "host", port: 1, path: "/test", query: "query", fragment: "fragment",
            generate: "//host:1/test?query#fragment"
        )

        XCTAssertURIComponents(
            scheme: .httpUnixDomainSocket, host: "/path", path: "/test",
            generate: "http+unix://%2Fpath/test"
        )
        XCTAssertURIComponents(
            scheme: .httpUnixDomainSocket, host: "/path", path: "/test", fragment: "fragment",
            generate: "http+unix://%2Fpath/test#fragment"
        )
        XCTAssertURIComponents(
            scheme: .httpUnixDomainSocket, host: "/path", path: "/test", query: "query", fragment: "fragment",
            generate: "http+unix://%2Fpath/test?query#fragment"
        )
    }
    #endif
    
    func testDefaultInitializer() {
        let uri = URI.init()
        XCTAssertEqual(uri.string, "/")
    }
    
    func testOverlongURIParsing() {
        let zeros = String(repeating: "0", count: 65_512)
        let untrustedInput = "[https://vapor.codes.somewhere-else.test:](https://vapor.codes.somewhere-else.test/\(zeros)443)[\(zeros)](https://vapor.codes.somewhere-else.test/\(zeros)443)[443](https://vapor.codes.somewhere-else.test/\(zeros)443)"
    
        let readableInAssertionOutput = untrustedInput
            .replacingOccurrences(of: zeros, with: "00...00")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let uri = URI(string: untrustedInput)

        XCTAssertNil(uri.scheme)
        XCTAssertNil(uri.userinfo)
        XCTAssertNil(uri.host)
        XCTAssertNil(uri.port)
        XCTAssertNil(uri.query)
        XCTAssertNil(uri.fragment)
        // TODO: It is not clear why the "encode the first colon as %3A but none of the others" behavior appears, and why only on Darwin
        XCTAssertEqual(
            uri.path.replacingOccurrences(of: zeros, with: "00...00").replacing("%3A", with: ":", maxReplacements: 1),
            readableInAssertionOutput.replacing("%3A", with: ":", maxReplacements: 1)
        )
    }
    
    func testUrlParsingVectors() {
        XCTAssertURIString("file:///usr/local/bin", hasScheme: "file", hasPath: "/usr/local/bin")
        XCTAssertURIString("file:/usr/local/bin", hasScheme: "file", hasHost: nil, hasPath: "/usr/local/bin")
        XCTAssertURIString("file://localhost/usr/local/bin", hasScheme: "file", hasHost: "localhost", hasPath: "/usr/local/bin")
        XCTAssertURIString("file://usr/local/bin", hasScheme: "file", hasHost: "usr", hasPath: "/local/bin")
        XCTAssertURIString("/usr/local/bin", hasHost: nil, hasPath: "/usr/local/bin")
        XCTAssertURIString("file://localhost/usr/local/bin/", hasScheme: "file", hasHost: "localhost", hasPath: "/usr/local/bin/")
        XCTAssertURIString("file://localhost/", hasScheme: "file", hasHost: "localhost", hasPath: "/")
        XCTAssertURIString("file:///", hasScheme: "file", hasPath: "/")
        XCTAssertURIString("file:/", hasScheme: "file", hasHost: nil, hasPath: "/")
        XCTAssertURIString("file:///Volumes", hasScheme: "file", hasPath: "/Volumes")
        XCTAssertURIString("file:///Users/darin", hasScheme: "file", hasPath: "/Users/darin")
        XCTAssertURIString("file:/", hasScheme: "file", hasHost: nil, hasPath: "/")
        XCTAssertURIString("file:///.", hasScheme: "file", hasPath: "/.")
        XCTAssertURIString("file:///./.", hasScheme: "file", hasPath: "/./.")
        XCTAssertURIString("file:///.///.", hasScheme: "file", hasPath: "/.///.")
        XCTAssertURIString("file:///a/..", hasScheme: "file", hasPath: "/a/..")
        XCTAssertURIString("file:///a/b/..", hasScheme: "file", hasPath: "/a/b/..")
        XCTAssertURIString("file:///a/b//..", hasScheme: "file", hasPath: "/a/b//..")
        XCTAssertURIString("file:///./a/b/..", hasScheme: "file", hasPath: "/./a/b/..")
        XCTAssertURIString("file:///a/./b/..", hasScheme: "file", hasPath: "/a/./b/..")
        XCTAssertURIString("file:///a/b/./..", hasScheme: "file", hasPath: "/a/b/./..")
        XCTAssertURIString("file:///a///b//..", hasScheme: "file", hasPath: "/a///b//..")
        XCTAssertURIString("file:///a/b/../..", hasScheme: "file", hasPath: "/a/b/../..")
        XCTAssertURIString("file:///a/b/c/../..", hasScheme: "file", hasPath: "/a/b/c/../..")
        XCTAssertURIString("file:///a/../b/..", hasScheme: "file", hasPath: "/a/../b/..")
        XCTAssertURIString("file:///a/../b/../c", hasScheme: "file", hasPath: "/a/../b/../c")
        XCTAssertURIString("file:///a/../b/../c", hasScheme: "file", hasPath: "/a/../b/../c")
        XCTAssertURIString("ftp://ftp.gnu.org/", hasScheme: "ftp", hasHost: "ftp.gnu.org", hasPath: "/")
        XCTAssertURIString("ftp://ftp.gnu.org/pub/gnu", hasScheme: "ftp", hasHost: "ftp.gnu.org", hasPath: "/pub/gnu")
        XCTAssertURIString("ftp://luser@ftp.gnu.org/pub/gnu",
            hasScheme: "ftp", hasUserinfo: "luser", hasHost: "ftp.gnu.org", hasPath: "/pub/gnu"
        )
        XCTAssertURIString("ftp://@ftp.gnu.org/pub/gnu", hasScheme: "ftp", hasUserinfo: "", hasHost: "ftp.gnu.org", hasPath: "/pub/gnu")
        XCTAssertURIString("ftp://luser:password@ftp.gnu.org/pub/gnu",
            hasScheme: "ftp", hasUserinfo: "luser:password", hasHost: "ftp.gnu.org", hasPath: "/pub/gnu"
        )
        XCTAssertURIString("ftp://:password@ftp.gnu.org/pub/gnu",
            hasScheme: "ftp", hasUserinfo: ":password", hasHost: "ftp.gnu.org", hasPath: "/pub/gnu"
        )
        XCTAssertURIString("ftp://ftp.gnu.org:72/pub/gnu", hasScheme: "ftp", hasHost: "ftp.gnu.org", hasPort: 72, hasPath: "/pub/gnu")
        XCTAssertURIString("ftp://:72/pub/gnu", hasScheme: "ftp", hasHost: "", hasPort: 72, hasPath: "/pub/gnu")
        XCTAssertURIString("http://localhost/usr/local/bin/", hasScheme: "http", hasHost: "localhost", hasPath: "/usr/local/bin/")
        XCTAssertURIString("http://localhost/", hasScheme: "http", hasHost: "localhost", hasPath: "/")
        XCTAssertURIString("http://www.apple.com/", hasScheme: "http", hasHost: "www.apple.com", hasPath: "/")
        XCTAssertURIString("http://www.apple.com/dir", hasScheme: "http", hasHost: "www.apple.com", hasPath: "/dir")
        XCTAssertURIString("http://www.apple.com/dir/", hasScheme: "http", hasHost: "www.apple.com", hasPath: "/dir/")
        XCTAssertURIString("http://darin:nothin@www.apple.com:42/dir/",
            hasScheme: "http", hasUserinfo: "darin:nothin", hasHost: "www.apple.com", hasPort: 42, hasPath: "/dir/"
        )
        XCTAssertURIString("http:/", hasScheme: "http", hasHost: nil, hasPath: "/")
        XCTAssertURIString("http://www.apple.com/query?email=darin@apple.com",
            hasScheme: "http", hasHost: "www.apple.com", hasPath: "/query", hasQuery: "email=darin@apple.com"
        )
        XCTAssertURIString("HTTP://WWW.ZOO.COM/", hasScheme: "HTTP", hasHost: "WWW.ZOO.COM", hasPath: "/")
        XCTAssertURIString("HTTP://WWW.ZOO.COM/ED", hasScheme: "HTTP", hasHost: "WWW.ZOO.COM", hasPath: "/ED")
        XCTAssertURIString("http://groups.google.com/groups?as_uauthors=joe@blow.com&as_scoring=d&hl=en",
            hasScheme: "http", hasHost: "groups.google.com", hasPath: "/groups", hasQuery: "as_uauthors=joe@blow.com&as_scoring=d&hl=en"
        )
        XCTAssertURIString("http://my.site.com/some/page.html#fragment",
            hasScheme: "http", hasHost: "my.site.com", hasPath: "/some/page.html", hasFragment: "fragment"
        )
        XCTAssertURIString("scheme://user:pass@host:1/path/path2/file.html;params?query#fragment",
            hasScheme: "scheme", hasUserinfo: "user:pass", hasHost: "host", hasPort: 1, hasPath: "/path/path2/file.html;params",
            hasQuery: "query", hasFragment: "fragment", hasEqualString: false
        )
        XCTAssertURIString("http://test.com/a%20space", hasScheme: "http", hasHost: "test.com", hasPath: "/a%20space")
        XCTAssertURIString("http://test.com/aBrace%7B", hasScheme: "http", hasHost: "test.com", hasPath: "/aBrace%7B")
        XCTAssertURIString("http://test.com/aJ%4a", hasScheme: "http", hasHost: "test.com", hasPath: "/aJ%4a")
        XCTAssertURIString("file:///%3F", hasScheme: "file", hasPath: "/%3F")
        XCTAssertURIString("file:///%78", hasScheme: "file", hasPath: "/%78")
        XCTAssertURIString("file:///?", hasScheme: "file", hasPath: "/", hasQuery: "")
        XCTAssertURIString("file:///&", hasScheme: "file", hasPath: "/&")
        XCTAssertURIString("file:///x", hasScheme: "file", hasPath: "/x")
        XCTAssertURIString("http:///%3F", hasScheme: "http", hasPath: "/%3F")
        XCTAssertURIString("http:///%78", hasScheme: "http", hasPath: "/%78")
        XCTAssertURIString("http:///?", hasScheme: "http", hasPath: "/", hasQuery: "")
        XCTAssertURIString("http:///&", hasScheme: "http", hasPath: "/&")
        XCTAssertURIString("http:///x", hasScheme: "http", hasPath: "/x")
        XCTAssertURIString("glorb:///%3F", hasScheme: "glorb", hasPath: "/%3F")
        XCTAssertURIString("glorb:///%78", hasScheme: "glorb", hasPath: "/%78")
        XCTAssertURIString("glorb:///?", hasScheme: "glorb", hasPath: "/", hasQuery: "")
        XCTAssertURIString("glorb:///&", hasScheme: "glorb", hasPath: "/&")
        XCTAssertURIString("glorb:///x", hasScheme: "glorb", hasPath: "/x")
        XCTAssertURIString("uahsfcncvuhrtgvnahr", hasHost: nil, hasPath: "uahsfcncvuhrtgvnahr")
        XCTAssertURIString("http://[fe80::20a:27ff:feae:8b9e]/", hasScheme: "http", hasHost: "[fe80::20a:27ff:feae:8b9e]", hasPath: "/")
        XCTAssertURIString("http://[fe80::20a:27ff:feae:8b9e%25en0]/", hasScheme: "http", hasHost: "[fe80::20a:27ff:feae:8b9e%25en0]", hasPath: "/")
        XCTAssertURIString("http://host.com/foo/bar/../index.html", hasScheme: "http", hasHost: "host.com", hasPath: "/foo/bar/../index.html")
        XCTAssertURIString("http://host.com/foo/bar/./index.html", hasScheme: "http", hasHost: "host.com", hasPath: "/foo/bar/./index.html")
        XCTAssertURIString("http:/cgi-bin/Count.cgi?ft=0", hasScheme: "http", hasHost: nil, hasPath: "/cgi-bin/Count.cgi", hasQuery: "ft=0")
        XCTAssertURIString("file://///", hasScheme: "file", hasPath: "///")
        XCTAssertURIString("file:/Volumes", hasScheme: "file", hasHost: nil, hasPath: "/Volumes")
        XCTAssertURIString("/Volumes", hasHost: nil, hasPath: "/Volumes")
        XCTAssertURIString(".", hasHost: nil, hasPath: ".")
        XCTAssertURIString("./a", hasHost: nil, hasPath: "./a")
        XCTAssertURIString("../a", hasHost: nil, hasPath: "../a")
        XCTAssertURIString("../../a", hasHost: nil, hasPath: "../../a")
        XCTAssertURIString("/", hasHost: nil, hasPath: "/")
        XCTAssertURIString("http://a/b/c/./g", hasScheme: "http", hasHost: "a", hasPath: "/b/c/./g")
        XCTAssertURIString("http://a/b/c/.", hasScheme: "http", hasHost: "a", hasPath: "/b/c/.")
        XCTAssertURIString("http://a/b/c/./", hasScheme: "http", hasHost: "a", hasPath: "/b/c/./")
        XCTAssertURIString("http://a/b/c/..", hasScheme: "http", hasHost: "a", hasPath: "/b/c/..")
        XCTAssertURIString("http://a/b/c/../", hasScheme: "http", hasHost: "a", hasPath: "/b/c/../")
        XCTAssertURIString("http://a/b/c/../g", hasScheme: "http", hasHost: "a", hasPath: "/b/c/../g")
        XCTAssertURIString("http://a/b/c/../..", hasScheme: "http", hasHost: "a", hasPath: "/b/c/../..")
        XCTAssertURIString("http://a/b/c/../../", hasScheme: "http", hasHost: "a", hasPath: "/b/c/../../")
        XCTAssertURIString("http://a/b/c/../../g", hasScheme: "http", hasHost: "a", hasPath: "/b/c/../../g")
        XCTAssertURIString("http://a/b/c/../../../g", hasScheme: "http", hasHost: "a", hasPath: "/b/c/../../../g")
        XCTAssertURIString("http://a/b/c/../../../../g", hasScheme: "http", hasHost: "a", hasPath: "/b/c/../../../../g")
        XCTAssertURIString("http://a/b/c/./g", hasScheme: "http", hasHost: "a", hasPath: "/b/c/./g")
        XCTAssertURIString("http://a/b/c/../g", hasScheme: "http", hasHost: "a", hasPath: "/b/c/../g")
        XCTAssertURIString("http://a/b/c/g.", hasScheme: "http", hasHost: "a", hasPath: "/b/c/g.")
        XCTAssertURIString("http://a/b/c/.g", hasScheme: "http", hasHost: "a", hasPath: "/b/c/.g")
        XCTAssertURIString("http://a/b/c/g..", hasScheme: "http", hasHost: "a", hasPath: "/b/c/g..")
        XCTAssertURIString("http://a/b/c/..g", hasScheme: "http", hasHost: "a", hasPath: "/b/c/..g")
        XCTAssertURIString("http://a/b/c/./../g", hasScheme: "http", hasHost: "a", hasPath: "/b/c/./../g")
        XCTAssertURIString("http://a/b/c/./g/.", hasScheme: "http", hasHost: "a", hasPath: "/b/c/./g/.")
        XCTAssertURIString("http://a/b/c/g/./h", hasScheme: "http", hasHost: "a", hasPath: "/b/c/g/./h")
        XCTAssertURIString("http://a/b/c/g/../h", hasScheme: "http", hasHost: "a", hasPath: "/b/c/g/../h")
        XCTAssertURIString("http://a/b/c/g;x=1/./y", hasScheme: "http", hasHost: "a", hasPath: "/b/c/g;x=1/./y", hasEqualString: false)
        XCTAssertURIString("http://a/b/c/g;x=1/../y", hasScheme: "http", hasHost: "a", hasPath: "/b/c/g;x=1/../y", hasEqualString: false)
        XCTAssertURIString("http://a/b/c/g?y/./x", hasScheme: "http", hasHost: "a", hasPath: "/b/c/g", hasQuery: "y/./x")
        XCTAssertURIString("http://a/b/c/g?y/../x", hasScheme: "http", hasHost: "a", hasPath: "/b/c/g", hasQuery: "y/../x")
        XCTAssertURIString("http://a/b/c/g#s/./x", hasScheme: "http", hasHost: "a", hasPath: "/b/c/g", hasFragment: "s/./x")
        XCTAssertURIString("http://a/b/c/g#s/../x", hasScheme: "http", hasHost: "a", hasPath: "/b/c/g", hasFragment: "s/../x")
        XCTAssertURIString("http://a/../../x", hasScheme: "http", hasHost: "a", hasPath: "/../../x")
        XCTAssertURIString("http://a/..///../x", hasScheme: "http", hasHost: "a", hasPath: "/..///../x")
    }
}
