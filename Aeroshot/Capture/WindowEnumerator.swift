import AppKit
import ApplicationServices
import CoreGraphics
import ScreenCaptureKit

/// Enumerates on-screen windows and resolves the frontmost capturable window
/// at a point using CGWindowList's z-order matched to SCWindow.
final class WindowEnumerator {

    struct OverlayContent {
        let displays: [DisplayInfo]
        let windows: [WindowInfo]
    }

    struct WindowInfo {
        let scWindow: SCWindow
        /// SCK global frame (top-left origin).
        let scFrame: CGRect
        let title: String
        let appName: String

        var cocoaFrame: CGRect { GeometryConversions.cgToCocoa(scFrame) }
        var isDock: Bool { appName == "Dock" }
    }

    /// Returns capturable windows front-to-back for SCK capture.
    static func onScreenWindows() async throws -> [WindowInfo] {
        let cgWindows = onScreenCGWindows()
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        return windowInfos(from: content, cgWindows: cgWindows)
    }

    /// Returns the display and window lists from one ScreenCaptureKit query.
    static func overlayContent() async throws -> OverlayContent {
        let cgWindows = onScreenCGWindows()
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        return OverlayContent(
            displays: DisplayInfo.match(displays: content.displays),
            windows: windowInfos(from: content, cgWindows: cgWindows)
        )
    }

    private static func windowInfos(from content: SCShareableContent,
                                    cgWindows: [[String: Any]]) -> [WindowInfo] {
        let myPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        var zOrder: [CGWindowID: Int] = [:]
        for (index, info) in cgWindows.enumerated() {
            if let windowID = info[kCGWindowNumber as String] as? CGWindowID {
                zOrder[windowID] = index
            }
        }
        let dockFrame = content.windows
            .first { $0.owningApplication?.applicationName == "Dock" }
            .flatMap { dockAccessibilityFrame(processID: $0.owningApplication?.processID) }
            .map { frame in
                guard let display = content.displays.first(where: {
                    $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
                }) else { return frame }
                return dockCaptureFrame(accessibilityFrame: frame, displayFrame: display.frame)
            }
        let windows: [WindowInfo] = content.windows.compactMap { window -> WindowInfo? in
            guard window.isOnScreen,
                  window.owningApplication?.processID != myPID,
                  window.windowLayer < 25,
                  window.frame.width > 40, window.frame.height > 40
            else { return nil }
            let appName = window.owningApplication?.applicationName ?? ""
            return WindowInfo(scWindow: window,
                              scFrame: appName == "Dock" ? dockFrame ?? window.frame : window.frame,
                              title: window.title ?? "",
                              appName: appName)
        }
        return windows.sorted {
            zOrder[$0.scWindow.windowID, default: .max] < zOrder[$1.scWindow.windowID, default: .max]
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
        let snapshotHit = snapshotHitIndex(at: cgPoint, frames: candidates.map(\.scFrame))
            .map { candidates[$0] }

        let liveWindows = onScreenCGWindows()
        if !liveWindows.isEmpty {
            let liveIDs = Set(liveWindows.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
            if let hit = pickWindow(from: liveWindows, cgPoint: cgPoint, byID: byID, myPID: myPID) {
                if let snapshotHit,
                   shouldPreferSnapshot(snapshotID: snapshotHit.scWindow.windowID,
                                        liveID: hit.scWindow.windowID,
                                        liveIDs: liveIDs) {
                    return snapshotHit
                }
                return hit
            }
        }

        return snapshotHit
    }

    static func snapshotHitIndex(at point: CGPoint, frames: [CGRect]) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }

    static func shouldPreferSnapshot(snapshotID: CGWindowID, liveID: CGWindowID,
                                     liveIDs: Set<CGWindowID>) -> Bool {
        snapshotID != liveID && !liveIDs.contains(snapshotID)
    }

    private static func onScreenCGWindows() -> [[String: Any]] {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
    }

    private static func pickWindow(from list: [[String: Any]], cgPoint: CGPoint,
                                   byID: [CGWindowID: WindowInfo], myPID: pid_t) -> WindowInfo? {
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int else { continue }
            guard layer < 25 else { continue }
            guard let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0.05 else { continue }
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != myPID else { continue }
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let match = byID[windowID]
            else { continue }
            guard let bounds = cgBounds(from: info), bounds.width > 40, bounds.height > 40 else { continue }
            guard bounds.contains(cgPoint) else { continue }
            let ownerName = (info[kCGWindowOwnerName as String] as? String) ?? match.appName
            let selectionFrame = selectionFrame(ownerName: ownerName,
                                                cgBounds: bounds,
                                                scFrame: match.scFrame)
            guard selectionFrame.contains(cgPoint) else { continue }
            return WindowInfo(scWindow: match.scWindow,
                              scFrame: selectionFrame,
                              title: match.title,
                              appName: ownerName)
        }
        return nil
    }

    static func selectionFrame(ownerName: String, cgBounds: CGRect, scFrame: CGRect) -> CGRect {
        ownerName == "Dock" ? scFrame : cgBounds
    }

    static func dockCaptureFrame(accessibilityFrame frame: CGRect, displayFrame: CGRect) -> CGRect {
        var result = frame.insetBy(dx: -2, dy: -2)
        let distances = [
            abs(frame.minX - displayFrame.minX),
            abs(displayFrame.maxX - frame.maxX),
            abs(frame.minY - displayFrame.minY),
            abs(displayFrame.maxY - frame.maxY)
        ]
        switch distances.firstIndex(of: distances.min() ?? 0) {
        case 0:
            result.size.width = result.maxX - displayFrame.minX
            result.origin.x = displayFrame.minX
        case 1:
            result.size.width = displayFrame.maxX - result.minX
        case 2:
            result.size.height = result.maxY - displayFrame.minY
            result.origin.y = displayFrame.minY
        default:
            result.size.height = displayFrame.maxY - result.minY
        }
        return result.intersection(displayFrame)
    }

    private static func dockAccessibilityFrame(processID: pid_t?) -> CGRect? {
        guard let processID else { return nil }
        let app = AXUIElementCreateApplication(processID)
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement]
        else { return nil }

        for child in children {
            var roleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue) == .success,
                  roleValue as? String == kAXListRole
            else { continue }
            var positionValue: CFTypeRef?
            var sizeValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &positionValue) == .success,
                  AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &sizeValue) == .success,
                  let positionValue,
                  let sizeValue
            else { continue }
            guard let origin = accessibilityPoint(from: positionValue),
                  let dimensions = accessibilitySize(from: sizeValue)
            else { continue }
            return CGRect(origin: origin, size: dimensions)
        }
        return nil
    }

    static func accessibilityPoint(from value: CFTypeRef) -> CGPoint? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let value = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(value) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    static func accessibilitySize(from value: CFTypeRef) -> CGSize? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let value = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(value) == .cgSize else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    /// Resolve SCWindow for capture after a CGWindowList hit (fresh instance).
    static func resolve(_ info: WindowInfo) async throws -> SCWindow? {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        return content.windows.first(where: { $0.windowID == info.scWindow.windowID })
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
