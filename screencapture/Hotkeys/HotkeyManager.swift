import AppKit
import CoreGraphics
import os

/// Global shortcuts via NSEvent monitors (same approach as CleanShot / Longshot).
/// Requires Input Monitoring in System Settings for shortcuts to work while
/// other apps are frontmost.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private static let log = Logger(subsystem: "com.screencapture", category: "Hotkeys")

    private struct Binding {
        let hotkey: Hotkey
        let handler: () -> Void
    }

    private var bindings: [HotkeyAction: Binding] = [:]
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private(set) var isGlobalMonitorActive = false

    private init() {}

    // MARK: - Input Monitoring (required for background shortcuts)

    static var hasInputMonitoringAccess: Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    static func requestInputMonitoringAccess() -> Bool {
        if CGPreflightListenEventAccess() { return true }
        CGRequestListenEventAccess()
        return CGPreflightListenEventAccess()
    }

    static func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Registration

    /// Stores the binding and (re)installs event monitors. Returns whether the
    /// global (background) monitor is active — false means Input Monitoring is
    /// missing and shortcuts only work while ScreenCapture is the active app.
    @discardableResult
    func register(action: HotkeyAction, hotkey: Hotkey, handler: @escaping () -> Void) -> Bool {
        bindings[action] = Binding(hotkey: hotkey, handler: handler)
        reinstallMonitors()
        Self.log.info("Bound \(action.rawValue) → \(hotkey.displayString), global=\(self.isGlobalMonitorActive)")
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

    /// Re-attach monitors after Input Monitoring is granted without changing bindings.
    func refreshMonitors() {
        reinstallMonitors()
    }

    // MARK: - Monitors

    private func reinstallMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        isGlobalMonitorActive = false

        guard !bindings.isEmpty else { return }

        // Background shortcuts (other apps frontmost) — needs Input Monitoring.
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
        guard let pressed = Hotkey(event: event) else { return false }
        for binding in bindings.values where binding.hotkey == pressed {
            Self.log.debug("Shortcut fired: \(pressed.displayString)")
            binding.handler()
            return true
        }
        return false
    }
}
