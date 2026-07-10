import Foundation

nonisolated enum DiagnosticSubsystem: String, Codable, CaseIterable, Sendable {
    case project, recording, mediaExport, gif, library, automation, application
}

nonisolated enum DiagnosticOutcome: String, Codable, CaseIterable, Sendable {
    case started, succeeded, cancelled, recovered, rejected, failed
}

/// A content-free event. Callers can report bounded counters and flags, but
/// cannot attach arbitrary strings, URLs, paths, titles, OCR, pixels, or input
/// events by construction.
nonisolated struct DiagnosticEvent: Codable, Equatable, Sendable {
    let timestamp: Date
    let subsystem: DiagnosticSubsystem
    let outcome: DiagnosticOutcome
    let counters: [String: Int64]
    let flags: [String: Bool]

    init(
        timestamp: Date = Date(),
        subsystem: DiagnosticSubsystem,
        outcome: DiagnosticOutcome,
        counters: [String: Int64] = [:],
        flags: [String: Bool] = [:]
    ) {
        self.timestamp = timestamp
        self.subsystem = subsystem
        self.outcome = outcome
        self.counters = DiagnosticSanitizer.allowedCounters(counters)
        self.flags = DiagnosticSanitizer.allowedFlags(flags)
    }
}

nonisolated enum DiagnosticSanitizer {
    private static let counterKeys: Set<String> = [
        "attempt_count", "duration_bucket", "generation", "item_count",
        "retry_count", "schema_version"
    ]
    private static let flagKeys: Set<String> = [
        "cache_rebuilt", "prior_data_retained", "recovery_available"
    ]

    static func allowedCounters(_ values: [String: Int64]) -> [String: Int64] {
        values.filter { counterKeys.contains($0.key) }
    }

    static func allowedFlags(_ values: [String: Bool]) -> [String: Bool] {
        values.filter { flagKeys.contains($0.key) }
    }

    /// Sanitizes an untrusted metadata dictionary at an integration boundary.
    /// String and binary values are never copied, even under an allowed key.
    static func sanitize(_ values: [String: Any]) -> (counters: [String: Int64], flags: [String: Bool]) {
        var counters: [String: Int64] = [:]
        var flags: [String: Bool] = [:]
        for (key, value) in values {
            if counterKeys.contains(key), let number = value as? NSNumber,
               CFGetTypeID(number) != CFBooleanGetTypeID() {
                counters[key] = number.int64Value
            } else if flagKeys.contains(key), let flag = value as? Bool {
                flags[key] = flag
            }
        }
        return (counters, flags)
    }
}
