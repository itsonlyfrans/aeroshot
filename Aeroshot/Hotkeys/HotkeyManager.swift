@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import os

/// Global shortcuts via an active event tap so matching keys never reach the
/// frontmost app or macOS after Aeroshot handles them.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private static let log = Logger(subsystem: "com.aeroshot", category: "Hotkeys")

    private struct Binding {
        let hotkey: Hotkey
        let handler: () -> Void
    }

    private var bindings: [HotkeyAction: Binding] = [:]
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var localMonitor: Any?
    private(set) var isEnabled = true

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

    /// Suspend dispatch and return the state that the caller must restore.
    func suspend() -> Bool {
        let priorState = isEnabled
        isEnabled = false
        return priorState
    }

    // MARK: - Monitors

    private func reinstallMonitors() {
        uninstallEventTap()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        isGlobalMonitorActive = false

        guard !bindings.isEmpty else { return }

        installEventTap()

        // Shortcuts while our settings/editor windows are key.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.dispatch(event) ? nil : event
        }
    }

    private func installEventTap() {
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Self.log.error("Could not install active hotkey event tap")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isGlobalMonitorActive = true
    }

    private func uninstallEventTap() {
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        eventTapSource = nil
        eventTap = nil
    }

    func handleTapEvent(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        return dispatch(event) ? nil : Unmanaged.passUnretained(event)
    }

    @discardableResult
    func dispatch(_ event: CGEvent) -> Bool {
        guard let event = NSEvent(cgEvent: event) else { return false }
        return dispatch(event)
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

nonisolated private func hotkeyEventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    return MainActor.assumeIsolated {
        manager.handleTapEvent(type, event: event)
    }
}
