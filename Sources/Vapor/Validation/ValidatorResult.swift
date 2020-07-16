public struct ValidatorResults {
    public struct Nested {
        public let results: [ValidatorResult]
    }
    
    public struct Skipped { }

    public struct Missing { }

    public struct NotFound { }

    public struct Codable {
        public let error: Error
    }

    public struct Invalid {
        public let reason: String
    }

    public struct TypeMismatch {
        public let type: Any.Type
    }
}

extension ValidatorResults.Nested: ValidatorResult {
    public var isFailure: Bool {
        !self.results.filter { $0.isFailure }.isEmpty
    }
    
    public var successDescription: String? {
        self.results.filter { !$0.isFailure }
            .compactMap { $0.successDescription }
            .joined(separator: " and ")
    }
    
    public var failureDescription: String? {
        self.results.filter { $0.isFailure }
            .compactMap { $0.failureDescription }
            .joined(separator: " and ")
    }
}

extension ValidatorResults.Skipped: ValidatorResult {
    public var isFailure: Bool {
        false
    }
    
    public var successDescription: String? {
        nil
    }
    
    public var failureDescription: String? {
        nil
    }
}

extension ValidatorResults.Missing: ValidatorResult {
    public var isFailure: Bool {
        true
    }
    
    public var successDescription: String? {
        nil
    }
    
    public var failureDescription: String? {
        "is required"
    }
}

extension ValidatorResults.Invalid: ValidatorResult {
    public var isFailure: Bool {
        true
    }

    public var successDescription: String? {
        nil
    }

    public var failureDescription: String? {
        "is invalid: \(self.reason)"
    }
}

extension ValidatorResults.NotFound: ValidatorResult {
    public var isFailure: Bool {
        true
    }

    public var successDescription: String? {
        nil
    }

    public var failureDescription: String? {
        "cannot be null"
    }
}


extension ValidatorResults.TypeMismatch: ValidatorResult {
    public var isFailure: Bool {
        true
    }

    public var successDescription: String? {
        nil
    }

    public var failureDescription: String? {
        "is not a(n) \(self.type)"
    }
}

extension ValidatorResults.Codable: ValidatorResult {
    public var isFailure: Bool {
        true
    }
    
    public var successDescription: String? {
        nil
    }
    
    public var failureDescription: String? {
        "failed to decode: \(error)"
    }
}

public protocol ValidatorResult {
    var isFailure: Bool { get }
    var successDescription: String? { get }
    var failureDescription: String? { get }
}
