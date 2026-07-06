import AppKit
@preconcurrency import ApplicationServices

/// Posts synthetic scroll-wheel events for scrolling-capture auto-scroll.
/// Requires Accessibility permission (same as CleanShot/Longshot auto-scroll).
nonisolated enum ScrollEventPoster {

    static var hasAccessibilityAccess: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Scroll down by `pixels` (positive = down). Returns false if posting failed.
    @discardableResult
    static func scrollDown(pixels: Int32 = 120) -> Bool {
        guard hasAccessibilityAccess else { return false }
        guard let event = CGEvent(scrollWheelEvent2Source: nil,
                                  units: .pixel,
                                  wheelCount: 1,
                                  wheel1: -pixels,
                                  wheel2: 0,
                                  wheel3: 0)
        else { return false }
        event.post(tap: .cghidEventTap)
        return true
    }
}
