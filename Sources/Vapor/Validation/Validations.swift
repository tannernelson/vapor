import Foundation

public struct Validations: Sendable {
    var storage: [Validation]
    
    public init() {
        self.storage = []
    }
    
    public mutating func add<T>(
        _ key: BasicCodingKey,
        as type: T.Type = T.self,
        is validator: Validator<T> = .valid,
        required: Bool = true,
        customFailureDescription: String? = nil
    ) {
        self.storage.append(.init(key: key, required: required, validator: validator, customFailureDescription: customFailureDescription))
    }
    
    public mutating func add(
        _ key: BasicCodingKey,
        result: ValidatorResult,
        customFailureDescription: String? = nil
    ) {
        self.storage.append(.init(key: key, result: result, customFailureDescription: customFailureDescription))
    }

    public mutating func add(
        _ key: BasicCodingKey,
        required: Bool = true,
        customFailureDescription: String? = nil,
        _ nested: (inout Validations) -> ()
    ) {
        var validations = Validations()
        nested(&validations)
        self.storage.append(.init(nested: key, required: required, keyed: validations, customFailureDescription: customFailureDescription))
    }
    
    public mutating func add(
        each key: BasicCodingKey,
        required: Bool = true,
        customFailureDescription: String? = nil,
        _ handler: @Sendable @escaping (Int, inout Validations) -> ()
    ) {
        self.storage.append(.init(nested: key, required: required, unkeyed: handler, customFailureDescription: customFailureDescription))
    }
    
    public func validate(request: Request) throws -> ValidationsResult {
        guard let contentType = request.headers.contentType else {
            throw Abort(.unprocessableEntity, reason: "Missing \"Content-Type\" header")
        }
        guard let body = request.body.data else {
            throw Abort(.unprocessableEntity, reason: "Empty Body")
        }
        let contentDecoder = try ContentConfiguration.global.requireDecoder(for: contentType)
        return try contentDecoder.decode(ValidationsExecutor.self, from: body, headers: request.headers, userInfo: [.pendingValidations: self]).results
    }
    
    public func validate(query: URI) throws -> ValidationsResult {
        let urlDecoder = try ContentConfiguration.global.requireURLDecoder()
        return try urlDecoder.decode(ValidationsExecutor.self, from: query, userInfo: [.pendingValidations: self]).results
    }
    
    public func validate(json: String) throws -> ValidationsResult {
        return try ContentConfiguration.global.requireDecoder(for: .json)
            .decode(ValidationsExecutor.self, from: .init(string: json), headers: [:], userInfo: [.pendingValidations: self]).results
    }
    
    public func validate(_ decoder: Decoder) throws -> ValidationsResult {
        let container = try decoder.container(keyedBy: BasicCodingKey.self)
        
        return try .init(results: self.storage.map {
            try .init(
                key: $0.key,
                result: {
                    switch (container.contains($0.key), $0.valuelessKeyBehavior) {
                    case (_, .ignore):          return $0.run(decoder) // do *NOT* call superDecoder(forKey:) here!
                    case (false, .missing):     return ValidatorResults.Missing()
                    case (true, .skipAlways) where try container.decodeNil(forKey: $0.key),
                         (false, .skipWhenUnset),
                         (false, .skipAlways):  return ValidatorResults.Skipped()
                    case (true, _):             return try $0.run(container.superDecoder(forKey: $0.key))
                    }
                }($0),
                customFailureDescription: $0.customFailureDescription
            )
        })
    }
}

/// N.B.: The only reason we need all this is that "top-level" decoders like JSONDecoder etc. do not actually conform to
/// Decoder, so we can only invoke our logic from the other end of Codable. And the only way to pass the validation set
/// through is via Codable's oft-ignored userInfo mechanism. (Ideally, we'd flip things around and do some magic with
/// _En_coder instead, but we can't do that without breaking public API.)

fileprivate extension CodingUserInfoKey {
    static var pendingValidations: Self { .init(rawValue: "codes.vapor.validation.pendingValidations")! }
}

fileprivate struct ValidationsExecutor: Decodable {
    let results: ValidationsResult
    
    init(from decoder: Decoder) throws {
        guard let pendingValidations = decoder.userInfo[.pendingValidations] as? Validations else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Validation executor couldn't find any validations to run (broken Decoder?)"))
        }
        try self.init(from: decoder, explicitValidations: pendingValidations)
    }
    
    init(from decoder: Decoder, explicitValidations: Validations) throws {
        self.results = try explicitValidations.validate(decoder)
    }
}
