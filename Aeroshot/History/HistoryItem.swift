import Foundation

enum HistoryCaptureKind: String, Codable {
    case image
    case text
    case recording
}

struct HistoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let fileName: String
    let createdAt: Date
    var ocrText: String?
    var pixelWidth: Int
    var pixelHeight: Int
    var kind: HistoryCaptureKind

    init(id: UUID = UUID(), fileName: String, createdAt: Date = Date(),
         ocrText: String? = nil, pixelWidth: Int, pixelHeight: Int,
         kind: HistoryCaptureKind = .image) {
        self.id = id
        self.fileName = fileName
        self.createdAt = createdAt
        self.ocrText = ocrText
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileName = try container.decode(String.self, forKey: .fileName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText)
        pixelWidth = try container.decode(Int.self, forKey: .pixelWidth)
        pixelHeight = try container.decode(Int.self, forKey: .pixelHeight)
        kind = try container.decodeIfPresent(HistoryCaptureKind.self, forKey: .kind) ?? .image
    }

    var fileExtension: String {
        (fileName as NSString).pathExtension.lowercased()
    }
}
