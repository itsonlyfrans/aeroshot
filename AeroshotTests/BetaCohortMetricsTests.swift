import Foundation
import Testing
@testable import Aeroshot

struct BetaCohortMetricsTests {
    @Test func scorecardUsesOnlyBoundedContentFreeEvents() {
        let events: [DiagnosticEvent] = [
            .init(subsystem: .application, outcome: .started),
            .init(subsystem: .application, outcome: .succeeded),
            .init(subsystem: .recording, outcome: .succeeded, counters: ["duration_bucket": 2]),
            .init(subsystem: .mediaExport, outcome: .failed, counters: ["duration_bucket": 9]),
            .init(subsystem: .mediaExport, outcome: .succeeded, counters: ["duration_bucket": 4]),
            .init(subsystem: .project, outcome: .recovered),
            .init(subsystem: .project, outcome: .failed),
        ]
        let snapshot = BetaCohortMetrics.snapshot(events: events)
        #expect(snapshot.sessionCount == 1)
        #expect(snapshot.crashFreeSessionRate == 1)
        #expect(snapshot.taskSuccessRate == 0.5)
        #expect(snapshot.medianTimeToOutputBucket == 2)
        #expect(snapshot.exportFailureRate == 0.5)
        #expect(snapshot.projectRecoveryRate == 0.5)
    }

    @Test func absentDenominatorsRemainUnknownInsteadOfPerfect() {
        let snapshot = BetaCohortMetrics.snapshot(events: [])
        #expect(snapshot.crashFreeSessionRate == nil)
        #expect(snapshot.taskSuccessRate == nil)
        #expect(snapshot.exportFailureRate == nil)
        #expect(snapshot.projectRecoveryRate == nil)
    }
}
