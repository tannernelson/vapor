import Foundation
import NIOHTTP1

extension HTTPHeaders {
    
    /// The unit in which `ContentRange`s and `Range`s are specified. This is usually `bytes`.
    /// See https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Range
    public enum RangeUnit: Sendable, Equatable {
        case bytes
        case custom(value: String)
        
        public func serialize() -> String {
            switch self {
            case .bytes:
                return "bytes"
            case .custom(let value):
                return value
            }
        }
    }
    
    /// Represents the HTTP `Range` request header.
    /// See https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Range
    public struct Range: Sendable, Equatable {
        public let unit: RangeUnit
        public let ranges: [HTTPHeaders.Range.Value]
        
        public init(unit: RangeUnit, ranges: [HTTPHeaders.Range.Value]) {
            self.unit = unit
            self.ranges = ranges
        }
        
        init?(directives: [HTTPHeaders.Directive]) {
            let rangeCandidates: [HTTPHeaders.Range.Value] = directives.enumerated().compactMap {
                if $0.0 == 0, let parameter = $0.1.parameter {
                    return HTTPHeaders.Range.Value.from(requestStr: parameter)
                }
                return HTTPHeaders.Range.Value.from(requestStr: $0.1.value)
            }
            guard !rangeCandidates.isEmpty else {
                return nil
            }
            self.ranges = rangeCandidates
            let lowerCasedUnit = directives[0].value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            self.unit = lowerCasedUnit == "bytes"
                ? RangeUnit.bytes
                : RangeUnit.custom(value: lowerCasedUnit)
        }
        
        public func serialize() -> String {
            return "\(unit.serialize())=\(ranges.map { $0.serialize() }.joined(separator: ", "))"
        }
    }
    
    /// Represents the HTTP `Content-Range` response header.
    ///
    /// See https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Range
    public struct ContentRange: Equatable {
        public let unit: RangeUnit
        public let range: HTTPHeaders.ContentRange.Value
        
        init?(directive: HTTPHeaders.Directive) {
            let splitResult = directive.value.split(separator: " ")
            guard splitResult.count == 2 else {
                return nil
            }
            let (unitStr, rangeStr) = (splitResult[0], splitResult[1])
            let lowerCasedUnit = unitStr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let contentRange = HTTPHeaders.ContentRange.Value.from(responseStr: rangeStr) else {
                return nil
            }
            self.unit = lowerCasedUnit == "bytes"
                ? RangeUnit.bytes
                : RangeUnit.custom(value: lowerCasedUnit)
            self.range = contentRange
        }
        
        public init(unit: RangeUnit, range: HTTPHeaders.ContentRange.Value) {
            self.unit = unit
            self.range = range
        }
        
        init?(directives: [Directive]) {
            guard directives.count == 1 else {
                return nil
            }
            self.init(directive: directives[0])
        }
        
        public func serialize() -> String {
            return "\(unit.serialize()) \(range.serialize())"
        }
        
    }
    
    /// Convenience for accessing the Content-Range response header.
    ///
    /// See https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Range
    public var contentRange: ContentRange? {
        get {
            return HTTPHeaders.ContentRange(directives: self.parseDirectives(name: .contentRange).flatMap { $0 })
        }
        set {
            if self.contains(name: .contentRange) {
                self.remove(name: .contentRange)
            }
            guard let newValue = newValue else {
                return
            }
            self.add(name: .contentRange, value: newValue.serialize())
        }
    }
    
    /// Convenience for accessing the `Range` request header.
    ///
    /// See https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Range
    public var range: Range? {
        get {
            return HTTPHeaders.Range(directives: self.parseDirectives(name: .range).flatMap { $0 })
        }
        set {
            if self.contains(name: .range) {
                self.remove(name: .range)
            }
            guard let newValue = newValue else {
                return
            }
            self.add(name: .range, value: newValue.serialize())
        }
    }
}

extension HTTPHeaders.Range {
    /// Represents one value of the `Range` request header.
    ///
    /// See https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Range
    public enum Value: Sendable, Equatable {
        ///Integer with single trailing dash, e.g. `25-`
        case start(value: Int)
        ///Integer with single leading dash, e.g. `-25`
        case tail(value: Int)
        ///Two integers with single dash in between, e.g. `20-25`
        case within(start: Int, end: Int)
        
