import CoreGraphics
import Foundation

/// Aspect ratio lock for selection overlays (shares presets with beautify).
enum SelectionAspectLock: String, Codable, CaseIterable, Identifiable {
    case auto, square, wide16x9, fourByThree

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Free"
        case .square: return "1:1"
        case .wide16x9: return "16:9"
        case .fourByThree: return "4:3"
        }
    }

    var ratio: CGFloat? {
        switch self {
        case .auto: return nil
        case .square: return 1
        case .wide16x9: return 16.0 / 9.0
        case .fourByThree: return 4.0 / 3.0
        }
    }

    var badgeLabel: String? {
        switch self {
        case .auto: return nil
        case .square: return "1:1"
        case .wide16x9: return "16:9"
        case .fourByThree: return "4:3"
        }
    }

    /// Constrain a rubber-band rect anchored at `origin` toward `current`.
    static func constrainedRect(origin: CGPoint, current: CGPoint, ratio: CGFloat, bounds: CGRect) -> (origin: CGPoint, current: CGPoint) {
        var dx = current.x - origin.x
        var dy = current.y - origin.y
        let signX: CGFloat = dx >= 0 ? 1 : -1
        let signY: CGFloat = dy >= 0 ? 1 : -1
        dx = abs(dx)
        dy = abs(dy)

        if dx / max(dy, 0.001) > ratio {
            dy = dx / ratio
        } else {
            dx = dy * ratio
        }

        var end = CGPoint(x: origin.x + signX * dx, y: origin.y + signY * dy)
        var start = origin

        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        if rect.minX < bounds.minX {
            let shift = bounds.minX - rect.minX
            start.x += shift
            end.x += shift
        }
        if rect.minY < bounds.minY {
            let shift = bounds.minY - rect.minY
            start.y += shift
            end.y += shift
        }
        if rect.maxX > bounds.maxX {
            let shift = rect.maxX - bounds.maxX
            start.x -= shift
            end.x -= shift
        }
        if rect.maxY > bounds.maxY {
            let shift = rect.maxY - bounds.maxY
            start.y -= shift
            end.y -= shift
        }

        return (start, end)
    }
}
