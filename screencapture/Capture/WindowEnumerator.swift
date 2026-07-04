import AppKit
import ScreenCaptureKit

/// Enumerates on-screen windows via SCShareableContent, preserving z-order.
final class WindowEnumerator {

    struct WindowInfo {
        let scWindow: SCWindow
        /// Global Cocoa frame (bottom-left origin) of the window.
        let cocoaFrame: CGRect
        let title: String
        let appName: String
    }

    /// Returns capturable windows front-to-back, excluding our own app,
    /// menu-bar items, and tiny utility windows.
    static func onScreenWindows() async throws -> [WindowInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let myPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        // SCShareableContent returns windows in z-order, frontmost first.
        return content.windows.compactMap { window in
            guard window.isOnScreen,
                  window.owningApplication?.processID != myPID,
                  window.windowLayer == 0,  // normal app windows only
                  window.frame.width > 40, window.frame.height > 40
            else { return nil }
            let cocoaFrame = GeometryConversions.cgToCocoa(window.frame)
            return WindowInfo(scWindow: window,
                              cocoaFrame: cocoaFrame,
                              title: window.title ?? "",
                              appName: window.owningApplication?.applicationName ?? "")
        }
    }

    static func shareableDisplays() async throws -> [DisplayInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return DisplayInfo.match(displays: content.displays)
    }

    /// Frontmost window whose frame contains the global Cocoa point.
    static func window(at point: NSPoint, in windows: [WindowInfo]) -> WindowInfo? {
        windows.first { $0.cocoaFrame.contains(point) }
    }
}
