import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Enumerates on-screen windows and resolves the frontmost capturable window
/// at a point using CGWindowList (accurate z-order) matched to SCWindow.
final class WindowEnumerator {

    struct WindowInfo {
        let scWindow: SCWindow
        /// SCK global frame (top-left origin).
        let scFrame: CGRect
        let title: String
        let appName: String

        var cocoaFrame: CGRect { GeometryConversions.cgToCocoa(scFrame) }
    }

    /// Returns capturable windows front-to-back for SCK capture.
    static func onScreenWindows() async throws -> [WindowInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let myPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        return content.windows.compactMap { window in
            guard window.isOnScreen,
                  window.owningApplication?.processID != myPID,
                  window.windowLayer < 25,
                  window.frame.width > 40, window.frame.height > 40
            else { return nil }
            return WindowInfo(scWindow: window,
                              scFrame: window.frame,
                              title: window.title ?? "",
                              appName: window.owningApplication?.applicationName ?? "")
        }
    }

    static func windows(on display: DisplayInfo, in windows: [WindowInfo]) -> [WindowInfo] {
        let bounds = display.scDisplay.frame
        return windows.filter { $0.scFrame.intersects(bounds) }
    }

    static func shareableDisplays() async throws -> [DisplayInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return DisplayInfo.match(displays: content.displays)
    }

    /// Windows owned by this app (overlays, HUD) — exclude from area capture.
    static func ownWindows() async -> [SCWindow] {
        let myPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else {
            return []
        }
        return content.windows.filter { $0.owningApplication?.processID == myPID && $0.isOnScreen }
    }

    /// Frontmost capturable window under the cursor using CGWindowList z-order.
    static func frontmostWindow(at cocoaPoint: NSPoint, candidates: [WindowInfo]) -> WindowInfo? {
        guard !candidates.isEmpty else { return nil }
        let cgPoint = GeometryConversions.cocoaPointToCG(cocoaPoint)
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.scWindow.windowID, $0) })
        let myPID = pid_t(ProcessInfo.processInfo.processIdentifier)

        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        for requireLayerZero in [true, false] {
            if let hit = pickWindow(from: list, cgPoint: cgPoint, byID: byID, myPID: myPID,
                                    requireLayerZero: requireLayerZero) {
                return hit
            }
        }
        return nil
    }

    private static func pickWindow(from list: [[String: Any]], cgPoint: CGPoint,
                                   byID: [CGWindowID: WindowInfo], myPID: pid_t,
                                   requireLayerZero: Bool) -> WindowInfo? {
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int else { continue }
            if requireLayerZero {
                guard layer == 0 else { continue }
            } else {
                guard layer < 25 else { continue }
            }
            guard let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0.05 else { continue }
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != myPID else { continue }
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let match = byID[windowID]
            else { continue }
            guard let bounds = cgBounds(from: info), bounds.width > 40, bounds.height > 40 else { continue }
            guard bounds.contains(cgPoint) else { continue }
            return WindowInfo(scWindow: match.scWindow,
                              scFrame: bounds,
                              title: match.title,
                              appName: (info[kCGWindowOwnerName as String] as? String) ?? match.appName)
        }
        return nil
    }

    /// Resolve SCWindow for capture after a CGWindowList hit (fresh instance).
    static func resolve(_ info: WindowInfo) async throws -> WindowInfo? {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let fresh = content.windows.first(where: { $0.windowID == info.scWindow.windowID }) else {
            return nil
        }
        return WindowInfo(scWindow: fresh,
                          scFrame: fresh.frame,
                          title: fresh.title ?? info.title,
                          appName: fresh.owningApplication?.applicationName ?? info.appName)
    }

    private static func cgBounds(from info: [String: Any]) -> CGRect? {
        guard let dict = info[kCGWindowBounds as String] as? [String: Any],
              let x = dict["X"] as? CGFloat,
              let y = dict["Y"] as? CGFloat,
              let w = dict["Width"] as? CGFloat,
              let h = dict["Height"] as? CGFloat
        else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
