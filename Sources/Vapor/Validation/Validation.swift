public struct Validation: Sendable {
    enum ValuelessKeyBehavior {
        case missing // value is required; return a Missing() result if key is not found
        case skipWhenUnset // value is not required, but should not be nil-checked; return a Skipped() result only if key doesn't exist at all
        case skipAlways // value is not required, return a Skipped() result if key is unset or nil
        case ignore // value is not relevant, call run closure regardless of key presence
    }
    let key: BasicCodingKey
    let valuelessKeyBehavior: ValuelessKeyBehavior
    let customFailureDescription: String?
    let run: @Sendable (Decoder) -> ValidatorResult

    init<T>(key: BasicCodingKey, required: Bool, validator: Validator<T>, customFailureDescription: String?) {
        self.init(
            key: key,
            valuelessKeyBehavior: required ? .missing : .skipAlways,
            customFailureDescription: customFailureDescription
        ) { decoder -> ValidatorResult in
            do {
                let container = try decoder.singleValueContainer()
                return try validator.validate(container.decode(T.self))
            } catch DecodingError.valueNotFound {
                return ValidatorResults.NotFound()
            } catch DecodingError.typeMismatch(let type, _) {
                return ValidatorResults.TypeMismatch(type: type)
            } catch DecodingError.dataCorrupted(let context) {
                return ValidatorResults.Invalid(reason: context.debugDescription)
            } catch {
               return ValidatorResults.Codable(error: error)
            }
        }
    }
    
    init(nested key: BasicCodingKey, required: Bool, keyed validations: Validations, customFailureDescription: String?) {
        self.init(
            key: key,
            valuelessKeyBehavior: required ? .missing : .skipAlways,
            customFailureDescription: customFailureDescription
        ) { decoder in
            do {
                return try ValidatorResults.Nested(results: validations.validate(decoder).results)
            } catch {
                return ValidatorResults.Codable(error: error)
            }
        }
    }
    
    init(nested key: BasicCodingKey, required: Bool, unkeyed factory: @Sendable @escaping (Int, inout Validations) -> (), customFailureDescription: String?) {
        self.init(
            key: key,
            valuelessKeyBehavior: required ? .missing : .skipAlways,
            customFailureDescription: customFailureDescription
        ) { decoder in
            do {
                var container = try decoder.unkeyedContainer()
                var results: [[ValidatorResult]] = []
                
                while !container.isAtEnd {
                    var validations = Validations()
                    factory(container.currentIndex, &validations)
                    try results.append(validations.validate(container.superDecoder()).results)
                }
                return ValidatorResults.NestedEach(results: results)
            } catch {
                return ValidatorResults.Codable(error: error)
            }
        }
    }
    
    init(key: BasicCodingKey, result: ValidatorResult, customFailureDescription: String?) {
        self.init(key: key, valuelessKeyBehavior: .ignore, customFailureDescription: customFailureDescription) { _ in result }
    }
    
    init(
        key: BasicCodingKey,
        valuelessKeyBehavior: ValuelessKeyBehavior,
        customFailureDescription: String?,
        run: @escaping @Sendable (Decoder) -> ValidatorResult
    ) {
        self.key = key
        self.valuelessKeyBehavior = valuelessKeyBehavior
        self.customFailureDescription = customFailureDescription
        self.run = run
    }
}

public struct ValidationResult: Sendable {
    public let key: BasicCodingKey
    public let result: ValidatorResult
    public let customFailureDescription: String?
    
    init(key: BasicCodingKey, result: ValidatorResult, customFailureDescription: String? = nil) {
        self.key = key
        self.result = result
        self.customFailureDescription = customFailureDescription
    }
}

extension ValidationResult: ValidatorResult {
    public var isFailure: Bool {
        self.result.isFailure
    }
    
    public var successDescription: String? {
        self.result.successDescription
            .map { "\(self.key) \($0)" }
    }
    
    public var failureDescription: String? {
        self.result.failureDescription
            .map { "\(self.key) \($0)" }
    }
}
