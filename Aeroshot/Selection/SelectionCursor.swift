import AppKit

/// A high-contrast reticle that remains readable over both the dimmed overlay
/// and bright content underneath it.
enum SelectionCursor {
    static let crosshair: NSCursor = {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        func drawLine(from start: CGPoint, to end: CGPoint, color: NSColor, width: CGFloat) {
            color.setStroke()
            let path = NSBezierPath()
            path.lineWidth = width
            path.lineCapStyle = .round
            path.move(to: start)
            path.line(to: end)
            path.stroke()
        }

        // Shadow first, then a slimmer white reticle for contrast.
        let gap: CGFloat = 3
        let arm: CGFloat = 10
        let segments = [
            (CGPoint(x: center.x - arm, y: center.y), CGPoint(x: center.x - gap, y: center.y)),
            (CGPoint(x: center.x + gap, y: center.y), CGPoint(x: center.x + arm, y: center.y)),
            (CGPoint(x: center.x, y: center.y - arm), CGPoint(x: center.x, y: center.y - gap)),
            (CGPoint(x: center.x, y: center.y + gap), CGPoint(x: center.x, y: center.y + arm))
        ]
        for (start, end) in segments {
            drawLine(from: start, to: end, color: .black.withAlphaComponent(0.9), width: 3)
        }
        for (start, end) in segments {
            drawLine(from: start, to: end, color: .white, width: 1.25)
        }

        return NSCursor(image: image, hotSpot: center)
    }()
}
