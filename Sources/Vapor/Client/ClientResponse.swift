import NIOCore
import NIOHTTP1
import Foundation

public struct ClientResponse: Sendable {
    public var status: HTTPStatus
    public var headers: HTTPHeaders
    public var body: ByteBuffer?
    private let byteBufferAllocator: ByteBufferAllocator

    public init(status: HTTPStatus = .ok, headers: HTTPHeaders = [:], body: ByteBuffer? = nil, byteBufferAllocator: ByteBufferAllocator = ByteBufferAllocator()) {
        self.status = status
        self.headers = headers
        self.body = body
        self.byteBufferAllocator = byteBufferAllocator
    }
}

extension ClientResponse {
    private struct _ContentContainer: ContentContainer {
        var body: ByteBuffer?
        var headers: HTTPHeaders
        let allocator: ByteBufferAllocator

        var contentType: HTTPMediaType? {
            return self.headers.contentType
        }

        mutating func encode<E>(_ encodable: E, using encoder: ContentEncoder) throws where E : Encodable {
            var body = self.allocator.buffer(capacity: 0)
            try encoder.encode(encodable, to: &body, headers: &self.headers)
            self.body = body
        }

        func decode<D>(_ decodable: D.Type, using decoder: ContentDecoder) throws -> D where D : Decodable {
            guard let body = self.body else {
                throw Abort(.lengthRequired)
            }
            return try decoder.decode(D.self, from: body, headers: self.headers)
        }

        mutating func encode<C>(_ content: C, using encoder: ContentEncoder) throws where C : Content {
            var body = self.allocator.buffer(capacity: 0)
            var content = content
            try content.beforeEncode()
            try encoder.encode(content, to: &body, headers: &self.headers)
            self.body = body
        }

        func decode<C>(_ content: C.Type, using decoder: ContentDecoder) throws -> C where C : Content {
            guard let body = self.body else {
                throw Abort(.lengthRequired)
            }
            var decoded = try decoder.decode(C.self, from: body, headers: self.headers)
            try decoded.afterDecode()
            return decoded
        }
    }

    public var content: ContentContainer {
        get {
            return _ContentContainer(body: self.body, headers: self.headers, allocator: self.byteBufferAllocator)
        }
        set {
            let container = (newValue as! _ContentContainer)
            self.body = container.body
            self.headers = container.headers
        }
    }
}

extension ClientResponse: CustomStringConvertible {
    public var description: String {
        var desc = ["HTTP/1.1 \(status.code) \(status.reasonPhrase)"]
        desc += self.headers.map { "\($0.name): \($0.value)" }
        if var body = self.body {
            let string = body.readString(length: body.readableBytes) ?? ""
            desc += ["", string]
        }
        return desc.joined(separator: "\n")
    }
}

extension ClientResponse: ResponseEncodable {
    public func encodeResponse(for request: Request) async throws -> Response {
        let body: Response.Body
        if let buffer = self.body {
            body = .init(buffer: buffer)
        } else {
            body = .empty
        }
        let response = Response(
            status: self.status,
            headers: self.headers,
            body: body
        )
        return response
    }
}

extension ClientResponse: Codable {
    private enum CodingKeys: String, CodingKey {
        case status = "status"
        case headers = "headers"
        case body = "body"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try container.decode(HTTPStatus.self, forKey: .status)
        self.headers = try container.decode(HTTPHeaders.self, forKey: .headers)
        let bodyString = try container.decode(String?.self, forKey: .body)
        guard let s = bodyString, let bodyData = [UInt8].init(decodingBase64: s) else {
            throw Abort(.internalServerError, reason: "Could not decode client response body from base64 string")
        }
        self.byteBufferAllocator = ByteBufferAllocator()
        self.body = self.byteBufferAllocator.buffer(bytes: bodyData)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.status, forKey: .status)
        try container.encode(self.headers, forKey: .headers)
        if let body = self.body {
            let string = body.readableBytesView.base64String()
            try container.encode(string, forKey: .body)
        } else {
            try container.encodeNil(forKey: .body)
        }
    }
}

extension ClientResponse: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.status == rhs.status && lhs.headers == rhs.headers && lhs.body == rhs.body
    }
}
