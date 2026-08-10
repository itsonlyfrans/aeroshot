import Foundation
import Testing

struct CapturePermissionUITestGuardTests {
    @Test func capturePermissionGuardWaitsForTheDenialToast() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appending(path: "AeroshotUITests/AeroshotUITests.swift"))
        let helper = try #require(source.components(separatedBy: "private func permissionBlockIsVisible() -> Bool {").dropFirst().first)

        #expect(helper.contains("app.staticTexts.matching("))
        #expect(helper.contains("label CONTAINS[c] 'Screen Recording permission'"))
        #expect(!helper.contains("app.windows.count > 0"))
    }
}
