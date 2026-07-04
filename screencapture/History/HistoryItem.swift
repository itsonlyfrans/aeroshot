import Foundation

struct HistoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let fileName: String
    let createdAt: Date
    var ocrText: String?
    var pixelWidth: Int
    var pixelHeight: Int

    init(id: UUID = UUID(), fileName: String, createdAt: Date = Date(),
         ocrText: String? = nil, pixelWidth: Int, pixelHeight: Int) {
        self.id = id
        self.fileName = fileName
        self.createdAt = createdAt
        self.ocrText = ocrText
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}
