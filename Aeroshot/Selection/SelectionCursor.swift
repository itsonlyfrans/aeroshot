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

    static let resizeNorthwestSoutheast = resizeCursor(descending: true)
    static let resizeNortheastSouthwest = resizeCursor(descending: false)

    private static func resizeCursor(descending: Bool) -> NSCursor {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let start = descending ? NSPoint(x: 2, y: 14) : NSPoint(x: 2, y: 2)
        let end = descending ? NSPoint(x: 14, y: 2) : NSPoint(x: 14, y: 14)
        let path = NSBezierPath()
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.move(to: start)
        path.line(to: end)
        path.stroke()

        for point in [start, end] {
            let arrow = NSBezierPath()
            arrow.appendArc(withCenter: point, radius: 3, startAngle: 0, endAngle: 360)
            arrow.fill()
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 8, y: 8))
    }
}

/// The capture-surface cursor precedence. The toolbar owns only its own window.
enum SelectionCursorPolicy {
    enum Role: Equatable {
        case activeResize
        case activeRetainedRegionMove
        case selection
        case arrow
        case hoveredResizeHandle
        case retainedRegion
    }

    static func role(
        hasActiveResize: Bool,
        isActivelyMovingRetainedRegion: Bool,
        isOverInteractiveControl: Bool,
        hasHoveredResizeHandle: Bool,
        isInsideRetainedRegion: Bool
    ) -> Role {
        if hasActiveResize { return .activeResize }
        if isActivelyMovingRetainedRegion { return .activeRetainedRegionMove }
        if isOverInteractiveControl { return .arrow }
        if hasHoveredResizeHandle { return .hoveredResizeHandle }
        if isInsideRetainedRegion { return .retainedRegion }
        return .selection
    }

    static func shouldApply<Cursor: Equatable>(previous: Cursor?, next: Cursor, force: Bool = false) -> Bool {
        force || previous != next
    }
}
