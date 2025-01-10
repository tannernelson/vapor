import Foundation

extension Validator where T == String {
    /// Validates that all characters in a `String` are ASCII (bytes 0..<128).
    public static var ascii: Validator {
        .characterSet(.ascii)
    }

    /// Validates that all characters in a `String` are alphanumeric (a-z,A-Z,0-9).
    public static var alphanumeric: Validator {
        .characterSet(.alphanumerics)
    }

    /// Validates that all characters in a `String` are in the supplied `CharacterSet`.
    public static func characterSet(_ characterSet: Foundation.CharacterSet) -> Validator {
        .init {
            ValidatorResults.CharacterSet(string: $0, characterSet: characterSet)
        }
    }
}

extension ValidatorResults {
    /// `ValidatorResult` of a validator that validates that a `String` contains characters in a given `CharacterSet`.
    public struct CharacterSet {
        /// The validated string.
        public let string: String
        
        /// The set of characters the input is allowed to contain.
        public let characterSet: Foundation.CharacterSet

        /// On validation failure, the first substring of the input with characters not contained in `characterSet`.
        var invalidRange: Swift.Range<String.Index>? {
            self.string.rangeOfCharacter(from: self.characterSet.inverted)
        }
        
        public var invalidSlice: String? {
            self.invalidRange.flatMap { self.string[$0] }
                .map { .init($0 )}
        }
        
        var allowedCharacterString: String {
            self.characterSet.traits.joined(separator: ", ")
        }
    }
}

extension ValidatorResults.CharacterSet: ValidatorResult {
    public var isFailure: Bool {
        self.invalidRange != nil
    }
    
    public var successDescription: String? {
        "contains only \(self.allowedCharacterString)"
    }
    
    public var failureDescription: String? {
        self.invalidSlice.map {
            "contains '\($0)' (allowed: \(self.allowedCharacterString))"
        }
    }
}

extension Validator where T == [String] {
    /// Validates that all characters in elements of a `[String]` are ASCII (bytes 0..<128).
    public static var ascii: Validator {
        .characterSet(.ascii)
    }

    /// Validates that all characters in elements of a `[String]` are alphanumeric (a-z,A-Z,0-9).
    public static var alphanumeric: Validator {
        .characterSet(.alphanumerics)
    }

    /// Validates that all characters in elements of a `[String]` are in the supplied `CharacterSet`.
    public static func characterSet(_ characterSet: Foundation.CharacterSet) -> Validator {
        .init {
            ValidatorResults.CollectionCharacterSet(strings: $0, characterSet: characterSet)
        }
    }
}

extension ValidatorResults {
    /// `ValidatorResult` of a validator that validates that all elements of a `[String]` contain characters in a given `CharacterSet`.
    public struct CollectionCharacterSet {
        /// The validated string.
        public let strings: [String]
        
        /// The set of characters the input is allowed to contain.
        public let characterSet: Foundation.CharacterSet

        /// On validation failure, the first substring of the input with characters not contained in `characterSet`.
        var invalidRanges: [(Int, Swift.Range<String.Index>)?] {
            return self.strings.enumerated().compactMap {
                if let range = $1.rangeOfCharacter(from: self.characterSet.inverted) {
                    return ($0, range)
                }
                return nil
            }
        }
        
        var allowedCharacterString: String {
            self.characterSet.traits.joined(separator: ", ")
        }
    }
}

extension ValidatorResults.CollectionCharacterSet: ValidatorResult {
    public var isFailure: Bool {
        !self.invalidRanges.isEmpty
    }
    
    public var successDescription: String? {
        "contains only \(self.allowedCharacterString)"
    }
    
    public var failureDescription: String? {
        let disallowedCharacters = self.invalidRanges.compactMap { $0 }
            .map { (invalidSlice) in
                "string at index \(invalidSlice.0) contains '\(String(self.strings[invalidSlice.0][invalidSlice.1]))'"
            }
        return "\(disallowedCharacters.joined(separator: ", ")) (allowed: \(self.allowedCharacterString))"
    }
}

/// Unions two character sets.
///
///     .characterSet(.alphanumerics + .whitespaces)
///
public func +(lhs: CharacterSet, rhs: CharacterSet) -> CharacterSet {
    lhs.union(rhs)
}

private extension CharacterSet {
    /// ASCII (byte 0..<128) character set.
    static var ascii: CharacterSet {
        .init((0..<128).map(Unicode.Scalar.init))
    }

    /// Returns an array of strings describing the contents of this `CharacterSet`.
    var traits: [String] {
        var desc: [String] = []
        if isSuperset(of: .newlines) {
            desc.append("newlines")
        }
        if isSuperset(of: .whitespaces) {
            desc.append("whitespace")
        }
        if isSuperset(of: .ascii) {
            desc.append("ASCII")
        }
        if isSuperset(of: .capitalizedLetters) {
            desc.append("A-Z")
        }
        if isSuperset(of: .lowercaseLetters) {
            desc.append("a-z")
        }
        if isSuperset(of: .decimalDigits) {
            desc.append("0-9")
        }
        return desc
    }
}
