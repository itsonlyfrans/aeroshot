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

    static func filter(forIndependentWindow window: SCWindow) -> SCContentFilter {
        SCContentFilter(desktopIndependentWindow: window)
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

    /// Capture a single window, cleanly isolated from overlapping content.
    static func captureWindow(_ window: SCWindow, scale: CGFloat) async throws -> CGImage {
        let filter = filter(forIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int((window.frame.width * scale).rounded())
        config.height = Int((window.frame.height * scale).rounded())
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
