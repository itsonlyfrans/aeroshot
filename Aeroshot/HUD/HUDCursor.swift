import AppKit

/// A restrained command cursor for the capture HUD. It stays recognizably
/// macOS-like while clearly separating toolbar interaction from region picking.
enum HUDCursor {
    /// Updated only from AppKit's main event loop. The selection overlay checks
    /// this before applying its precision cursor.
    static var isPointerOverToolbar = false

    static let command: NSCursor = {
        let size = NSSize(width: 15, height: 17)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let arrow = NSBezierPath()
        arrow.move(to: CGPoint(x: 2, y: 15))
        arrow.line(to: CGPoint(x: 2, y: 2))
        arrow.line(to: CGPoint(x: 5, y: 5))
        arrow.line(to: CGPoint(x: 7, y: 1))
        arrow.line(to: CGPoint(x: 9.5, y: 2.2))
        arrow.line(to: CGPoint(x: 7.5, y: 6.5))
        arrow.line(to: CGPoint(x: 12.5, y: 6.5))
        arrow.close()

        NSColor.black.withAlphaComponent(0.86).setStroke()
        arrow.lineWidth = 2
        arrow.lineJoinStyle = .round
        arrow.stroke()
        NSColor.white.setFill()
        arrow.fill()
        AeroTheme.accentNSColor.setStroke()
        arrow.lineWidth = 0.75
        arrow.stroke()

        return NSCursor(image: image, hotSpot: NSPoint(x: 2, y: 15))
    }()
}
