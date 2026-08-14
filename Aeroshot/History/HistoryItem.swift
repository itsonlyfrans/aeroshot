import Foundation

enum HistoryCaptureKind: String, Codable, CaseIterable, Sendable {
    case image
    case text
    case recording
    case gif
    case project
}

enum HistoryRecoveryState: String, Codable, Sendable {
    case none
    case recoverable
    case recovered
    case recoveryFailed
}

enum HistorySourceState: String, Codable, Sendable {
    case available
    case missing
}

struct HistoryItem: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var fileName: String
    let createdAt: Date
    var ocrText: String?
    var pixelWidth: Int
    var pixelHeight: Int
    var sourceScale: Double?
    var kind: HistoryCaptureKind
    var projectURL: URL?
    var exportURL: URL?
    var tags: [String]
    var isFavorite: Bool
    var recoveryState: HistoryRecoveryState
    var sourceState: HistorySourceState
    var checksum: String?
    var durationSeconds: Double?
    var lastOpenedAt: Date?

    init(
        id: UUID = UUID(),
        fileName: String,
        createdAt: Date = Date(),
        ocrText: String? = nil,
        pixelWidth: Int,
        pixelHeight: Int,
        sourceScale: Double? = nil,
        kind: HistoryCaptureKind = .image,
        projectURL: URL? = nil,
        exportURL: URL? = nil,
        tags: [String] = [],
        isFavorite: Bool = false,
        recoveryState: HistoryRecoveryState = .none,
        sourceState: HistorySourceState = .available,
        checksum: String? = nil,
        durationSeconds: Double? = nil,
        lastOpenedAt: Date? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.createdAt = createdAt
        self.ocrText = ocrText
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.sourceScale = sourceScale.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.kind = kind
        self.projectURL = projectURL
        self.exportURL = exportURL
        self.tags = Self.normalizedTags(tags)
        self.isFavorite = isFavorite
        self.recoveryState = recoveryState
        self.sourceState = sourceState
        self.checksum = checksum
        self.durationSeconds = durationSeconds
        self.lastOpenedAt = lastOpenedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        fileName = try values.decode(String.self, forKey: .fileName)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        ocrText = try values.decodeIfPresent(String.self, forKey: .ocrText)
        pixelWidth = try values.decodeIfPresent(Int.self, forKey: .pixelWidth) ?? 0
        pixelHeight = try values.decodeIfPresent(Int.self, forKey: .pixelHeight) ?? 0
        sourceScale = try values.decodeIfPresent(Double.self, forKey: .sourceScale)
            .flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        kind = try values.decodeIfPresent(HistoryCaptureKind.self, forKey: .kind) ?? .image
        projectURL = try values.decodeIfPresent(URL.self, forKey: .projectURL)
        exportURL = try values.decodeIfPresent(URL.self, forKey: .exportURL)
        tags = Self.normalizedTags(try values.decodeIfPresent([String].self, forKey: .tags) ?? [])
        isFavorite = try values.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        recoveryState = try values.decodeIfPresent(HistoryRecoveryState.self, forKey: .recoveryState) ?? .none
        sourceState = try values.decodeIfPresent(HistorySourceState.self, forKey: .sourceState) ?? .available
        checksum = try values.decodeIfPresent(String.self, forKey: .checksum)
        durationSeconds = try values.decodeIfPresent(Double.self, forKey: .durationSeconds)
        lastOpenedAt = try values.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
    }

    var fileExtension: String { (fileName as NSString).pathExtension.lowercased() }

    var searchableText: String {
        ([fileName, ocrText ?? ""] + tags).joined(separator: " ").folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: .current
        )
    }

    static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { raw in
            let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty else { return nil }
            let key = tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return seen.insert(key).inserted ? tag : nil
        }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

enum HistorySort: String, CaseIterable, Identifiable, Sendable {
    case newest = "Newest"
    case oldest = "Oldest"
    case lastOpened = "Last Opened"
    case name = "Name"
    var id: String { rawValue }
}

struct HistoryFilter: Equatable, Sendable {
    var kinds: Set<HistoryCaptureKind> = []
    var tags: Set<String> = []
    var favoritesOnly = false
    var missingOnly = false
}

struct HistoryRecoveryInput: Equatable, Sendable {
    let itemID: UUID
    let projectURL: URL
    let sourceURL: URL?
}
