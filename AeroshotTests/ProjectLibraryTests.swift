import CoreGraphics
import CryptoKit
import Foundation
import Testing
@testable import Aeroshot

@MainActor
struct ProjectLibraryTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func legacyIndexMigratesWithBackwardCompatibleDefaults() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let artifact = directory.appendingPathComponent("legacy.png")
        try Data([1, 2, 3]).write(to: artifact)
        let legacy: [String: Any] = [
            "id": id.uuidString,
            "fileName": "legacy.png",
            "createdAt": 0,
            "pixelWidth": 640,
            "pixelHeight": 480,
            "kind": "image"
        ]
        let data = try JSONSerialization.data(withJSONObject: [legacy])
        try data.write(to: directory.appendingPathComponent("index.json"))

        let store = HistoryStore(directory: directory, trashHandler: { _ in })

        let item = try #require(store.items.first)
        #expect(item.id == id)
        #expect(item.tags.isEmpty)
        #expect(!item.isFavorite)
        #expect(item.sourceState == .available)
        #expect(item.recoveryState == .none)
    }

    @Test func searchFiltersTagsFavoritesKindsAndSortsDeterministically() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("source-one.png")
        let secondURL = directory.appendingPathComponent("source-two.gif")
        try Data([1]).write(to: firstURL)
        try Data([2]).write(to: secondURL)
        let store = HistoryStore(directory: directory, trashHandler: { _ in })
        let first = try #require(store.addArtifact(from: firstURL, kind: .image))
        _ = try #require(store.addArtifact(from: secondURL, kind: .gif))
        store.setTags(["Launch", "launch", "  Work  "], for: first)
        store.toggleFavorite(first)

        let tagFilter = HistoryFilter(kinds: [.image], tags: ["launch"], favoritesOnly: true)
        #expect(store.search("source", filter: tagFilter) .map(\.id) == [first.id])
        let nameSorted = store.search("", sort: .name)
        #expect(nameSorted.map(\.fileName) == nameSorted.map(\.fileName).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        })
        #expect(store.items.first(where: { $0.id == first.id })?.tags == ["Launch", "Work"])
    }

    @Test func reconciliationRemovesChecksumDuplicatesAndMarksMissingSources() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("outside.dat")
        try Data("same".utf8).write(to: source)
        let store = HistoryStore(directory: directory, trashHandler: { _ in })
        let original = try #require(store.addArtifact(from: source, kind: .recording))
        let duplicate = try #require(store.addArtifact(from: source, kind: .recording))
        try FileManager.default.removeItem(at: store.fileURL(for: original))

        let result = store.reconcile()

        #expect(result.removedDuplicateIDs == [original.id])
        #expect(result.missingItemIDs == [original.id])
        #expect(store.items.map(\.id) == [duplicate.id])
    }

    @Test func recoveryDiscoveryReturnsOnlyRecoverableProjects() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recoverable = directory.appendingPathComponent("Recoverable.aeroshot", isDirectory: true)
        let healthy = directory.appendingPathComponent("Healthy.aeroshot", isDirectory: true)
        try FileManager.default.createDirectory(at: recoverable, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: healthy, withIntermediateDirectories: true)
        let store = HistoryStore(directory: directory, trashHandler: { _ in })
        let expected = try #require(store.indexProject(at: recoverable, recoveryState: .recoverable))
        _ = store.indexProject(at: healthy)

        #expect(store.recoveryInputs() == [HistoryRecoveryInput(itemID: expected.id, projectURL: recoverable, sourceURL: nil)])
    }

    @Test func successfulDeleteUsesTrashAndPersistsRemoval() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("delete-me.gif")
        try Data([9]).write(to: source)
        var trashed: [URL] = []
        let store = HistoryStore(directory: directory, trashHandler: { trashed.append($0) })
        let item = try #require(store.addArtifact(from: source, kind: .gif))

        #expect(store.remove(item))
        #expect(trashed == [store.fileURL(for: item)])
        let reloaded = HistoryStore(directory: directory, trashHandler: { _ in })
        #expect(reloaded.items.isEmpty)
    }

    @Test func removingIndexedProjectOnlyRemovesItsIndexEntry() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("History", isDirectory: true)
        let project = root.appendingPathComponent("External.aeroshot", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        var trashed: [URL] = []
        let store = HistoryStore(directory: directory, trashHandler: { trashed.append($0) })
        let item = try #require(store.indexProject(at: project))

        #expect(store.remove(item))
        #expect(trashed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: project.path))
        #expect(store.items.allSatisfy { $0.id != item.id })
        #expect(HistoryStore(directory: directory, trashHandler: { _ in }).items.isEmpty)
    }

    @Test func failedTrashKeepsItemAndReportsTruthfulError() throws {
        struct TrashFailure: Error {}
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("keep-me.mov")
        try Data([8]).write(to: source)
        let store = HistoryStore(directory: directory, trashHandler: { _ in throw TrashFailure() })
        let item = try #require(store.addArtifact(from: source, kind: .recording))

        #expect(!store.remove(item))
        #expect(store.items.contains(where: { $0.id == item.id }))
        guard case .moveToTrash = store.lastError else {
            Issue.record("Expected a move-to-Trash error")
            return
        }
    }

    @Test func failedRetentionTrashKeepsTheArtifactIndexed() throws {
        struct TrashFailure: Error {}
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstSource = directory.appendingPathComponent("first.mov")
        let secondSource = directory.appendingPathComponent("second.mov")
        try Data([1]).write(to: firstSource)
        try Data([2]).write(to: secondSource)
        let store = HistoryStore(
            directory: directory,
            maxItems: 1,
            trashHandler: { _ in throw TrashFailure() }
        )
        let first = try #require(store.addArtifact(from: firstSource, kind: .recording))
        _ = try #require(store.addArtifact(from: secondSource, kind: .recording))

        #expect(store.items.contains(where: { $0.id == first.id }))
        #expect(HistoryStore(directory: directory, trashHandler: { _ in }).items.contains(where: { $0.id == first.id }))
        #expect(FileManager.default.fileExists(atPath: store.fileURL(for: first).path))
    }

    @Test func failedRemovalIndexWriteKeepsItemAndArtifact() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("keep-on-index-failure.mov")
        try Data([8]).write(to: source)
        let store = HistoryStore(directory: directory, trashHandler: { _ in })
        let item = try #require(store.addArtifact(from: source, kind: .recording))
        try FileManager.default.removeItem(at: directory.appendingPathComponent("index.json"))
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("index.json"),
            withIntermediateDirectories: false
        )

        #expect(!store.remove(item))
        #expect(store.items.contains(where: { $0.id == item.id }))
        #expect(FileManager.default.fileExists(atPath: store.fileURL(for: item).path))
        guard case .writeIndex = store.lastError else {
            Issue.record("Expected an index-write error")
            return
        }
    }

    @Test func removalJournalRecoversAfterCompensationWriteFailure() throws {
        struct TrashFailure: Error {}
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("recover-after-failed-trash.mov")
        try Data([7]).write(to: source)
        let index = directory.appendingPathComponent("index.json")
        let store = HistoryStore(directory: directory, trashHandler: { _ in
            try FileManager.default.removeItem(at: index)
            try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
            throw TrashFailure()
        })
        let item = try #require(store.addArtifact(from: source, kind: .recording))

        #expect(!store.remove(item))
        try FileManager.default.removeItem(at: index)
        let recovered = HistoryStore(directory: directory, trashHandler: { _ in })

        #expect(recovered.items.contains(where: { $0.id == item.id }))
        #expect(FileManager.default.fileExists(atPath: recovered.fileURL(for: item).path))
    }

    @Test func failedCapturePersistenceDoesNotPublishMissingHistoryItems() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("not-a-directory")
        try Data().write(to: file)
        let store = HistoryStore(directory: file, trashHandler: { _ in })
        let image = try #require(CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage())

        #expect(store.add(image: image) == nil)
        #expect(store.add(textCapture: "capture") == nil)
        #expect(store.items.isEmpty)
    }

    @Test func failedIndexPersistenceRollsBackCaptureAndArtifact() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(directory: directory, trashHandler: { _ in })
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("index.json"),
            withIntermediateDirectories: false
        )
        let image = try #require(CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage())

        #expect(store.add(image: image) == nil)
        #expect(store.items.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["index.json"])
        guard case .writeIndex = store.lastError else {
            Issue.record("Expected an index-write error")
            return
        }
    }

    @Test func checksumStreamsAcrossChunks() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("large-recording.bin")
        let data = Data(repeating: 0xA5, count: 1_048_576 + 17)
        try data.write(to: url)
        let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        #expect(HistoryStore.checksum(of: url) == expected)
    }

    @Test func recordingImportUsesAUtilityTask() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Aeroshot/History/HistoryStore.swift"))
        let start = try #require(source.range(of: "func add(recordingFrom"))
        let end = try #require(source.range(of: "func addArtifact", range: start.upperBound..<source.endIndex))

        #expect(source[start.lowerBound..<end.lowerBound].contains("Task.detached(priority: .utility)"))
    }

    @Test func recordingImportCopiesAndIndexesTheArtifact() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("recording.mp4")
        let bytes = Data(repeating: 0x5A, count: 1_048_576 + 17)
        try bytes.write(to: source)
        let store = HistoryStore(directory: directory, trashHandler: { _ in })

        let item = try #require(await store.add(recordingFrom: source, durationSeconds: 42))

        #expect(item.kind == .recording)
        #expect(item.durationSeconds == 42)
        #expect(try Data(contentsOf: store.fileURL(for: item)) == bytes)
        #expect(item.checksum == HistoryStore.checksum(of: source))
    }
}
