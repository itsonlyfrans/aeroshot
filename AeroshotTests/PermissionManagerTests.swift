import Security
import Testing
@testable import Aeroshot

struct PermissionManagerTests {
    @Test func appSignatureAllowsRecordingDevices() throws {
        let task = try #require(SecTaskCreateFromSelf(nil))
        for key in ["com.apple.security.device.audio-input", "com.apple.security.device.camera"] {
            let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil)
            #expect(value as? Bool == true)
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
}
