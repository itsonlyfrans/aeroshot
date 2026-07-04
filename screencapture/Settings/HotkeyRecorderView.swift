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
    var onValidationError: ((String?) -> Void)?

    func makeNSView(context: Context) -> RecorderField {
        let field = RecorderField()
        field.validationMessage = validationMessage
        field.onRecorded = { new in
            hotkey = new
            onChange(new)
        }
        field.onValidationError = onValidationError
        return field
    }

    func updateNSView(_ nsView: RecorderField, context: Context) {
        nsView.validationMessage = validationMessage
        nsView.onValidationError = onValidationError
        nsView.display(hotkey: hotkey)
    }

    final class RecorderField: NSButton {
        var onRecorded: ((Hotkey) -> Void)?
        var validationMessage: ((Hotkey) -> String?)?
        var onValidationError: ((String?) -> Void)?
        private var recording = false
        private var monitor: Any?
        private var currentHotkey: Hotkey?
        private var pulseTimer: Timer?
        private var pulseBright = true

        init() {
            super.init(frame: .zero)
            bezelStyle = .rounded
            setButtonType(.momentaryPushIn)
            target = self
            action = #selector(toggleRecording)
        }

        required init?(coder: NSCoder) { fatalError() }

        deinit {
            pulseTimer?.invalidate()
        }

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
            contentTintColor = .controlAccentColor
            onValidationError?(nil)
            startPulsing()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                if event.keyCode == 53 { // Esc cancels
                    self.stopRecording()
                    return nil
                }
                guard let new = Hotkey(event: event), new.isValid else {
                    NSSound.beep()
                    let reason = Hotkey(event: event)?.invalidReason ?? "Needs a modifier key"
                    self.onValidationError?(reason)
                    return nil
                }
                if let message = self.validationMessage?(new) {
                    NSSound.beep()
                    self.onValidationError?(message)
                    return nil
                }
                self.stopRecording()
                self.onRecorded?(new)
                return nil
            }
        }

        private func stopRecording() {
            recording = false
            stopPulsing()
            HotkeyManager.shared.setEnabled(true)
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            contentTintColor = nil
            if let currentHotkey { title = currentHotkey.displayString }
        }

        private func startPulsing() {
            pulseTimer?.invalidate()
            pulseBright = true
            alphaValue = 1
            pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
                guard let self, self.recording else { return }
                self.pulseBright.toggle()
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.25
                    self.animator().alphaValue = self.pulseBright ? 1.0 : 0.55
                }
            }
        }

        private func stopPulsing() {
            pulseTimer?.invalidate()
            pulseTimer = nil
            alphaValue = 1
        }
    }
}
