import XCTest
@testable import Aeroshot

@MainActor
final class OperationsPolicyTests: XCTestCase {
    func testTelemetryAndCrashReportingDefaultOff() {
        let policy = TelemetryPolicy()
        XCTAssertFalse(policy.permitsAnalytics)
        XCTAssertFalse(policy.permitsCrashReports)
        XCTAssertNil(policy.sanitizedEvent(.init(name: "app_launch", properties: [:])))
    }

    func testTelemetryAllowsOnlyAggregateContentFreeFields() {
        let policy = TelemetryPolicy(analyticsConsent: .enabled)
        let event = policy.sanitizedEvent(.init(name: "export_completed", properties: [
            "format": "mp4",
            "result": "success",
            "path": "/Users/example/Secret.mov",
            "text": "captured document contents",
            "operation": "https://example.invalid/track"
        ]))

        XCTAssertEqual(event, .init(name: "export_completed", properties: [
            "format": "mp4", "result": "success"
        ]))
        XCTAssertNil(policy.sanitizedEvent(.init(name: "arbitrary_event", properties: [:])))
    }

    func testCoreOperationsIgnoreEntitlementState() {
        struct Provider: EntitlementProviding { let status: EntitlementStatus }

        for status in [EntitlementStatus.unknown, .unlicensed, .licensed(expiration: nil)] {
            let boundary = EntitlementBoundary(provider: Provider(status: status))
            XCTAssertTrue(CoreOperation.allCases.allSatisfy(boundary.permits))
        }
    }
}
