import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click-to-record hotkey field. Rejects combos without modifiers and the
/// system's reserved ⇧⌘3/4/5 captures.
struct HotkeyRecorderView: NSViewRepresentable {
    let action: HotkeyAction
    @Binding var hotkey: Hotkey
    var validationMessage: (Hotkey) -> String? = { _ in nil }
    var onChange: (Hotkey) -> Void

    func makeNSView(context: Context) -> RecorderField {
        let field = RecorderField()
        field.validationMessage = validationMessage
        field.onRecorded = { new in
            hotkey = new
            onChange(new)
        }
        return field
    }

    func updateNSView(_ nsView: RecorderField, context: Context) {
        nsView.validationMessage = validationMessage
        nsView.display(hotkey: hotkey)
    }

    final class RecorderField: NSButton {
        var onRecorded: ((Hotkey) -> Void)?
        var validationMessage: ((Hotkey) -> String?)?
        private var recording = false
        private var monitor: Any?
        private var currentHotkey: Hotkey?

        init() {
            super.init(frame: .zero)
            bezelStyle = .rounded
            setButtonType(.momentaryPushIn)
            target = self
            action = #selector(toggleRecording)
        }

        required init?(coder: NSCoder) { fatalError() }

        func display(hotkey: Hotkey) {
            currentHotkey = hotkey
            if !recording { title = hotkey.displayString }
        }

        @objc private func toggleRecording() {
            recording ? stopRecording() : startRecording()
        }

        private func startRecording() {
            recording = true
            HotkeyManager.shared.setEnabled(false)
            title = "Type shortcut…"
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                if event.keyCode == 53 { // Esc cancels
                    self.stopRecording()
                    return nil
                }
                guard let new = Hotkey(event: event), new.isValid else {
                    NSSound.beep()
                    self.title = Hotkey(event: event)?.invalidReason ?? "Needs a modifier key"
                    return nil
                }
                if let message = self.validationMessage?(new) {
                    NSSound.beep()
                    self.title = message
                    return nil
                }
                self.stopRecording()
                self.onRecorded?(new)
                return nil
            }
        }

        private func stopRecording() {
            recording = false
            HotkeyManager.shared.setEnabled(true)
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            if let currentHotkey { title = currentHotkey.displayString }
        }
    }
}
