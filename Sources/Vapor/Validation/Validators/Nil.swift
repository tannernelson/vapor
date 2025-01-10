#warning("Fix")
//extension Validator where T: OptionalType {
//    /// Validates that the data is `nil`. Combine with the not-operator `!` to validate that the data is not `nil`.
//    public static var `nil`: Validator<T> { .init { ValidatorResults.Nil(isNil: $0.wrapped == nil) } }
//}
//
//extension ValidatorResults {
//    /// `ValidatorResult` of a validator that validates that the data is `nil`.
//    public struct Nil {
//        /// Input is `nil`.
//        public let isNil: Bool
//    }
//}
//
//extension ValidatorResults.Nil: ValidatorResult {
//    public var isFailure: Bool {
//        !self.isNil
//    }
//    
//    public var successDescription: String? {
//        switch self.isNil {
//        case true:
//            return "is not null"
//        case false:
//            return "is null"
//        }
//    }
//    
//    public var failureDescription: String? {
//        switch self.isNil {
//        case true:
//            return "is null"
//        case false:
//            return "is not null"
//        }
//    }
//}
