import AppKit
import ScreenCaptureKit

/// Thin wrapper around SCScreenshotManager. Filter construction is kept
/// separate from invocation so a future SCStream recorder can reuse filters.
final class ScreenCaptureService {

    enum CaptureError: Error {
        case noDisplay
        case captureFailed
    }

    // MARK: - Filter construction

    static func filter(for display: DisplayInfo, excludingWindows: [SCWindow] = []) -> SCContentFilter {
        SCContentFilter(display: display.scDisplay, excludingWindows: excludingWindows)
    }

    // MARK: - Still capture

    /// Capture a full display at native pixel resolution.
    static func captureDisplay(_ display: DisplayInfo, excludingWindows: [SCWindow] = []) async throws -> CGImage {
        let filter = filter(for: display, excludingWindows: excludingWindows)
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.scDisplay.width) * display.scale)
        config.height = Int(CGFloat(display.scDisplay.height) * display.scale)
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Capture an area of a display. `rectInDisplayTopLeftPoints` is local to
    /// the display, top-left origin, in points.
    static func captureArea(_ rectInDisplayTopLeftPoints: CGRect,
                            on display: DisplayInfo,
                            excludingWindows: [SCWindow] = []) async throws -> CGImage {
        let filter = filter(for: display, excludingWindows: excludingWindows)
        let config = SCStreamConfiguration()
        config.sourceRect = rectInDisplayTopLeftPoints
        config.width = Int((rectInDisplayTopLeftPoints.width * display.scale).rounded())
        config.height = Int((rectInDisplayTopLeftPoints.height * display.scale).rounded())
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Capture a single window, isolated from other windows in the stack.
    static func captureWindow(_ window: SCWindow, on display: DisplayInfo) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let freshWindow = content.windows.first(where: { $0.windowID == window.windowID }) else {
            throw CaptureError.captureFailed
        }

        let filter = SCContentFilter(desktopIndependentWindow: freshWindow)
        let config = SCStreamConfiguration()
        config.width = Int((freshWindow.frame.width * display.scale).rounded())
        config.height = Int((freshWindow.frame.height * display.scale).rounded())
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
