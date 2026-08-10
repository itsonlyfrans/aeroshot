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
}
