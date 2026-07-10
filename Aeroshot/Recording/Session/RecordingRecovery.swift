import Foundation

nonisolated enum RecordingRecoveryError: Error, Equatable {
    case invalidRelativePath(String)
    case unsupportedSchemaVersion(Int)
    case noPartialMedia
    case corruptManifest
}

/// Validated package-relative reference. Absolute paths, traversal, empty path
/// components, backslashes, and NULs are rejected during creation and decode.
nonisolated struct RecordingRelativePath: Codable, Equatable, Hashable, Sendable {
    let value: String

    init(_ value: String) throws {
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              !value.contains("\\"),
              !value.contains("\0"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { throw RecordingRecoveryError.invalidRelativePath(value) }
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

nonisolated enum RecordingRecoveryLifecycle: String, Codable, Equatable, Sendable {
    case recording
    case paused
    case stopping
}

nonisolated enum RecordingRecoveryRetention: Codable, Equatable, Sendable {
    case deleteImmediately
    case retainUntil(Date)
    case retainUntilUserDecision

    func isRetained(at date: Date) -> Bool {
        switch self {
        case .deleteImmediately: false
        case .retainUntil(let expiration): expiration > date
        case .retainUntilUserDecision: true
        }
    }
}

nonisolated struct RecordingPrivacyRetentionPolicy: Codable, Equatable, Sendable {
    let interruptedSession: RecordingRecoveryRetention
    let deleteOnExplicitCancel: Bool
    let capturedContentExcludedFromDiagnostics: Bool
    let eventMetadataExcludedFromDiagnostics: Bool

    static let privateByDefault = RecordingPrivacyRetentionPolicy(
        interruptedSession: .retainUntilUserDecision,
        deleteOnExplicitCancel: true,
        capturedContentExcludedFromDiagnostics: true,
        eventMetadataExcludedFromDiagnostics: true
    )
}

nonisolated struct RecordingRecoveryManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let session: RecordingSessionSnapshot
    let lifecycle: RecordingRecoveryLifecycle
    let partialMedia: RecordingRelativePath
    let eventMetadata: [RecordingRelativePath]
    let updatedAt: Date
    let retention: RecordingPrivacyRetentionPolicy

    init(
        session: RecordingSessionSnapshot,
        lifecycle: RecordingRecoveryLifecycle,
        partialMedia: RecordingRelativePath,
        eventMetadata: [RecordingRelativePath] = [],
        updatedAt: Date,
        retention: RecordingPrivacyRetentionPolicy = .privateByDefault
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.session = session
        self.lifecycle = lifecycle
        self.partialMedia = partialMedia
        self.eventMetadata = eventMetadata
        self.updatedAt = updatedAt
        self.retention = retention
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, session, lifecycle, partialMedia, eventMetadata, updatedAt, retention
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw RecordingRecoveryError.unsupportedSchemaVersion(schemaVersion)
        }
        self.schemaVersion = schemaVersion
        session = try values.decode(RecordingSessionSnapshot.self, forKey: .session)
        lifecycle = try values.decode(RecordingRecoveryLifecycle.self, forKey: .lifecycle)
        partialMedia = try values.decode(RecordingRelativePath.self, forKey: .partialMedia)
        eventMetadata = try values.decode([RecordingRelativePath].self, forKey: .eventMetadata)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        retention = try values.decode(RecordingPrivacyRetentionPolicy.self, forKey: .retention)
    }
}

nonisolated struct RecordingRecoveryStore: @unchecked Sendable {
    let directoryURL: URL
    private let fileManager: FileManager

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL.standardizedFileURL
        self.fileManager = fileManager
    }

    func discover(at date: Date) -> [RecordingRecoveryManifest] {
        let files = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url -> RecordingRecoveryManifest? in
                guard let data = try? Data(contentsOf: url),
                      let manifest = try? decoder.decode(RecordingRecoveryManifest.self, from: data),
                      manifest.retention.interruptedSession.isRetained(at: date)
                else { return nil }
                return manifest
            }
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.session.sessionID.uuidString < $1.session.sessionID.uuidString
            }
    }
}
