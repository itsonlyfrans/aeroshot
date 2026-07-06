import CoreGraphics
import Foundation

nonisolated enum ShareSafeLinePolicy {
    static let sensitiveFieldLabels: Set<String> = [
        "name", "email", "phone", "address", "mobile", "visa", "amex",
        "cardholder", "invoice", "billing", "backup email", "expiry", "ssn",
        "social security",
    ]

    private static let labelOnlyLines = sensitiveFieldLabels

    static func isSensitiveFieldLabel(_ text: String) -> Bool {
        labelOnlyLines.contains(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// Filters Apple Intelligence findings to avoid over-redacting labels, names, and UI chrome.
    /// Strong categories are accepted when the line plausibly matches the claimed category;
    /// weak categories fall back to the conservative pattern checks.
    static func filterSmartScanFindings(
        _ findings: [SmartScanFinding],
        lineTexts: [String],
        patternMatched: Set<Int>
    ) -> Set<Int> {
        var accepted = Set<Int>()
        for finding in findings {
            guard lineTexts.indices.contains(finding.lineIndex) else { continue }
            let text = lineTexts[finding.lineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !isSensitiveFieldLabel(text) else { continue }
            if patternMatched.contains(finding.lineIndex)
                || (finding.category.isStrong && categoryPlausible(finding.category, in: text))
                || shouldIncludeSmartScanLine(text) {
                accepted.insert(finding.lineIndex)
            }
        }
        return accepted
    }

    /// Enhanced scan (OpenAI privacy filter) tags individual tokens and is eager on log/UI text.
    /// Only accept lines pattern matching would also redact — the model supplements recall on
    /// those lines and weak-category corroboration (names), it does not define new redactions.
    static func filterPrivacyFilterFindings(
        _ findings: [SmartScanFinding],
        lineTexts: [String],
        patternMatched: Set<Int>
    ) -> Set<Int> {
        var accepted = Set<Int>()
        for finding in findings {
            guard lineTexts.indices.contains(finding.lineIndex) else { continue }
            let text = lineTexts[finding.lineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !isSensitiveFieldLabel(text) else { continue }
            if patternMatched.contains(finding.lineIndex) || shouldIncludeSmartScanLine(text) {
                accepted.insert(finding.lineIndex)
            }
        }
        return accepted
    }

    /// Light validation so a hallucinated category can't redact arbitrary UI text.
    static func categoryPlausible(_ category: SmartScanCategory, in text: String) -> Bool {
        switch category {
        case .email:
            return PIIDetector.containsEmailAddress(text)
        case .phone:
            // Digit counts are not enough: status lines like "ID 10234 · OK 20000 · build
            // 20250601" are digit-dense but contain no phone number. Require a real match.
            return PIIDetector.containsPhoneNumber(text)
        case .payment:
            return PIIDetector.containsLikelyPaymentCard(text)
        case .address:
            return PIIDetector.looksLikePhysicalAddress(text)
        case .secret:
            if !PIIDetector.sensitiveRanges(in: text).isEmpty { return true }
            return text.split(whereSeparator: \.isWhitespace).contains {
                PIIDetector.isLikelyHighEntropySecret(String($0))
            }
        case .credential:
            if !PIIDetector.sensitiveRanges(in: text).isEmpty { return true }
            let lower = text.lowercased()
            return lower.contains("password") || lower.contains("passwd")
                || lower.contains("secret") || lower.contains(" code")
                || lower.hasPrefix("code ") || lower.contains(" token")
                || lower.contains("bearer ") || lower.contains("postgres://")
                || lower.contains("mysql://")
        case .health:
            return false
        case .name, .id, .other:
            return false
        }
    }

    /// Medium-confidence lines are redacted only with corroboration: a bare "CA 94107"
    /// fragment next to a flagged line, or a name the AI flagged adjacent to flagged contact info.
    static func corroboratedMediumLines(
        lineTexts: [String],
        flagged: Set<Int>,
        aiFindings: [SmartScanFinding]
    ) -> Set<Int> {
        let aiNameIndices = Set(aiFindings.filter { $0.category == .name }.map(\.lineIndex))
        var added = Set<Int>()

        for (index, text) in lineTexts.enumerated() where !flagged.contains(index) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let adjacentFlagged = flagged.contains(index - 1) || flagged.contains(index + 1)
            guard adjacentFlagged else { continue }

            if isBareStateZipFragment(trimmed) {
                added.insert(index)
            } else if aiNameIndices.contains(index), isLikelyPersonNameOnly(trimmed) {
                added.insert(index)
            }
        }

        return added
    }

    static func isBareStateZipFragment(_ text: String) -> Bool {
        text.range(of: #"^[A-Z]{2}\s+\d{5}(?:-\d{4})?$"#, options: .regularExpression) != nil
    }

    /// Adds lines that look like OCR splits of an already-flagged sensitive value (e.g. address wrap).
    static func expandForContinuations(
        _ indices: Set<Int>,
        lineTexts: [String]
    ) -> Set<Int> {
        var expanded = indices

        for index in indices {
            guard index + 1 < lineTexts.count else { continue }
            let next = lineTexts[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !next.isEmpty else { continue }
            if looksLikeContinuation(of: lineTexts[index], nextLine: next) {
                expanded.insert(index + 1)
            }
        }

        for (index, text) in lineTexts.enumerated() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if PIIDetector.looksLikePhysicalAddress(trimmed) || PIIDetector.lineShouldBeRedacted(trimmed) {
                expanded.insert(index)
                continue
            }

            if trimmed.range(of: #"^[a-z]?,\s*[A-Z]{2}\s+\d{5}(?:-\d{4})?\b"#, options: .regularExpression) != nil {
                expanded.insert(index)
                if index > 0 {
                    expanded.insert(index - 1)
                }
            }
        }

        return expanded
    }

    /// Redact value lines that follow a standalone field label, e.g. label "Name" then "Jordan Alvarez".
    static func expandForLabeledFieldValues(
        _ indices: Set<Int>,
        lineTexts: [String]
    ) -> Set<Int> {
        var expanded = indices

        for (index, text) in lineTexts.enumerated() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if isSensitiveFieldLabel(trimmed), index + 1 < lineTexts.count {
                let next = lineTexts[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !next.isEmpty, !isSensitiveFieldLabel(next) {
                    expanded.insert(index + 1)
                }
            }
        }

        return expanded
    }

    /// Within a flagged OCR line, return only the observations that hold sensitive values — not field labels.
    static func redactableObservations(in group: [OCRTextObservation]) -> [OCRTextObservation] {
        guard !group.isEmpty else { return [] }
        let sorted = group.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        let lineText = sorted.map(\.text).joined(separator: " ")

        var redactable: [OCRTextObservation] = []

        if let valueStart = indexAfterLeadingFieldLabel(in: sorted, lineText: lineText) {
            redactable = Array(sorted[valueStart...]).filter {
                !isSensitiveFieldLabel($0.text)
            }
        }

        if redactable.isEmpty {
            redactable = sorted.filter {
                let text = $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return !text.isEmpty && !isSensitiveFieldLabel(text)
            }
            if redactable.isEmpty {
                redactable = sorted
            }
        }

        // Side-by-side columns merge into one OCR line; always include any observation
        // that pattern matching already flagged as sensitive regardless of label heuristics.
        let patternMatched = sorted.filter { !PIIDetector.sensitiveRanges(in: $0.text).isEmpty }
        if patternMatched.isEmpty {
            return redactable
        }

        func key(for observation: OCRTextObservation) -> String {
            "\(observation.text)|\(observation.boundingBox.minX)|\(observation.boundingBox.minY)"
        }

        var merged = redactable
        var mergedKeys = Set(merged.map(key(for:)))
        for observation in patternMatched where !mergedKeys.contains(key(for: observation)) {
            merged.append(observation)
            mergedKeys.insert(key(for: observation))
        }
        return merged
    }

    private static func indexAfterLeadingFieldLabel(
        in sorted: [OCRTextObservation],
        lineText: String
    ) -> Int? {
        let lower = lineText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        for label in labelOnlyLines.sorted(by: { $0.count > $1.count }) {
            guard lower.hasPrefix(label + " ") || lower.hasPrefix(label + ":") else { continue }

            let labelWords = label.split(separator: " ").map(String.init)
            var observationIndex = 0
            var wordIndex = 0

            while observationIndex < sorted.count, wordIndex < labelWords.count {
                let observationText = sorted[observationIndex].text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()

                if observationText == label {
                    observationIndex += 1
                    wordIndex = labelWords.count
                    break
                }

                if observationText == labelWords[wordIndex] {
                    wordIndex += 1
                    observationIndex += 1
                    continue
                }

                break
            }

            if wordIndex == labelWords.count, observationIndex < sorted.count {
                return observationIndex
            }
        }

        if sorted.count >= 2, isSensitiveFieldLabel(sorted[0].text) {
            return 1
        }

        return nil
    }

    static func shouldIncludeSmartScanLine(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if labelOnlyLines.contains(trimmed.lowercased()) { return false }

        if !PIIDetector.sensitiveRanges(in: trimmed).isEmpty { return true }
        if PIIDetector.lineShouldBeRedacted(trimmed) { return true }

        let lower = trimmed.lowercased()
        if lower.contains("postgres://") || lower.contains("mysql://") { return true }
        if lower.range(of: #"[a-z][a-z0-9+.-]*://[^\s/@:]+:[^\s@/]+@"#, options: .regularExpression) != nil {
            return true
        }
        if lower.contains("password") || lower.contains("secret") || lower.contains("api_key") { return true }
        if lower.contains("token=") || lower.hasPrefix("bearer ") { return true }

        // State + ZIP fragments often split across OCR lines (e.g. "d, CA 94107").
        // Require a comma so status copy like "Status OK 20000 requests" never matches.
        if trimmed.range(of: #",\s*[A-Z]{2}\s+\d{5}(?:-\d{4})?\b"#, options: .regularExpression) != nil {
            return true
        }
        if isBareStateZipFragment(trimmed) {
            return true
        }

        // Person name only — skip unless paired with contact info on the same line.
        if isLikelyPersonNameOnly(trimmed) { return false }

        return false
    }

    private static func looksLikeContinuation(of previousLine: String, nextLine: String) -> Bool {
        let previous = previousLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = nextLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !previous.isEmpty, !next.isEmpty else { return false }

        if PIIDetector.lineShouldBeRedacted(next) { return true }

        // Wrapped secret tail: a long key wraps and the overflow renders as a bare
        // fragment on the next visual line (e.g. "sk_test_51H…0000" → "001").
        if endsWithKeyLikeToken(previous), isBareTokenFragment(next) { return true }

        // Wrapped address tail: "Springfiel" → "d, CA 94107"
        if previous.hasSuffix(",") || previous.split(separator: " ").last.map({ $0.count <= 12 && !$0.contains("@") }) == true {
            if next.first?.isLowercase == true { return true }
            if next.range(of: #",\s*[A-Z]{2}\s+\d{5}"#, options: .regularExpression) != nil { return true }
        }

        return false
    }

    private static func endsWithKeyLikeToken(_ text: String) -> Bool {
        guard let last = text.split(whereSeparator: \.isWhitespace).last.map(String.init) else { return false }
        guard last.count >= 16, last.range(of: #"^[A-Za-z0-9+/=_.:-]+$"#, options: .regularExpression) != nil else {
            return false
        }
        return last.contains(where: \.isNumber) && last.contains(where: \.isLetter)
    }

    /// A short residue like "001" or "dp7dc" — never a Title-case word such as "Privacy",
    /// so adjacent UI copy is not swallowed by the continuation rule.
    private static func isBareTokenFragment(_ text: String) -> Bool {
        guard text.count <= 16,
              text.range(of: #"^[A-Za-z0-9+/=_.-]+$"#, options: .regularExpression) != nil else {
            return false
        }
        return text.contains(where: \.isNumber) || text == text.lowercased()
    }

    static func isLikelyPersonNameOnly(_ text: String) -> Bool {
        text.range(
            of: #"^[A-Z][a-z]+(?: [A-Z][a-z]+){0,2}$"#,
            options: .regularExpression
        ) != nil
    }
}
