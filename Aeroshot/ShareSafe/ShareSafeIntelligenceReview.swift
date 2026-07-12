#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
@Generable
struct ShareSafeIntelligenceFinding: Sendable {
    @Guide(description: "Zero-based index of the OCR line that contains sensitive information.")
    var lineIndex: Int

    @Guide(description: "Category of the sensitive content. Exactly one of: secret, credential, email, phone, address, payment, health, name, id, other.")
    var category: String

    @Guide(description: "A few words explaining why this line is sensitive.")
    var reason: String
}

@available(macOS 26.0, *)
@Generable
struct ShareSafeIntelligenceResult: Sendable {
    @Guide(description: "Findings for OCR lines that contain sensitive or private information worth redacting before sharing. Empty when nothing is sensitive.")
    var findings: [ShareSafeIntelligenceFinding]
}

@available(macOS 26.0, *)
enum ShareSafeIntelligenceReview {
    private static let maxLines = 120

    @MainActor private static var nextSession = makeSession()

    static var isModelAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    static var availabilitySubtitle: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "Adds on-device semantic detection beyond pattern matching"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Enable Apple Intelligence in System Settings"
        case .unavailable(.deviceNotEligible):
            return "Not available on this Mac"
        case .unavailable(.modelNotReady):
            return "Apple Intelligence model is still downloading"
        case .unavailable:
            return "Apple Intelligence is not available"
        }
    }

    @MainActor
    static func prewarm() {
        guard isModelAvailable else { return }
        nextSession.prewarm()
    }

    @MainActor
    static func reviewFindings(lineTexts: [String]) async throws -> [SmartScanFinding] {
        guard isModelAvailable, !lineTexts.isEmpty else { return [] }

        let capped = Array(lineTexts.prefix(maxLines))
        let numbered = capped.enumerated()
            .map { "\($0.offset): \($0.element)" }
            .joined(separator: "\n")

        let session = nextSession
        nextSession = makeSession()

        let response = try await session.respond(
            to: """
            Review these OCR lines and return findings for lines that should be redacted:

            \(numbered)
            """,
            generating: ShareSafeIntelligenceResult.self
        )

        return response.content.findings
            .filter { $0.lineIndex >= 0 && $0.lineIndex < capped.count }
            .map { SmartScanFinding(lineIndex: $0.lineIndex, category: SmartScanCategory(label: $0.category)) }
    }

    @MainActor
    private static func makeSession() -> LanguageModelSession {
        LanguageModelSession {
            """
            You help redact screenshots before sharing. Given numbered OCR lines, return findings only for lines \
            that contain actual sensitive values, each with a category:
            - secret: API keys, tokens, private keys, high-entropy credentials
            - credential: passwords, connection strings with embedded logins
            - email: email addresses
            - phone: phone numbers
            - address: postal addresses or fragments of one
            - payment: card numbers, IBANs, account numbers
            - health: medical or health information
            - name: a person's name with no other sensitive data on the line
            - id: internal record, invoice, or account identifiers
            - other: anything else private (door codes, internal hostnames, salaries)

            Do NOT flag:
            - Field labels alone (Name, Email, Phone, Address)
            - Record numbers, invoice IDs, or UI section headers that are not private
            - Generic app chrome, menu items, buttons, or version numbers

            Prefer the smallest set of findings possible. Supplement pattern matching — do not flag every row in a form.
            """
        }
    }
}
#endif
