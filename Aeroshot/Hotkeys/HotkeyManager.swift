import AppKit
@preconcurrency import ApplicationServices
import os

/// Global shortcuts via NSEvent global monitors.
/// Requires Accessibility in System Settings for shortcuts to work while
/// other apps are frontmost.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private static let log = Logger(subsystem: "com.aeroshot", category: "Hotkeys")

    private struct Binding {
        let hotkey: Hotkey
        let handler: () -> Void
    }

    private var bindings: [HotkeyAction: Binding] = [:]
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isEnabled = true

    private(set) var isGlobalMonitorActive = false

    private init() {}

    // MARK: - Accessibility (required for background shortcuts)

    static var hasGlobalHotkeyAccess: Bool {
        AXIsProcessTrusted()
    }

    static func requestGlobalHotkeyAccess() {
        guard !hasGlobalHotkeyAccess else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Registration

    /// Stores the binding and (re)installs event monitors. Returns whether the
    /// global (background) monitor is active — false means Accessibility is
    /// missing and shortcuts only work while Aeroshot is the active app.
    @discardableResult
    func register(action: HotkeyAction, hotkey: Hotkey, handler: @escaping () -> Void) -> Bool {
        bindings[action] = Binding(hotkey: hotkey, handler: handler)
        reinstallMonitors()
        Self.log.debug("Bound \(action.rawValue) → \(hotkey.displayString), global=\(self.isGlobalMonitorActive)")
        return isGlobalMonitorActive
    }

    /// Replace all bindings and reinstall monitors once.
    @discardableResult
    func setBindings(_ newBindings: [HotkeyAction: (hotkey: Hotkey, handler: () -> Void)]) -> Bool {
        bindings = newBindings.mapValues { Binding(hotkey: $0.hotkey, handler: $0.handler) }
        reinstallMonitors()
        Self.log.debug("Installed \(self.bindings.count) hotkey bindings, global=\(self.isGlobalMonitorActive)")
        return isGlobalMonitorActive
    }

    func unregister(action: HotkeyAction) {
        bindings.removeValue(forKey: action)
        reinstallMonitors()
    }

    func unregisterAll() {
        bindings.removeAll()
        reinstallMonitors()
    }

    /// Re-attach monitors after Accessibility is granted without changing bindings.
    func refreshMonitors() {
        reinstallMonitors()
    }

    /// Suspend dispatch while recording a new shortcut in Settings.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    // MARK: - Monitors

    private func reinstallMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        isGlobalMonitorActive = false

        guard !bindings.isEmpty else { return }

        // Background shortcuts (other apps frontmost) — needs Accessibility.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.dispatch(event) }
        }
        isGlobalMonitorActive = globalMonitor != nil

        // Shortcuts while our settings/editor windows are key.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.dispatch(event) ? nil : event
        }
    }

    @discardableResult
    private func dispatch(_ event: NSEvent) -> Bool {
        guard isEnabled else { return false }
        guard let pressed = Hotkey(event: event) else { return false }
        for binding in bindings.values where binding.hotkey == pressed {
            Self.log.debug("Shortcut fired: \(pressed.displayString)")
            binding.handler()
            return true
        }
        return false
    }
}
