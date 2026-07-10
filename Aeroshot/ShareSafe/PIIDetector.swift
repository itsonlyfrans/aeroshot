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
nonisolated enum PIIDetector {
    private static let secretPatterns: [NSRegularExpression] = {
        let patterns = [
            #"\bsk_(live|test)_[a-zA-Z0-9]{8,}\b"#,
            #"\bAKIA[0-9A-Z]{16}\b"#,
            #"\bghp_[a-zA-Z0-9]{20,}\b"#,
            #"\bxox[baprs]-[a-zA-Z0-9-]{10,}\b"#,
            #"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#,
            #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
            #"\b[a-zA-Z][a-zA-Z0-9+.-]*://[^\s/@:]+:[^\s@/]+@\S+"#,
            #"(?i)\b(?:password|passwd|pwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|private[_-]?key)\s*[:=]\s*\S{4,}"#,
            #"(?i)\bBearer\s+[A-Za-z0-9._+/=-]{16,}"#,
            #"\bwhsec_[a-zA-Z0-9_]{16,}\b"#,
            #"\b\d{3}-\d{2}-\d{4}\b"#,
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

    /// US-style street + city/state/ZIP, tolerant of OCR spacing glitches.
    private static let physicalAddressPattern: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"\b\d{1,6}\s+[A-Za-z0-9][A-Za-z0-9\s.'-]{2,48}(?:\s*,\s*[A-Za-z][A-Za-z\s.'-]{1,40}){0,2}\s*,?\s*[A-Z]{2}\s+\d{5}(?:-\d{4})?\b"#,
            options: []
        )
    }()

    /// City + state + ZIP requires a comma so table cells like "ID 10234" or "OK 20000" never match.
    private static let cityStateZipPattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"\b[A-Za-z][A-Za-z.'\-]{2,}\s*,\s*[A-Z]{2}\s+\d{5}(?:-\d{4})?\b"#, options: [])
    }()

    /// Long alphanumeric runs that may be credentials regardless of vendor prefix.
    private static let tokenCandidatePattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"[A-Za-z0-9+=_\-]{20,}"#, options: [])
    }()

    private static let streetNumberLeadPattern: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"\b\d{1,6}\s+(?:[A-Za-z0-9][A-Za-z0-9\s.'-]{2,30}\s+){1,4}(?:St|Street|Ave|Avenue|Rd|Road|Dr|Drive|Ln|Lane|Blvd|Boulevard|Ter|Terrace|Way|Ct|Court|Pl|Place|Pkwy|Parkway|Cir|Circle|Hwy|Highway)\.?(\s|,|$)"#,
            options: [.caseInsensitive]
        )
    }()

    /// Contact-form labels with a value on the same OCR line, e.g. "Name Jordan Alvarez".
    /// The value must look value-like (Title Case word, digit, or @) so settings copy
    /// such as "Email notifications enabled" or "Phone: see settings" is not flagged.
    private static let labeledValuePattern: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"^(?i:Name|Address|Cardholder|Mobile|Phone|Email|Backup\s+email|SSN|Social\s+security)\b\s*[:.]?\s*(?:[A-Z][A-Za-z'’-]+|\S*[\d@]\S*)"#,
            options: []
        )
    }()

    private static let dataDetector: NSDataDetector? = {
        let types: NSTextCheckingResult.CheckingType = [.phoneNumber, .link, .address]
        return try? NSDataDetector(types: types.rawValue)
    }()

    /// Label prefix of a contact-form line, used to redact only the value portion.
    private static let fieldLabelPrefixPattern: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"^(?i:Name|Address|Cardholder|Mobile|Phone|Email|Backup\s+email|SSN|Social\s+security)\b\s*[:.]?\s*"#,
            options: []
        )
    }()

    /// `.env`-style assignment: `DATABASE_URL=…` or `DATABASE_URL: …`.
    private static let envAssignmentPattern: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"^[A-Z][A-Z0-9_]{1,48}\s*[:=]\s*\S"#,
            options: []
        )
    }()

    // Detection runs several policy passes over the same OCR lines; cache per line text.
    private static let rangeCacheLock = NSLock()
    nonisolated(unsafe) private static var rangeCache: [String: [NSRange]] = [:]
    private static let rangeCacheLimit = 4096

    /// Ranges of sensitive content within `text`, in ascending order.
    static func sensitiveRanges(in text: String) -> [Range<String.Index>] {
        guard !text.isEmpty else { return [] }

        rangeCacheLock.lock()
        let cached = rangeCache[text]
        rangeCacheLock.unlock()
        if let cached {
            return cached.compactMap { Range($0, in: text) }
        }

        let ranges = computeSensitiveRanges(in: text)

        rangeCacheLock.lock()
        if rangeCache.count >= rangeCacheLimit { rangeCache.removeAll(keepingCapacity: true) }
        rangeCache[text] = ranges.map { NSRange($0, in: text) }
        rangeCacheLock.unlock()

        return ranges
    }

    private static func computeSensitiveRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []

        if let detector = dataDetector {
            let nsRange = NSRange(text.startIndex..., in: text)
            detector.enumerateMatches(in: text, options: [], range: nsRange) { result, _, _ in
                guard let result, let range = Range(result.range, in: text) else { return }
                switch result.resultType {
                case .phoneNumber:
                    let digits = String(text[range]).filter(\.isNumber)
                    if digits.count >= 7, phoneContextAllows(text, matchRange: range), !isTrivialDigitSequence(digits) {
                        ranges.append(range)
                    }
                case .address:
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
        if let physicalAddressPattern {
            ranges.append(contentsOf: matches(for: physicalAddressPattern, in: text))
        }
        if let streetNumberLeadPattern {
            ranges.append(contentsOf: matches(for: streetNumberLeadPattern, in: text))
        }
        if let cityStateZipPattern {
            ranges.append(contentsOf: matches(for: cityStateZipPattern, in: text))
        }
        if let tokenCandidatePattern {
            ranges.append(contentsOf: matches(for: tokenCandidatePattern, in: text).filter { isLikelyHighEntropySecret(String(text[$0])) })
        }

        return mergeOverlapping(ranges.sorted { $0.lowerBound < $1.lowerBound })
    }

    /// Sensitive substrings plus env-value / labeled-field spans for partial redaction.
    static func redactionRanges(in text: String) -> [Range<String.Index>] {
        // An `.env` assignment is sensitive by its value, never its key. Some
        // broad system detectors classify the entire assignment as a URL/link;
        // honoring that range would unnecessarily hide useful variable names.
        if let envValue = envAssignmentValueRange(in: text) {
            return [envValue]
        }
        var ranges = sensitiveRanges(in: text)
        if ranges.isEmpty, let valueRange = labeledFieldValueRange(in: text) {
            ranges = [valueRange]
        }
        return ranges
    }

    /// Whether an OCR line (possibly merged from adjacent tokens) should be fully redacted.
    static func lineShouldBeRedacted(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if !sensitiveRanges(in: trimmed).isEmpty { return true }
        if emailPrefixPattern?.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return true
        }
        if labeledValuePattern?.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return true
        }
        if looksLikePhysicalAddress(trimmed) { return true }
        return false
    }

    /// Value portion of a `.env`-style assignment line, e.g. the URL in `DATABASE_URL=postgres://…`.
    static func envAssignmentValueRange(in text: String) -> Range<String.Index>? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard envAssignmentPattern?.firstMatch(
            in: trimmed,
            options: [],
            range: NSRange(trimmed.startIndex..., in: trimmed)
        ) != nil else { return nil }

        guard let separator = trimmed.firstIndex(where: { $0 == "=" || $0 == ":" }) else { return nil }
        var start = trimmed.index(after: separator)
        while start < trimmed.endIndex, trimmed[start].isWhitespace {
            start = trimmed.index(after: start)
        }
        guard start < trimmed.endIndex else { return nil }
        return start..<trimmed.endIndex
    }

    /// Value portion of a labeled contact-form line, e.g. "Jordan Alvarez" in "Name Jordan Alvarez".
    /// Only returned when the line matches the labeled-value shape (value-like content after the label).
    static func labeledFieldValueRange(in text: String) -> Range<String.Index>? {
        let nsRange = NSRange(text.startIndex..., in: text)
        guard labeledValuePattern?.firstMatch(in: text, options: [], range: nsRange) != nil,
              let prefixMatch = fieldLabelPrefixPattern?.firstMatch(in: text, options: [], range: nsRange),
              let prefixRange = Range(prefixMatch.range, in: text),
              prefixRange.upperBound < text.endIndex
        else { return nil }
        return prefixRange.upperBound..<text.endIndex
    }

    /// Strict corroboration checks for AI scan findings — a claimed category must be
    /// backed by an actual detector match so a hallucination can't redact UI text.
    static func containsPhoneNumber(_ text: String) -> Bool {
        guard let detector = dataDetector else { return false }
        let nsRange = NSRange(text.startIndex..., in: text)
        var found = false
        detector.enumerateMatches(in: text, options: [], range: nsRange) { result, _, stop in
            guard let result, result.resultType == .phoneNumber,
                  let range = Range(result.range, in: text) else { return }
            let digits = String(text[range]).filter(\.isNumber)
            if digits.count >= 7, phoneContextAllows(text, matchRange: range), !isTrivialDigitSequence(digits) {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    static func containsLikelyPaymentCard(_ text: String) -> Bool {
        guard let paymentCardPattern else { return false }
        return matches(for: paymentCardPattern, in: text).contains { isLikelyPaymentCard(String(text[$0])) }
    }

    static func containsEmailAddress(_ text: String) -> Bool {
        guard let emailPrefixPattern else { return false }
        return emailPrefixPattern.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func looksLikePhysicalAddress(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if physicalAddressPattern?.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return true
        }
        if streetNumberLeadPattern?.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return true
        }
        // Wrapped address head without state/ZIP yet, e.g. "742 Evergreen Terrace, Springfiel"
        if trimmed.range(of: #"^\d{1,6}\s+[A-Za-z0-9].*,\s*[A-Za-z]"#, options: .regularExpression) != nil {
            return true
        }
        // Wrapped address tail, e.g. "d, CA 94107"
        if trimmed.range(of: #"^[a-z]?,\s*[A-Z]{2}\s+\d{5}(?:-\d{4})?\b"#, options: .regularExpression) != nil {
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
        guard !isTrivialDigitSequence(digits) else { return false }
        return luhnCheck(digits)
    }

    /// All-identical or strictly sequential digits are UI placeholders, not real cards,
    /// even when they pass Luhn (e.g. "0000 0000 0000 0000").
    private static func isTrivialDigitSequence(_ digits: String) -> Bool {
        guard let first = digits.first else { return true }
        if digits.allSatisfy({ $0 == first }) { return true }
        let values = digits.compactMap(\.wholeNumberValue)
        let ascending = zip(values, values.dropFirst()).allSatisfy { ($0 + 1) % 10 == $1 }
        let descending = zip(values, values.dropFirst()).allSatisfy { ($0 + 9) % 10 == $1 }
        return ascending || descending
    }

    /// NSDataDetector is eager on number columns; skip phone matches whose preceding
    /// token marks them as builds, IDs, ports, or references.
    private static let phoneContextBlockers: Set<String> = [
        "v", "ver", "version", "build", "id", "ref", "port", "error", "code",
        "seq", "order", "ticket", "case", "issue", "pr", "sha", "commit",
    ]

    private static func phoneContextAllows(_ text: String, matchRange: Range<String.Index>) -> Bool {
        let prefix = text[..<matchRange.lowerBound]
        let words = prefix.split { $0.isWhitespace || $0 == ":" || $0 == "#" || $0 == "=" }
        guard let last = words.last else { return true }
        return !phoneContextBlockers.contains(String(last).lowercased())
    }

    /// Entropy-based catch-all for credentials without a known vendor prefix
    /// (how gitleaks/trufflehog reach recall on unknown token formats).
    static func isLikelyHighEntropySecret(_ token: String) -> Bool {
        guard token.count >= 20 else { return false }
        guard token.contains(where: \.isNumber), token.contains(where: \.isLetter) else { return false }
        // Git SHAs and UUIDs are hex, common in dev screenshots, and not secrets.
        if token.lowercased().allSatisfy({ "0123456789abcdef-".contains($0) }) { return false }
        return shannonEntropy(token) >= 4.0
    }

    private static func shannonEntropy(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        var counts: [Character: Int] = [:]
        for character in text {
            counts[character, default: 0] += 1
        }
        let length = Double(text.count)
        return counts.values.reduce(0) { entropy, count in
            let p = Double(count) / length
            return entropy - p * log2(p)
        }
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
