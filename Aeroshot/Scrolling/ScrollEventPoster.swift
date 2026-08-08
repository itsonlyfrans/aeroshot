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

    /// Makes a continuous pixel-scroll event at the selected content.
    static func makeScrollEvent(pixels: Int32, at target: CGPoint) -> CGEvent? {
        guard let event = CGEvent(scrollWheelEvent2Source: nil,
                                  units: .pixel,
                                  wheelCount: 1,
                                  wheel1: -pixels,
                                  wheel2: 0,
                                  wheel3: 0)
        else { return nil }
        event.location = target
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(-pixels))
        return event
    }

    /// Posts at `target`; this does not move the hardware pointer.
    @discardableResult
    static func scrollDown(pixels: Int32, at target: CGPoint) -> Bool {
        guard hasAccessibilityAccess,
              let event = makeScrollEvent(pixels: pixels, at: target)
        else { return false }
        event.post(tap: .cghidEventTap)
        return true
    }
}
