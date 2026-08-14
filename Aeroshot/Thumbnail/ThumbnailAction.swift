import Foundation

enum ThumbnailAction: String, CaseIterable, Codable, Identifiable {
    case copy, edit, pin, save, share, reveal, ocr, shareSafe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copy: return "Copy"
        case .edit: return "Edit"
        case .pin: return "Pin"
        case .save: return "Save"
        case .share: return "Share"
        case .reveal: return "Reveal"
        case .ocr: return "Copy Text"
        case .shareSafe: return "Share Safe"
        }
    }

    var symbol: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .edit: return "pencil.tip.crop.circle"
        case .pin: return "pin"
        case .save: return "square.and.arrow.down"
        case .share: return "square.and.arrow.up"
        case .reveal: return "magnifyingglass"
        case .ocr: return "text.viewfinder"
        case .shareSafe: return "shield.checkered"
        }
    }

    static let defaultVisibleActions: [ThumbnailAction] = [.edit, .copy, .save]

    static func normalized(_ actions: [ThumbnailAction]) -> [ThumbnailAction] {
        var seen = Set<ThumbnailAction>()
        return actions.filter { seen.insert($0).inserted }.prefix(4).map { $0 }
    }
}

enum ThumbnailSwipeDirection: String, CaseIterable, Codable, Identifiable {
    case left, right, up, down

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        }
    }
}

enum ThumbnailSwipeFingerCount: Int, CaseIterable, Codable, Identifiable {
    case two = 2
    case three = 3

    var id: Int { rawValue }
    var title: String { self == .two ? "Two fingers" : "Three fingers" }
}

enum ThumbnailGestureAction: String, CaseIterable, Codable, Identifiable {
    case none, dismiss, tuck, keep, copy, save, edit, pin, ocr, share, reveal, shareSafe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "No action"
        case .dismiss: return "Dismiss"
        case .tuck: return "Tuck Away"
        case .keep: return "Keep in Corner"
        case .copy: return "Copy"
        case .save: return "Save"
        case .edit: return "Edit"
        case .pin: return "Float Image"
        case .ocr: return "Copy Text"
        case .share: return "Share"
        case .reveal: return "Reveal"
        case .shareSafe: return "Share Safe"
        }
    }

    var thumbnailAction: ThumbnailAction? {
        ThumbnailAction(rawValue: rawValue)
    }
}

struct ThumbnailSwipeBindings: Codable, Equatable {
    private var actions: [String: ThumbnailGestureAction]

    static let defaults: Self = {
        var value = Self(actions: [:])
        for fingers in ThumbnailSwipeFingerCount.allCases {
            for direction in ThumbnailSwipeDirection.allCases {
                value.set(.none, for: fingers, direction: direction)
            }
        }
        value.set(.dismiss, for: .two, direction: .left)
        value.set(.edit, for: .two, direction: .right)
        value.set(.copy, for: .two, direction: .up)
        value.set(.tuck, for: .two, direction: .down)
        return value
    }()

    init(actions: [String: ThumbnailGestureAction] = [:]) {
        self.actions = actions
    }

    func action(for fingers: ThumbnailSwipeFingerCount, direction: ThumbnailSwipeDirection) -> ThumbnailGestureAction {
        actions[Self.key(fingers, direction)] ?? .none
    }

    mutating func set(
        _ action: ThumbnailGestureAction,
        for fingers: ThumbnailSwipeFingerCount,
        direction: ThumbnailSwipeDirection
    ) {
        actions[Self.key(fingers, direction)] = action
    }

    private static func key(_ fingers: ThumbnailSwipeFingerCount, _ direction: ThumbnailSwipeDirection) -> String {
        "\(fingers.rawValue).\(direction.rawValue)"
    }
}

enum ThumbnailSwipeResolver {
    static func direction(
        for translation: CGSize,
        minimumDistance: CGFloat = 0.06,
        axisDominance: CGFloat = 1.2
    ) -> ThumbnailSwipeDirection? {
        let horizontal = abs(translation.width)
        let vertical = abs(translation.height)
        guard max(horizontal, vertical) >= minimumDistance else { return nil }
        if horizontal >= vertical * axisDominance {
            return translation.width < 0 ? .left : .right
        }
        if vertical >= horizontal * axisDominance {
            return translation.height < 0 ? .down : .up
        }
        return nil
    }
}
