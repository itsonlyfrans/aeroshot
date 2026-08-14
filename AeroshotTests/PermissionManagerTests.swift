import Foundation
import Testing
@testable import Aeroshot

struct PermissionManagerTests {
    @Test func configuredEntitlementsAllowRecordingDevices() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appending(path: "Aeroshot/Aeroshot.entitlements"))
        let entitlements = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        for key in ["com.apple.security.device.audio-input", "com.apple.security.device.camera"] {
            #expect(entitlements[key] as? Bool == true)
        }
    }

    @MainActor
    @Test func overviewIncludesRecordingPermissions() {
        #expect(SettingsPermissions.totalCount == 4)
    }

    @MainActor
    @Test func captureCheckDoesNotRequestMissingPermission() async {
        var checks = 0
        let manager = PermissionManager {
            checks += 1
            return false
        }

        #expect(await !manager.ensurePermission())
        #expect(checks == 1)
        #expect(!manager.hasPermission)
    }

    @Test func successfulCaptureCheckDoesNotEnumerateScreenContent() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appending(path: "Aeroshot/Capture/PermissionManager.swift"))

        #expect(!source.contains("SCShareableContent"))
    }
}
