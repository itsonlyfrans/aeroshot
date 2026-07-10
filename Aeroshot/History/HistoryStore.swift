import AppKit
import Combine
import CryptoKit

enum HistoryStoreError: LocalizedError, Equatable {
    case createDirectory(String)
    case readIndex(String)
    case writeIndex(String)
    case copyArtifact(String)
    case moveToTrash(String)

    var errorDescription: String? {
        switch self {
        case .createDirectory(let reason): "The library folder could not be created: \(reason)"
        case .readIndex(let reason): "The library index could not be read: \(reason)"
        case .writeIndex(let reason): "Changes could not be saved: \(reason)"
        case .copyArtifact(let reason): "The artifact could not be added: \(reason)"
        case .moveToTrash(let reason): "The artifact could not be moved to Trash: \(reason)"
        }
    }
}

struct HistoryReconciliationResult: Equatable {
    let removedDuplicateIDs: [UUID]
    let missingItemIDs: [UUID]
}

/// Atomic, local-only persistence for captures and editable project references.
@MainActor
final class HistoryStore: ObservableObject {
    typealias TrashHandler = (URL) throws -> Void

    static let shared = HistoryStore()

    @Published private(set) var items: [HistoryItem] = []
    @Published private(set) var lastError: HistoryStoreError?

    private let maxItems: Int
    private let fileManager: FileManager
    private let trashHandler: TrashHandler
    let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    convenience init() {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacy = base.appendingPathComponent("ScreenCapture/History", isDirectory: true)
        let current = base.appendingPathComponent("Aeroshot/History", isDirectory: true)
        if manager.fileExists(atPath: legacy.path), !manager.fileExists(atPath: current.path) {
            try? manager.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? manager.moveItem(at: legacy, to: current)
        }
        self.init(directory: current)
    }

    init(
        directory: URL,
        fileManager: FileManager = .default,
        maxItems: Int = 500,
        trashHandler: TrashHandler? = nil
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.maxItems = maxItems
        self.trashHandler = trashHandler ?? { url in
            var result: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            lastError = .createDirectory(error.localizedDescription)
        }
        load()
    }

    func fileURL(for item: HistoryItem) -> URL { directory.appendingPathComponent(item.fileName) }

    func primaryURL(for item: HistoryItem) -> URL? {
        if let projectURL = item.projectURL, fileManager.fileExists(atPath: projectURL.path) { return projectURL }
        let stored = fileURL(for: item)
        if fileManager.fileExists(atPath: stored.path) { return stored }
        if let exportURL = item.exportURL, fileManager.fileExists(atPath: exportURL.path) { return exportURL }
        return nil
    }

    @discardableResult
    func add(image: CGImage) -> HistoryItem {
        let id = UUID()
        let name = "\(id.uuidString).png"
        let url = directory.appendingPathComponent(name)
        try? ImageExporter.write(image, to: url, format: .png)
        let item = HistoryItem(fileName: name, pixelWidth: image.width, pixelHeight: image.height,
                               kind: .image, checksum: Self.checksum(of: url))
        insert(item)
        return item
    }

    @discardableResult
    func add(textCapture text: String) -> HistoryItem {
        let id = UUID()
        let name = "\(id.uuidString).txt"
        let url = directory.appendingPathComponent(name)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
        let item = HistoryItem(fileName: name, ocrText: text, pixelWidth: lines, pixelHeight: 0,
                               kind: .text, checksum: Self.checksum(of: url))
        insert(item)
        return item
    }

    @discardableResult
    func add(recordingFrom sourceURL: URL, durationSeconds: Int) -> HistoryItem? {
        addArtifact(from: sourceURL,
                    kind: sourceURL.pathExtension.lowercased() == "gif" ? .gif : .recording,
                    durationSeconds: Double(max(durationSeconds, 0)))
    }

    @discardableResult
    func addArtifact(
        from sourceURL: URL,
        kind: HistoryCaptureKind,
        projectURL: URL? = nil,
        exportURL: URL? = nil,
        dimensions: CGSize? = nil,
        durationSeconds: Double? = nil,
        recoveryState: HistoryRecoveryState = .none
    ) -> HistoryItem? {
        let id = UUID()
        let sourceName = sourceURL.lastPathComponent
        let name = sourceName.isEmpty ? id.uuidString : "\(id.uuidString)-\(sourceName)"
        let destination = directory.appendingPathComponent(name)
        do {
            try fileManager.copyItem(at: sourceURL, to: destination)
        } catch {
            lastError = .copyArtifact(error.localizedDescription)
            return nil
        }
        let item = HistoryItem(
            id: id, fileName: name,
            pixelWidth: Int(dimensions?.width ?? 0), pixelHeight: Int(dimensions?.height ?? 0),
            kind: kind, projectURL: projectURL, exportURL: exportURL,
            recoveryState: recoveryState, checksum: Self.checksum(of: destination),
            durationSeconds: durationSeconds
        )
        insert(item)
        return item
    }

