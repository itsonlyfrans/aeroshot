import Foundation

enum ThumbnailAction: String, CaseIterable, Codable, Identifiable {
    case copy, edit, pin, save, share, ocr, shareSafe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copy: return "Copy"
        case .edit: return "Edit"
        case .pin: return "Pin"
        case .save: return "Save"
        case .share: return "Share"
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
        case .ocr: return "text.viewfinder"
        case .shareSafe: return "shield.checkered"
        }
    }

    static let defaultVisibleActions: [ThumbnailAction] = [.copy, .edit, .pin]

    static func normalized(_ actions: [ThumbnailAction]) -> [ThumbnailAction] {
        var seen = Set<ThumbnailAction>()
        return actions.filter { seen.insert($0).inserted }.prefix(3).map { $0 }
    }
}
