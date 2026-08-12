import AppKit
import Testing
@testable import Aeroshot

@Suite(.serialized)
@MainActor
struct HotkeyManagerTests {
    @Test func suspendPreservesThePriorEnabledStateForShortcutRecording() {
        let manager = HotkeyManager.shared
        let original = manager.isEnabled
        defer { manager.setEnabled(original) }

        manager.setEnabled(false)
        let disabledState = manager.suspend()
        manager.setEnabled(disabledState)
        #expect(!manager.isEnabled)

        manager.setEnabled(true)
        let enabledState = manager.suspend()
        manager.setEnabled(enabledState)
        #expect(manager.isEnabled)
    }

    @Test func dismantlingAnActiveRecorderRestoresHotkeys() {
        let manager = HotkeyManager.shared
        let original = manager.isEnabled
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
