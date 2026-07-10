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
        let expected = store.indexProject(at: recoverable, recoveryState: .recoverable)
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
}
