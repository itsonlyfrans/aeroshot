import Foundation

enum PIICategory: String, Sendable, CaseIterable {
    case email
    case phone
    case address
    case link
    case paymentCard
    case secret
}

/// Finds sensitive substrings in text for Share Safe redaction.
enum PIIDetector {
    private static let secretPatterns: [NSRegularExpression] = {
        let patterns = [
            #"\bsk_(live|test)_[a-zA-Z0-9]{8,}\b"#,
            #"\bAKIA[0-9A-Z]{16}\b"#,
            #"\bghp_[a-zA-Z0-9]{20,}\b"#,
            #"\bxox[baprs]-[a-zA-Z0-9-]{10,}\b"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()

    private static let paymentCardPattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"\b(?:\d[ -]?){13,19}\b"#, options: [])
    }()

    private static let emailPattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"[A-Z0-9._%+-]+@[A-Z0-9._%-]+(?:\.[A-Z0-9._%-]+)*"#, options: [.caseInsensitive])
    }()

    private static let emailPrefixPattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"[A-Z0-9._%+-]+@[A-Z0-9._%-]+"#, options: [.caseInsensitive])
    }()

    private static let dataDetector: NSDataDetector? = {
        let types: NSTextCheckingResult.CheckingType = [.phoneNumber, .link, .address]
        return try? NSDataDetector(types: types.rawValue)
    }()

    /// Ranges of sensitive content within `text`, in ascending order.
    static func sensitiveRanges(in text: String) -> [Range<String.Index>] {
        guard !text.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []

        if let detector = dataDetector {
            let nsRange = NSRange(text.startIndex..., in: text)
            detector.enumerateMatches(in: text, options: [], range: nsRange) { result, _, _ in
                guard let result, let range = Range(result.range, in: text) else { return }
                switch result.resultType {
                case .phoneNumber, .address:
                    ranges.append(range)
                case .link:
                    let matched = String(text[range])
                    if matched.contains("@") || matched.lowercased().hasPrefix("mailto:") {
                        ranges.append(range)
                    }
                default:
                    break
                }
            }
        }

        if let emailPattern {
            ranges.append(contentsOf: matches(for: emailPattern, in: text))
        }
        if let paymentCardPattern {
            ranges.append(contentsOf: matches(for: paymentCardPattern, in: text).filter { isLikelyPaymentCard(String(text[$0])) })
        }
        for pattern in secretPatterns {
            ranges.append(contentsOf: matches(for: pattern, in: text))
        }

        return mergeOverlapping(ranges.sorted { $0.lowerBound < $1.lowerBound })
    }

    /// Whether an OCR line (possibly merged from adjacent tokens) should be fully redacted.
    static func lineShouldBeRedacted(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if !sensitiveRanges(in: trimmed).isEmpty { return true }
        if emailPrefixPattern?.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return true
        }
        return false
    }

    private static func matches(for regex: NSRegularExpression, in text: String) -> [Range<String.Index>] {
        let nsRange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: nsRange).compactMap { Range($0.range, in: text) }
    }

    private static func isLikelyPaymentCard(_ value: String) -> Bool {
        let digits = value.filter(\.isNumber)
        guard (13...19).contains(digits.count) else { return false }
        return luhnCheck(digits)
    }

    private static func luhnCheck(_ digits: String) -> Bool {
        var sum = 0
        let reversed = digits.reversed().map { Int(String($0)) ?? 0 }
        for (index, digit) in reversed.enumerated() {
            if index.isMultiple(of: 2) {
                sum += digit
            } else {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            }
        }
        return sum.isMultiple(of: 10)
    }

    private static func mergeOverlapping(_ ranges: [Range<String.Index>]) -> [Range<String.Index>] {
        guard var current = ranges.first else { return [] }
        var merged: [Range<String.Index>] = []
        for range in ranges.dropFirst() {
            if range.lowerBound <= current.upperBound {
                current = current.lowerBound..<max(current.upperBound, range.upperBound)
            } else {
                merged.append(current)
                current = range
            }
        }
        merged.append(current)
        return merged
    }
}
