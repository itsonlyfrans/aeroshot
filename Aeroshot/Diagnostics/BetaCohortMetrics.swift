import Foundation

nonisolated struct BetaCohortSnapshot: Codable, Equatable, Sendable {
    let sessionCount: Int
    let crashFreeSessionRate: Double?
    let taskSuccessRate: Double?
    let medianTimeToOutputBucket: Int64?
    let exportFailureRate: Double?
    let projectRecoveryRate: Double?
}

/// Computes the Phase 7 beta scorecard from consented, content-free events.
/// It deliberately accepts no participant identifiers, paths, filenames, or captured content.
nonisolated enum BetaCohortMetrics {
    static func snapshot(events: [DiagnosticEvent]) -> BetaCohortSnapshot {
        let application = events.filter { $0.subsystem == .application }
        let sessions = application.filter { $0.outcome == .started }.count
        let cleanSessions = application.filter { $0.outcome == .succeeded }.count

        let taskEvents = events.filter { $0.subsystem != .application && [.succeeded, .failed, .cancelled].contains($0.outcome) }
        let successfulTasks = taskEvents.filter { $0.outcome == .succeeded }.count
        let durationBuckets = events.compactMap { $0.outcome == .succeeded ? $0.counters["duration_bucket"] : nil }.sorted()

        let exports = events.filter { $0.subsystem == .mediaExport && [.succeeded, .failed].contains($0.outcome) }
        let exportFailures = exports.filter { $0.outcome == .failed }.count
        let recoveries = events.filter { $0.subsystem == .project && [.recovered, .failed].contains($0.outcome) }
        let recovered = recoveries.filter { $0.outcome == .recovered }.count

        return BetaCohortSnapshot(
            sessionCount: sessions,
            crashFreeSessionRate: ratio(cleanSessions, sessions),
            taskSuccessRate: ratio(successfulTasks, taskEvents.count),
            medianTimeToOutputBucket: durationBuckets.isEmpty ? nil : durationBuckets[(durationBuckets.count - 1) / 2],
            exportFailureRate: ratio(exportFailures, exports.count),
            projectRecoveryRate: ratio(recovered, recoveries.count)
        )
    }

    private static func ratio(_ numerator: Int, _ denominator: Int) -> Double? {
        denominator > 0 ? Double(numerator) / Double(denominator) : nil
    }
}
