import AppKit
import ScreenCaptureKit

/// Pairs an SCDisplay with its NSScreen and scale factor.
struct DisplayInfo {
    let scDisplay: SCDisplay
    let nsScreen: NSScreen
    let scale: CGFloat

    var displayID: CGDirectDisplayID { scDisplay.displayID }

    /// Cocoa global frame of this display (bottom-left origin).
    var cocoaFrame: CGRect { nsScreen.frame }

    static func match(displays: [SCDisplay]) -> [DisplayInfo] {
        displays.compactMap { display in
            guard let screen = NSScreen.screens.first(where: { screen in
                let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                return id?.uint32Value == display.displayID
            }) else { return nil }
            return DisplayInfo(scDisplay: display, nsScreen: screen, scale: screen.backingScaleFactor)
        }
    }
}