    /// Indexes an existing local project without copying or modifying its package.
    @discardableResult
    func indexProject(
        at projectURL: URL,
        exportURL: URL? = nil,
        recoveryState: HistoryRecoveryState = .none
    ) -> HistoryItem {
        let item = HistoryItem(fileName: "", pixelWidth: 0, pixelHeight: 0, kind: .project,
                               projectURL: projectURL, exportURL: exportURL,
                               recoveryState: recoveryState,
                               sourceState: fileManager.fileExists(atPath: projectURL.path) ? .available : .missing)
        insert(item)
        return item
    }

    func setOCRText(_ text: String, for id: UUID) { update(id) { $0.ocrText = text } }
    func dismissLastError() { lastError = nil }
    func toggleFavorite(_ item: HistoryItem) { update(item.id) { $0.isFavorite.toggle() } }
    func setTags(_ tags: [String], for item: HistoryItem) { update(item.id) { $0.tags = HistoryItem.normalizedTags(tags) } }

    func markOpened(_ item: HistoryItem, at date: Date = Date()) {
        update(item.id) { $0.lastOpenedAt = date }
    }

    @discardableResult
    func remove(_ item: HistoryItem) -> Bool {
        let candidates = [item.projectURL, item.fileName.isEmpty ? nil : fileURL(for: item)].compactMap { $0 }
        do {
            for url in candidates where fileManager.fileExists(atPath: url.path) { try trashHandler(url) }
            items.removeAll { $0.id == item.id }
            try persist()
            return true
        } catch {
            lastError = .moveToTrash(error.localizedDescription)
            return false
        }
    }

    func search(
        _ query: String,
        filter: HistoryFilter = HistoryFilter(),
        sort: HistorySort = .newest
    ) -> [HistoryItem] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let wantedTags = Set(filter.tags.map {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        })
        let filtered = items.filter { item in
            (term.isEmpty || item.searchableText.contains(term))
                && (filter.kinds.isEmpty || filter.kinds.contains(item.kind))
                && (!filter.favoritesOnly || item.isFavorite)
                && (!filter.missingOnly || item.sourceState == .missing)
                && (wantedTags.isEmpty || wantedTags.isSubset(of: Set(item.tags.map {
                    $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                })))
        }
        return filtered.sorted {
            switch sort {
            case .newest: $0.createdAt > $1.createdAt
            case .oldest: $0.createdAt < $1.createdAt
            case .lastOpened: ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast)
            case .name: $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending
            }
        }
    }

    @discardableResult
    func reconcile() -> HistoryReconciliationResult {
        var seen = Set<String>()
        var duplicates: [UUID] = []
        var missing: [UUID] = []
        for index in items.indices {
            let urlKey = primaryCandidateURL(for: items[index])?.standardizedFileURL.path.lowercased()
            let identity = items[index].checksum.map { "checksum:\($0)" } ?? urlKey.map { "url:\($0)" }
            if let identity, !seen.insert(identity).inserted { duplicates.append(items[index].id) }
            let exists = primaryCandidateURL(for: items[index]).map { fileManager.fileExists(atPath: $0.path) } ?? false
            items[index].sourceState = exists ? .available : .missing
            if !exists { missing.append(items[index].id) }
        }
        items.removeAll { duplicates.contains($0.id) }
        trySave()
        return .init(removedDuplicateIDs: duplicates, missingItemIDs: missing)
    }

    func recoveryInputs() -> [HistoryRecoveryInput] {
        items.compactMap { item in
            guard item.recoveryState == .recoverable, let projectURL = item.projectURL else { return nil }
            let source = item.fileName.isEmpty ? item.exportURL : fileURL(for: item)
            return HistoryRecoveryInput(itemID: item.id, projectURL: projectURL, sourceURL: source)
        }
    }

    private func primaryCandidateURL(for item: HistoryItem) -> URL? {
        item.projectURL ?? (item.fileName.isEmpty ? item.exportURL : fileURL(for: item))
    }

    private func insert(_ item: HistoryItem) {
        items.insert(item, at: 0)
        trim()
        trySave()
    }

    private func update(_ id: UUID, mutation: (inout HistoryItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutation(&items[index])
        trySave()
    }

    private func trim() {
        while items.count > maxItems {
            let candidate = items[items.count - 1]
            do {
                if !candidate.fileName.isEmpty, fileManager.fileExists(atPath: fileURL(for: candidate).path) {
                    try trashHandler(fileURL(for: candidate))
                }
                items.removeLast()
            } catch {
                lastError = .moveToTrash(error.localizedDescription)
                break
            }
        }
    }

    private func load() {
        guard fileManager.fileExists(atPath: indexURL.path) else { return }
        do {
            items = try JSONDecoder().decode([HistoryItem].self, from: Data(contentsOf: indexURL))
            _ = reconcile()
        } catch {
            lastError = .readIndex(error.localizedDescription)
        }
    }

    private func trySave() {
        do { try persist() }
        catch { lastError = .writeIndex(error.localizedDescription) }
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(items)
        try data.write(to: indexURL, options: .atomic)
    }

    nonisolated static func checksum(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
