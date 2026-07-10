import CryptoKit
import Foundation

nonisolated enum AeroProjectPackageError: Error, Equatable {
    case invalidRelativePath(String)
    case pathEscapesPackage(String)
    case assetAlreadyExists(UUID)
    case immutableOriginalChanged(UUID)
    case missingAsset(UUID)
    case checksumMismatch(UUID)
    case byteCountMismatch(UUID)
    case duplicateAssetID(UUID)
    case duplicateOverlayID(UUID)
    case missingPrimarySource(UUID)
    case corruptManifest
    case noRecoverableGeneration
}

nonisolated enum AeroProjectSaveStage: Sendable {
    case temporaryManifestWritten
    case priorGenerationPreserved
    case beforeAtomicReplacement
}

nonisolated struct AeroProjectPackageStore: @unchecked Sendable {
    static let manifestFileName = "manifest.json"

    let packageURL: URL
    private let fileManager: FileManager
    private let now: @Sendable () -> Date

    init(
        packageURL: URL,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.packageURL = packageURL.standardizedFileURL
        self.fileManager = fileManager
        self.now = now
    }

    func preparePackage() throws {
        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: packageURL.appending(path: "assets/originals"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: packageURL.appending(path: "generated"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: packageURL.appending(path: "recovery"), withIntermediateDirectories: true)
    }

    func URL(forRelativePath relativePath: String) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\\"),
              !relativePath.contains("\0")
        else { throw AeroProjectPackageError.invalidRelativePath(relativePath) }

        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw AeroProjectPackageError.invalidRelativePath(relativePath)
        }

        let candidate = packageURL.appending(path: relativePath).standardizedFileURL
        let resolvedRoot = packageURL.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
        var prefix = packageURL
        for component in components {
            prefix.append(path: String(component))
            let resolvedPrefix = prefix.resolvingSymlinksInPath().standardizedFileURL
            guard resolvedPrefix.path == resolvedRoot.path || resolvedPrefix.path.hasPrefix(rootPath) else {
                throw AeroProjectPackageError.pathEscapesPackage(relativePath)
            }
        }
        return candidate
    }

    func storeOriginal(
        _ data: Data,
        id: UUID = UUID(),
        fileExtension: String,
        metadata: AeroMediaMetadata
    ) throws -> AeroProjectAsset {
        try preparePackage()
        let safeExtension = fileExtension.lowercased()
        guard !safeExtension.isEmpty,
              safeExtension.allSatisfy({ $0.isLetter || $0.isNumber })
        else { throw AeroProjectPackageError.invalidRelativePath(fileExtension) }

        let relativePath = "assets/originals/\(id.uuidString.lowercased()).\(safeExtension)"
        let destination = try URL(forRelativePath: relativePath)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw AeroProjectPackageError.assetAlreadyExists(id)
        }
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen])
        return AeroProjectAsset(
            id: id,
            relativePath: relativePath,
            sha256: Self.sha256(of: data),
            byteCount: Int64(data.count),
            isImmutableOriginal: true,
            metadata: metadata
        )
    }

    func load(validateAssets: Bool = true) throws -> AeroProjectManifest {
        let manifestURL = packageURL.appending(path: Self.manifestFileName)
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw AeroProjectPackageError.corruptManifest
        }
        let manifest: AeroProjectManifest
        do {
            manifest = try AeroProjectMigrator.decodeAndMigrate(data)
        } catch {
            throw error
        }
        if validateAssets { try validate(manifest) }
        return manifest
    }

    @discardableResult
    func save(
        _ manifest: AeroProjectManifest,
        failureInjector: ((AeroProjectSaveStage) throws -> Void)? = nil
    ) throws -> AeroProjectManifest {
        try preparePackage()
        let existing = try? load(validateAssets: false)
        try enforceImmutableOriginals(previous: existing, proposed: manifest)
        try validate(manifest)

        var candidate = manifest
        candidate.schemaVersion = AeroProjectSchema.currentVersion
        candidate.modifiedAt = now()
        candidate.recovery.generation = max(existing?.recovery.generation ?? 0, manifest.recovery.generation) + 1

        let manifestURL = packageURL.appending(path: Self.manifestFileName)
        let temporaryURL = packageURL.appending(path: ".manifest-\(UUID().uuidString).tmp")
        do {
            let data = try AeroProjectMigrator.encode(candidate)
            try data.write(to: temporaryURL, options: .withoutOverwriting)
            try synchronizeFile(at: temporaryURL)
            try failureInjector?(.temporaryManifestWritten)

            if let existing, fileManager.fileExists(atPath: manifestURL.path) {
                let recoveryRelativePath = "recovery/manifest-\(existing.recovery.generation).json"
                let recoveryURL = try URL(forRelativePath: recoveryRelativePath)
                if fileManager.fileExists(atPath: recoveryURL.path) {
                    try fileManager.removeItem(at: recoveryURL)
                }
                try fileManager.copyItem(at: manifestURL, to: recoveryURL)
                candidate.recovery.recoverableManifestPath = recoveryRelativePath
                let updatedData = try AeroProjectMigrator.encode(candidate)
                try updatedData.write(to: temporaryURL, options: .atomic)
                try synchronizeFile(at: temporaryURL)
                try failureInjector?(.priorGenerationPreserved)
            }

            try failureInjector?(.beforeAtomicReplacement)
            if fileManager.fileExists(atPath: manifestURL.path) {
                _ = try fileManager.replaceItemAt(manifestURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: manifestURL)
            }
            return candidate
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    func recoverLatestValidManifest() throws -> AeroProjectManifest {
        let recoveryURL = packageURL.appending(path: "recovery")
        let candidates = (try? fileManager.contentsOfDirectory(
            at: recoveryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        for candidateURL in candidates.sorted(by: { generation(of: $0) > generation(of: $1) }) {
            guard let data = try? Data(contentsOf: candidateURL),
                  let manifest = try? AeroProjectMigrator.decodeAndMigrate(data),
                  (try? validate(manifest)) != nil
            else { continue }
            return manifest
        }
        throw AeroProjectPackageError.noRecoverableGeneration
    }

    func loadRecoveringIfNeeded() throws -> AeroProjectManifest {
        do { return try load() } catch { return try recoverLatestValidManifest() }
    }

    func validate(_ manifest: AeroProjectManifest) throws {
        var assetIDs = Set<UUID>()
        for asset in manifest.assets {
            guard assetIDs.insert(asset.id).inserted else {
                throw AeroProjectPackageError.duplicateAssetID(asset.id)
            }
            let assetURL = try URL(forRelativePath: asset.relativePath)
            guard let data = try? Data(contentsOf: assetURL) else {
                throw AeroProjectPackageError.missingAsset(asset.id)
            }
            guard Int64(data.count) == asset.byteCount else {
                throw AeroProjectPackageError.byteCountMismatch(asset.id)
            }
            guard Self.sha256(of: data) == asset.sha256 else {
                throw AeroProjectPackageError.checksumMismatch(asset.id)
            }
        }
        if let primaryID = manifest.primarySourceAssetID, !assetIDs.contains(primaryID) {
            throw AeroProjectPackageError.missingPrimarySource(primaryID)
        }

        var overlayIDs = Set<UUID>()
        for overlay in manifest.overlays where !overlayIDs.insert(overlay.id).inserted {
            throw AeroProjectPackageError.duplicateOverlayID(overlay.id)
        }
    }

    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func enforceImmutableOriginals(
        previous: AeroProjectManifest?,
        proposed: AeroProjectManifest
    ) throws {
        guard let previous else { return }
        let proposedByID = Dictionary(uniqueKeysWithValues: proposed.assets.map { ($0.id, $0) })
        for original in previous.assets where original.isImmutableOriginal {
            guard let next = proposedByID[original.id], next == original else {
                throw AeroProjectPackageError.immutableOriginalChanged(original.id)
            }
            let url = try URL(forRelativePath: original.relativePath)
            guard let data = try? Data(contentsOf: url), Self.sha256(of: data) == original.sha256 else {
                throw AeroProjectPackageError.immutableOriginalChanged(original.id)
            }
        }
    }

    private func synchronizeFile(at url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.synchronize()
        try handle.close()
    }

    private func generation(of url: URL) -> Int {
        let name = url.deletingPathExtension().lastPathComponent
        return Int(name.replacingOccurrences(of: "manifest-", with: "")) ?? -1
    }
}
