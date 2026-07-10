import Foundation
import Testing
@testable import Aeroshot

struct AeroProjectTests {
    private let fixedDate = Date(timeIntervalSince1970: 1_784_000_000)

    @Test func manifestRoundTripsWithExactRationalMediaTime() throws {
        let time = try AeroMediaTime(value: 3_003, timescale: 90_000)
        let reducedTime = try AeroMediaTime(value: 1_001, timescale: 30_000)
        #expect(time == reducedTime)

        var manifest = AeroProjectManifest(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            createdAt: fixedDate
        )
        manifest.timeline = [AeroTimelineItem(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            kind: .sourceRange,
            sourceAssetID: nil,
            timeRange: try AeroMediaTimeRange(start: time, duration: time)
        )]
        manifest.exportPresets = [AeroExportPreset(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "Exact 29.97",
            format: .mp4,
            pixelSize: try AeroPixelSize(width: 1_920, height: 1_080),
            frameRate: try AeroMediaTime(value: 30_000, timescale: 1_001)
        )]

        let data = try AeroProjectMigrator.encode(manifest)
        let decoded = try AeroProjectMigrator.decodeAndMigrate(data)

        #expect(decoded == manifest)
        #expect(decoded.timeline[0].timeRange?.start.value == 1_001)
        #expect(decoded.timeline[0].timeRange?.start.timescale == 30_000)
    }

    @Test func versionZeroManifestMigratesToCurrentDefaults() throws {
        let original = AeroProjectManifest(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            createdAt: fixedDate
        )
        var object = try #require(
            JSONSerialization.jsonObject(with: AeroProjectMigrator.encode(original)) as? [String: Any]
        )
        object["schemaVersion"] = 0
        object["projectID"] = object.removeValue(forKey: "id")
        object.removeValue(forKey: "compatibility")
        object.removeValue(forKey: "generatedCachePolicy")
        object.removeValue(forKey: "recovery")

        let migrated = try AeroProjectMigrator.decodeAndMigrate(
            JSONSerialization.data(withJSONObject: object)
        )

