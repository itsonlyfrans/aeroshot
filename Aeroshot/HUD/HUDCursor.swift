import AppKit

/// A cursor writer may only affect the pointer when its window is topmost at
/// that screen point. This keeps overlapping panels from racing each other.
enum CursorWindowOwnership {
    static func ownsCursor(_ window: NSWindow?, at screenPoint: NSPoint = NSEvent.mouseLocation) -> Bool {
        guard let window else { return false }
        return frontmostAppWindow(at: screenPoint) === window
    }

    private static func frontmostAppWindow(at screenPoint: NSPoint) -> NSWindow? {
        var hitWindow: NSWindow?
        NSApp.enumerateWindows(options: .orderedFrontToBack) { candidate, stop in
            guard candidate.isVisible, !candidate.ignoresMouseEvents,
                  let contentView = candidate.contentView
            else { return }
            let pointInWindow = candidate.convertPoint(fromScreen: screenPoint)
            let pointInView = contentView.convert(pointInWindow, from: nil)
            guard contentView.hitTest(pointInView) != nil else { return }
            hitWindow = candidate
            stop.pointee = true
        }
        return hitWindow
    }
}
