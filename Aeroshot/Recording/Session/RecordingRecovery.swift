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
    static let currentSchemaVersion = 2
    static let legacySchemaVersion = 1

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
        guard schemaVersion == Self.currentSchemaVersion || schemaVersion == Self.legacySchemaVersion else {
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

    var hasOwnedMedia: Bool { schemaVersion == Self.currentSchemaVersion }
}

nonisolated struct RecordingRecoveryArtifact: Equatable, Sendable {
    let manifestURL: URL
    let manifest: RecordingRecoveryManifest
    let mediaURL: URL?
    let sessionDirectoryURL: URL?
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

    func discoverArtifacts(at date: Date) -> [RecordingRecoveryArtifact] {
        let root = directoryURL
        let decoder = JSONDecoder()
        let files = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var artifacts: [RecordingRecoveryArtifact] = []
        for url in files {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isDirectory == true, values?.isSymbolicLink != true {
                let manifestURL = url.appending(path: "manifest.json")
                guard let data = try? Data(contentsOf: manifestURL),
                      let manifest = try? decoder.decode(RecordingRecoveryManifest.self, from: data),
                      manifest.retention.interruptedSession.isRetained(at: date),
                      manifest.hasOwnedMedia,
                      url.lastPathComponent == manifest.session.sessionID.uuidString,
                      let mediaURL = validatedMediaURL(manifest: manifest, sessionDirectoryURL: url)
                else { continue }
                artifacts.append(RecordingRecoveryArtifact(
                    manifestURL: manifestURL,
                    manifest: manifest,
                    mediaURL: mediaURL,
                    sessionDirectoryURL: url
                ))
                continue
            }

            guard url.deletingLastPathComponent().standardizedFileURL == root,
                  url.pathExtension.lowercased() == "json",
                  let data = try? Data(contentsOf: url),
                  let manifest = try? decoder.decode(RecordingRecoveryManifest.self, from: data),
                  manifest.retention.interruptedSession.isRetained(at: date),
                  !manifest.hasOwnedMedia
            else { continue }
            artifacts.append(RecordingRecoveryArtifact(
                manifestURL: url,
                manifest: manifest,
                mediaURL: nil,
                sessionDirectoryURL: nil
            ))
        }

        return artifacts.sorted {
            if $0.manifest.updatedAt != $1.manifest.updatedAt {
                return $0.manifest.updatedAt > $1.manifest.updatedAt
            }
            return $0.manifest.session.sessionID.uuidString < $1.manifest.session.sessionID.uuidString
        }
    }

    func discard(_ artifact: RecordingRecoveryArtifact) throws {
        let manifestURL = artifact.manifestURL.standardizedFileURL
        let decoder = JSONDecoder()
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? decoder.decode(RecordingRecoveryManifest.self, from: data),
              manifest == artifact.manifest
        else { return }

        if manifest.hasOwnedMedia {
            let sessionDirectoryURL = directoryURL.appending(path: manifest.session.sessionID.uuidString, directoryHint: .isDirectory)
            let expectedManifestURL = sessionDirectoryURL.appending(path: "manifest.json")
            guard manifestURL == expectedManifestURL,
                  let values = try? sessionDirectoryURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true
            else { return }
            try fileManager.removeItem(at: sessionDirectoryURL)
            return
        }

        guard manifestURL.deletingLastPathComponent().standardizedFileURL == directoryURL else { return }
        try fileManager.removeItem(at: manifestURL)
    }

    private func validatedMediaURL(
        manifest: RecordingRecoveryManifest,
        sessionDirectoryURL: URL
    ) -> URL? {
        let filename = manifest.partialMedia.value
        guard filename == URL(fileURLWithPath: filename).lastPathComponent else { return nil }
        let mediaURL = sessionDirectoryURL.appending(path: filename)
        guard mediaURL.deletingLastPathComponent().standardizedFileURL == sessionDirectoryURL.standardizedFileURL,
              let values = try? mediaURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true
        else { return nil }
        return mediaURL
    }
}