        #expect(migrated.schemaVersion == AeroProjectSchema.currentVersion)
        #expect(migrated.id == original.id)
        #expect(migrated.generatedCachePolicy == .default)
        #expect(migrated.recovery == .initial)
    }

    @Test func futureSchemaIsRejectedExplicitly() throws {
        var object = try #require(
            JSONSerialization.jsonObject(
                with: AeroProjectMigrator.encode(AeroProjectManifest(createdAt: fixedDate))
            ) as? [String: Any]
        )
        object["schemaVersion"] = AeroProjectSchema.currentVersion + 1
        let data = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: AeroProjectMigrationError.unsupportedFutureVersion(2)) {
            try AeroProjectMigrator.decodeAndMigrate(data)
        }
    }

    @Test func corruptManifestIsRejected() throws {
        #expect(throws: AeroProjectMigrationError.unreadableManifest) {
            try AeroProjectMigrator.decodeAndMigrate(Data("{not-json".utf8))
        }
    }

    @Test func relativePathRejectsTraversalAndAbsolutePaths() throws {
        try withPackage { store in
            try store.preparePackage()
            for path in ["../manifest.json", "assets/../../outside", "/tmp/outside", "assets//source.png", "assets\\source.png"] {
                #expect(throws: (any Error).self) {
                    try store.URL(forRelativePath: path)
                }
            }
            let safeURL = try store.URL(forRelativePath: "assets/originals/source.png")
            #expect(safeURL.path.hasSuffix("assets/originals/source.png"))

            let symlink = store.packageURL.appending(path: "assets/escape")
            let external = FileManager.default.temporaryDirectory
                .appending(path: "AeroshotExternal-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: symlink,
                withDestinationURL: external
            )
            defer {
                try? FileManager.default.removeItem(at: symlink)
                try? FileManager.default.removeItem(at: external)
            }
            #expect(throws: (any Error).self) {
                try store.URL(forRelativePath: "assets/escape/outside.dat")
            }
        }
    }

    @Test func checksumMismatchIsDetected() throws {
        try withPackage { store in
            let asset = try store.storeOriginal(
                Data("original".utf8),
                fileExtension: "png",
                metadata: imageMetadata()
            )
            _ = try store.save(manifest(with: asset))
            try Data("tampered".utf8).write(to: store.URL(forRelativePath: asset.relativePath))

            #expect(throws: AeroProjectPackageError.checksumMismatch(asset.id)) {
                try store.load()
            }
        }
    }

    @Test func immutableOriginalCannotBeOverwrittenOrRebound() throws {
        try withPackage { store in
            let id = UUID()
            let asset = try store.storeOriginal(
                Data("original".utf8),
                id: id,
                fileExtension: "png",
                metadata: imageMetadata()
            )
            let saved = try store.save(manifest(with: asset))

            #expect(throws: AeroProjectPackageError.assetAlreadyExists(id)) {
                try store.storeOriginal(
                    Data("replacement".utf8),
                    id: id,
                    fileExtension: "png",
                    metadata: imageMetadata()
                )
            }

            var changed = saved
            changed.assets[0] = AeroProjectAsset(
                id: asset.id,
                relativePath: asset.relativePath,
                sha256: String(repeating: "0", count: 64),
                byteCount: asset.byteCount,
                isImmutableOriginal: true,
                metadata: asset.metadata
            )
            #expect(throws: AeroProjectPackageError.immutableOriginalChanged(id)) {
                try store.save(changed)
            }
        }
    }

    @Test func failedAtomicSavePreservesCurrentManifest() throws {
        struct InjectedFailure: Error {}

        try withPackage { store in
            let first = try store.save(AeroProjectManifest(createdAt: fixedDate))
            var changed = first
            changed.canvas.background = .transparent

            #expect(throws: InjectedFailure.self) {
                try store.save(changed) { stage in
                    if stage == .beforeAtomicReplacement { throw InjectedFailure() }
                }
            }

            let reloaded = try store.load()
            #expect(reloaded == first)
            #expect(reloaded.canvas.background == .source)
        }
    }

    @Test func corruptCurrentManifestRecoversLatestValidPriorGeneration() throws {
        try withPackage { store in
            let first = try store.save(AeroProjectManifest(createdAt: fixedDate))
            var second = first
            second.canvas.background = .transparent
            _ = try store.save(second)

            try Data("corrupt".utf8).write(
                to: store.packageURL.appending(path: AeroProjectPackageStore.manifestFileName)
            )

            let recovered = try store.loadRecoveringIfNeeded()
            #expect(recovered == first)
            #expect(recovered.recovery.generation == 1)
        }
    }

    @Test func autosaveCoalescesChangesAndFlushesWithoutWallClockDelay() async throws {
        try await withPackage { store in
            let coordinator = AeroProjectAutosaveCoordinator(store: store, debounce: .seconds(60))
            var first = AeroProjectManifest(createdAt: fixedDate)
            first.canvas.background = .solid
            var latest = first
            latest.canvas.background = .transparent

            await coordinator.projectDidChange(first)
            await coordinator.projectDidChange(latest)
            let saved = try await coordinator.flushPendingSave()

            #expect(saved?.canvas.background == .transparent)
            let reloaded = try store.load()
            let secondFlush = try await coordinator.flushPendingSave()
            #expect(reloaded.canvas.background == .transparent)
            #expect(secondFlush == nil)
        }
    }

    private func manifest(with asset: AeroProjectAsset) -> AeroProjectManifest {
        AeroProjectManifest(
            createdAt: fixedDate,
            assets: [asset],
            primarySourceAssetID: asset.id
        )
    }

    private func imageMetadata() -> AeroMediaMetadata {
        AeroMediaMetadata(
            mediaType: .image,
            pixelSize: try! AeroPixelSize(width: 2, height: 2),
            duration: nil,
            nominalFrameRate: nil,
            colorSpaceName: "sRGB",
            hasAudio: false
        )
    }

    private func withPackage(_ body: (AeroProjectPackageStore) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AeroshotProjectTests-\(UUID().uuidString).aeroshot")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AeroProjectPackageStore(packageURL: url, now: { fixedDate })
        try body(store)
    }

    private func withPackage(
        _ body: (AeroProjectPackageStore) async throws -> Void
    ) async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "AeroshotProjectTests-\(UUID().uuidString).aeroshot")
        defer { try? FileManager.default.removeItem(at: url) }
        let date = fixedDate
        let store = AeroProjectPackageStore(packageURL: url, now: { date })
        try await body(store)
    }
}