        ///Parses a string representing a requested range in one of the following formats:
        ///
        ///- `<range-start>-<range-end>`
        ///- `-<range-end>`
        ///- `<range-start>-`
        ///
        /// - parameters:
        ///     - requestStr: String representing a requested range
        /// - returns: A `HTTPHeaders.Range.Value` if the `requestStr` is valid, `nil` otherwise.
        public static func from<T>(requestStr: T) -> HTTPHeaders.Range.Value? where T: StringProtocol {
            let ranges = requestStr.split(separator: "-", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let count = ranges.count
            guard count <= 2 else { return nil }
    
            switch (count > 0 ? Int(ranges[0]) : nil, count > 1 ? Int(ranges[1]) : nil) {
            case (nil, nil):
                return nil
            case let (.some(start), nil):
                return .start(value: start)
            case let (nil, .some(tail)):
                return .tail(value: tail)
            case let (.some(start), .some(end)):
                return .within(start: start, end: end)
            }
        }
        
        ///Serializes `HTTPHeaders.Range.Value` to a string for use within the HTTP `Range` header.
        public func serialize() -> String {
            switch self {
            case .start(let value):
                return "\(value)-"
            case .tail(let value):
                return "-\(value)"
            case .within(let start, let end):
                return "\(start)-\(end)"
            }
        }
    }
}

extension HTTPHeaders.ContentRange {
    /// Represents the value of the `Content-Range` request header.
    ///
    /// See https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Range
    public enum Value : Equatable {
        case within(start: Int, end: Int)
        case withinWithLimit(start: Int, end: Int, limit: Int)
        case any(size: Int)
        
        ///Parses a string representing a response range in one of the following formats:
        ///
        ///- `<range-start>-<range-end>/<size>`
        ///- `<range-start>-<range-end>/*`
        ///- `*/<size>`
        ///
        /// - parameters:
        ///     - requestStr: String representing the response range
        /// - returns: A `HTTPHeaders.ContentRange.Value` if the `responseStr` is valid, `nil` otherwise.
        public static func from<T>(responseStr: T) -> HTTPHeaders.ContentRange.Value? where T : StringProtocol {
            let ranges = responseStr.split(separator: "-", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            switch ranges.count {
            case 1:
                let anyRangeOfSize = ranges[0].split(separator: "/", omittingEmptySubsequences: false)
                guard anyRangeOfSize.count == 2,
                    anyRangeOfSize[0] == "*",
                    let size = Int(anyRangeOfSize[1]) else {
                        return nil
                }
                return .any(size: size)
            case 2:
                guard let start = Int(ranges[0]) else {
                    return nil
                }
                let limits = ranges[1].split(separator: "/", omittingEmptySubsequences: false)
                guard limits.count == 2, let end = Int(limits[0]) else {
                    return nil
                }
                if limits[1] == "*" {
                    return .within(start: start, end: end)
                }
                guard let limit = Int(limits[1]) else {
                    return nil
                }
                return .withinWithLimit(start: start, end: end, limit: limit)
            default: return nil
            }
        }
        
        ///Serializes `HTTPHeaders.Range.Value` to a string for use within the HTTP `Content-Range` header.
        public func serialize() -> String {
            switch self {
            case .any(let size):
                return "*/\(size)"
            case .within(let start, let end):
                return "\(start)-\(end)/*"
            case .withinWithLimit(let start, let end, let limit):
                return "\(start)-\(end)/\(limit)"
            }
        }
    }
}

extension HTTPHeaders.Range.Value {
    
    ///Converts this `HTTPHeaders.Range.Value` to a `HTTPHeaders.ContentRange.Value` with the given `limit`.
    public func asResponseContentRange(limit: Int) throws -> HTTPHeaders.ContentRange.Value {
        switch self {
        case .start(let start):
            guard start <= limit, start >= 0 else {
                throw Abort(.badRequest)
            }
            return .withinWithLimit(start: start, end: limit - 1, limit: limit)
        case .tail(let end):
            guard end <= limit, end >= 0 else {
                throw Abort(.badRequest)
            }
            return .withinWithLimit(start: (limit - end), end: limit - 1, limit: limit)
        case .within(let start, let end):
            guard start >= 0, end >= 0, start < end, start <= limit else {
                throw Abort(.badRequest)
            }
            
            let endToRequest = min(end, limit)
            return .withinWithLimit(start: start, end: endToRequest, limit: limit)
        }
    }
}
