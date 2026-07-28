import Foundation

nonisolated enum SmartScanCategory: String, Sendable {
    case secret
    case credential
    case email
    case phone
    case address
    case payment
    case health
    case name
    case id
    case other

    init(label: String) {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self = SmartScanCategory(rawValue: normalized) ?? .other
    }

    /// Maps openai/privacy-filter BIOES entity labels (e.g. "B-private_email") to our
    /// categories. account_number maps to the weak .id — the model tags invoice IDs and
    /// UI record numbers with it, and Luhn-valid cards are already caught by patterns.
    /// private_person, private_date, and private_url stay weak for the same reason:
    /// they only redact with corroboration from patterns or adjacent flagged lines.
    init(privacyFilterLabel: String) {
        let entity = privacyFilterLabel.split(separator: "-", maxSplits: 1).last.map(String.init) ?? privacyFilterLabel
        switch entity.lowercased() {
        case "secret": self = .secret
        case "private_email": self = .email
        case "private_phone": self = .phone
        case "private_address": self = .address
        case "private_person": self = .name
        case "account_number", "private_date", "private_url": self = .id
        default: self = .other
        }
    }

    var isStrong: Bool {
        switch self {
        case .secret, .credential, .email, .phone, .address, .payment, .health:
            return true
        case .name, .id, .other:
            return false
        }
    }
}

nonisolated struct SmartScanFinding: Sendable, Hashable {
    let lineIndex: Int
    let category: SmartScanCategory
}

nonisolated enum ShareSafeSmartScanError: Error, Equatable {
    case unavailable
}

enum ShareSafeSmartScanSupport {
    /// Whether the on-device Apple Intelligence model can run a smart scan right now.
    static var isModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return ShareSafeIntelligenceReview.isModelAvailable
        }
        #endif
        return false
    }

    /// Subtitle copy for the Smart scan toggle in Settings.
    static var settingsSubtitle: String {
        if #available(macOS 26.0, *) {
            #if canImport(FoundationModels)
            return ShareSafeIntelligenceReview.availabilitySubtitle
            #else
            return "Requires macOS 26 with Apple Intelligence"
            #endif
        }
        return "Requires macOS 26 with Apple Intelligence"
    }

    /// Starts loading the optional model while the user selects a capture region.
    @MainActor
    static func prewarm() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            ShareSafeIntelligenceReview.prewarm()
        }
        #endif
    }

    /// Runs the optional Apple Intelligence pass. A requested scan must never
    /// degrade into a clean result when the model is unavailable or fails.
    static func findings(lineTexts: [String]) async throws -> [SmartScanFinding] {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if ShareSafeIntelligenceReview.isModelAvailable {
                return try await ShareSafeIntelligenceReview.reviewFindings(lineTexts: lineTexts)
            }
        }
        #endif
        throw ShareSafeSmartScanError.unavailable
    }
}
