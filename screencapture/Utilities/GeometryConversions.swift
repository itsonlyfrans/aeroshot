import AppKit
import ScreenCaptureKit

/// Centralizes conversions between Cocoa's bottom-left-origin global coordinates
/// and CoreGraphics / ScreenCaptureKit's top-left-origin coordinates.
///
/// The CG global space has its origin at the top-left of the *primary* display
/// (the one whose Cocoa frame.origin == .zero), with Y increasing downward.
enum GeometryConversions {

    /// Height of the primary screen in points (the anchor of both coordinate spaces).
    static var primaryScreenHeight: CGFloat {
        // NSScreen.screens.first is always the primary (menu bar) display.
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// Convert a rect in Cocoa global coordinates (bottom-left origin) to
    /// CG/SCK global coordinates (top-left origin).
    static func cocoaToCG(_ rect: CGRect, primaryHeight: CGFloat? = nil) -> CGRect {
        let h = primaryHeight ?? primaryScreenHeight
        return CGRect(x: rect.origin.x,
                      y: h - rect.origin.y - rect.height,
                      width: rect.width,
                      height: rect.height)
    }

    /// Convert a rect in CG/SCK global coordinates (top-left origin) to
    /// Cocoa global coordinates (bottom-left origin).
    static func cgToCocoa(_ rect: CGRect, primaryHeight: CGFloat? = nil) -> CGRect {
        // The transform is an involution; same math both ways.
        cocoaToCG(rect, primaryHeight: primaryHeight)
    }

    /// Convert a global Cocoa rect into a rect local to the given screen, in
    /// top-left-origin coordinates relative to that screen (what SCK's
    /// sourceRect expects for a display-filtered capture).
    static func cocoaGlobalToDisplayLocalTopLeft(_ rect: CGRect, screen: NSScreen) -> CGRect {
        let sf = screen.frame
        return CGRect(x: rect.origin.x - sf.origin.x,
                      y: sf.maxY - rect.maxY,
                      width: rect.width,
                      height: rect.height)
    }

    /// Convert an SCK/CG global frame (top-left origin) into display-local
    /// top-left coordinates for `SCStreamConfiguration.sourceRect`.
    static func scFrameToDisplayLocalTopLeft(_ frame: CGRect, display: DisplayInfo) -> CGRect {
        let df = display.scDisplay.frame
        return CGRect(x: frame.origin.x - df.origin.x,
                      y: frame.origin.y - df.origin.y,
                      width: frame.width,
                      height: frame.height)
    }

    /// Convert a global Cocoa point to SCK/CG global coordinates (top-left origin).
    static func cocoaPointToCG(_ point: NSPoint, primaryHeight: CGFloat? = nil) -> CGPoint {
        let h = primaryHeight ?? primaryScreenHeight
        return CGPoint(x: point.x, y: h - point.y)
    }

    /// The screen containing (or nearest to) a global Cocoa point.
    static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    /// Pixel dimensions for a rect in points on a given screen.
    static func pixelSize(for rect: CGRect, scale: CGFloat) -> CGSize {
        CGSize(width: (rect.width * scale).rounded(), height: (rect.height * scale).rounded())
    }
}
