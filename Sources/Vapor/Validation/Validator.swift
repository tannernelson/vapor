public struct Validator<T: Decodable & Sendable>: Sendable {
    public let validate: @Sendable (_ data: T) -> ValidatorResult
    public init(validate: @Sendable @escaping (_ data: T) -> ValidatorResult) {
        self.validate = validate
    }
}
