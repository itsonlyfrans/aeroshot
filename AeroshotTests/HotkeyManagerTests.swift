import AppKit
import Testing
@testable import Aeroshot

@Suite(.serialized)
@MainActor
struct HotkeyManagerTests {
    @Test func shortcutRecordingSuspensionDoesNotOverwriteTheUserPauseState() {
        let manager = HotkeyManager.shared
        let original = manager.isUserEnabled
        defer { manager.setEnabled(original) }

        manager.setEnabled(true)
        manager.suspend()
        #expect(!manager.isEnabled)

        manager.setEnabled(false)
        manager.resume()
        #expect(!manager.isEnabled)
        #expect(!manager.isUserEnabled)
    }

    @Test func dismantlingAnActiveRecorderRestoresHotkeys() {
        let manager = HotkeyManager.shared
        let original = manager.isUserEnabled
        defer { manager.setEnabled(original) }

        manager.setEnabled(true)
        let field = HotkeyRecorderView.RecorderField()
        field.performClick(nil)
        #expect(!manager.isEnabled)

        withExtendedLifetime(field) {
            HotkeyRecorderView.dismantleNSView(field, coordinator: ())
            #expect(manager.isEnabled)
        }
    }

    @Test func cancellingShortcutRecordingClearsTheValidationError() {
        let field = HotkeyRecorderView.RecorderField()
        var errorMessage: String?
        field.onValidationError = { errorMessage = $0 }
        field.performClick(nil)
        errorMessage = "Already used"

        field.performClick(nil)

        #expect(errorMessage == nil)
    }
}
