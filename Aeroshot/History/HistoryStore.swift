import AppKit
import Combine
import CryptoKit
import os

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

nonisolated private struct HistoryReconciliationScan: Sendable {
    let items: [HistoryItem]
    let duplicateIDs: [UUID]
    let missingIDs: [UUID]
}

nonisolated private enum HistoryReconciler {
    static func scan(
        items: [HistoryItem],
        directory: URL,
        fileExists: (URL) -> Bool
    ) -> HistoryReconciliationScan {
        var candidateItems = items
        var seen: [String: (id: UUID, exists: Bool)] = [:]
        var duplicates: [UUID] = []
        var missing: [UUID] = []
        for index in candidateItems.indices {
            let item = candidateItems[index]
            let url = item.projectURL ?? (item.fileName.isEmpty
                ? item.exportURL
                : directory.appendingPathComponent(item.fileName))
            let urlKey = url?.standardizedFileURL.path.lowercased()
            let identity = item.checksum.map { "checksum:\($0)" } ?? urlKey.map { "url:\($0)" }
            let exists = url.map(fileExists) ?? false
            if let identity, let retained = seen[identity] {
                if !retained.exists, exists {
                    duplicates.append(retained.id)
                    seen[identity] = (item.id, true)
                } else {
                    duplicates.append(item.id)
                }
            } else if let identity {
                seen[identity] = (item.id, exists)
            }
            candidateItems[index].sourceState = exists ? .available : .missing
            if !exists { missing.append(item.id) }
        }
        return .init(items: candidateItems, duplicateIDs: duplicates, missingIDs: missing)
    }
}

/// Owns every index read and write so snapshots cannot race on disk.
private final class HistoryIndexPersistence: @unchecked Sendable {
    private let indexURL: URL
    private let queue = DispatchQueue(label: "com.aeroshot.history-index", qos: .utility)

    init(indexURL: URL) {
        self.indexURL = indexURL
    }

    func load() throws -> [HistoryItem] {
        try queue.sync {
            try JSONDecoder().decode([HistoryItem].self, from: Data(contentsOf: indexURL))
        }
    }

    func save(_ items: [HistoryItem]) throws {
        // ponytail: synchronous handoff keeps commits atomic; make this actor-based only if
        // a measured 500-item index write exceeds the main-thread stall budget.
        try queue.sync {
            let data = try JSONEncoder().encode(items)
            try data.write(to: indexURL, options: .atomic)
        }
    }
}

/// Atomic, local-only persistence for captures and editable project references.
@MainActor
final class HistoryStore: ObservableObject {
    typealias TrashHandler = (URL) throws -> Void

    static let shared = HistoryStore()

    @Published private(set) var items: [HistoryItem] = []
    @Published private(set) var lastError: HistoryStoreError?
    @Published private(set) var isReconciling = false

    private let maxItems: Int
    private let fileManager: FileManager
    private let trashHandler: TrashHandler
    private let persistence: HistoryIndexPersistence
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
        self.init(directory: current, reconcileOnLoad: false)
        Task { [weak self] in _ = await self?.reconcileInBackground() }
    }

    init(
        directory: URL,
        fileManager: FileManager = .default,
        maxItems: Int = 500,
        trashHandler: TrashHandler? = nil,
        reconcileOnLoad: Bool = true
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.maxItems = maxItems
        self.persistence = HistoryIndexPersistence(indexURL: directory.appendingPathComponent("index.json"))
        self.trashHandler = trashHandler ?? { url in
            var result: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            lastError = .createDirectory(error.localizedDescription)
        }
        let loadState = PerformanceInstrumentation.signposter.beginInterval("HistoryLoad")
        load(reconcileOnLoad: reconcileOnLoad)
        PerformanceInstrumentation.signposter.endInterval("HistoryLoad", loadState)
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
    func add(image: CGImage, sourceScale: CGFloat = 1) -> HistoryItem? {
        let id = UUID()
        let name = "\(id.uuidString).png"
        let url = directory.appendingPathComponent(name)
        do {
            try ImageExporter.write(image, to: url, format: .png, scale: sourceScale)
        } catch {
            lastError = .copyArtifact(error.localizedDescription)
            return nil
        }
        let item = HistoryItem(fileName: name, pixelWidth: image.width, pixelHeight: image.height,
                               sourceScale: Double(sourceScale),
                               kind: .image, checksum: Self.checksum(of: url))
        guard insert(item) else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return item
    }

    @discardableResult
    func add(
        encodedImage data: Data,
        pixelWidth: Int,
        pixelHeight: Int,
        sourceScale: CGFloat = 1
    ) async -> HistoryItem? {
        let id = UUID()
        let name = "\(id.uuidString).png"
        let url = directory.appendingPathComponent(name)
        let result = await Task.detached(priority: .utility) {
            do {
                try data.write(to: url, options: .atomic)
                let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                return Result<String, Error>.success(checksum)
            } catch {
                return .failure(error)
            }
        }.value
        let checksum: String
        switch result {
        case .success(let value): checksum = value
        case .failure(let error):
            lastError = .copyArtifact(error.localizedDescription)
            return nil
        }
        guard !Task.isCancelled else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        let item = HistoryItem(
            id: id,
            fileName: name,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            sourceScale: Double(sourceScale),
            kind: .image,
            checksum: checksum
        )
        guard insert(item) else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return item
    }

    @discardableResult
    func add(textCapture text: String) -> HistoryItem? {
        let id = UUID()
        let name = "\(id.uuidString).txt"
        let url = directory.appendingPathComponent(name)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            lastError = .copyArtifact(error.localizedDescription)
            return nil
        }
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
        let item = HistoryItem(fileName: name, ocrText: text, pixelWidth: lines, pixelHeight: 0,
                               kind: .text, checksum: Self.checksum(of: url))
        guard insert(item) else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return item
    }

    @discardableResult
    func add(recordingFrom sourceURL: URL, durationSeconds: Int) async -> HistoryItem? {
        let id = UUID()
        let sourceName = sourceURL.lastPathComponent
        let name = sourceName.isEmpty ? id.uuidString : "\(id.uuidString)-\(sourceName)"
        let destination = directory.appendingPathComponent(name)
        let result = await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            do {
                try fileManager.copyItem(at: sourceURL, to: destination)
                return Result<String?, Error>.success(Self.checksum(of: destination))
            } catch {
                try? fileManager.removeItem(at: destination)
                return .failure(error)
            }
        }.value
        let checksum: String?
        switch result {
        case .success(let value): checksum = value
        case .failure(let error):
            lastError = .copyArtifact(error.localizedDescription)
            return nil
        }
        guard !Task.isCancelled else {
            try? fileManager.removeItem(at: destination)
            return nil
        }
        let item = HistoryItem(
            id: id,
            fileName: name,
            pixelWidth: 0,
            pixelHeight: 0,
            kind: sourceURL.pathExtension.lowercased() == "gif" ? .gif : .recording,
            checksum: checksum,
            durationSeconds: Double(max(durationSeconds, 0))
        )
        guard insert(item) else {
            try? fileManager.removeItem(at: destination)
            return nil
        }
        return item
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
        guard insert(item) else {
            try? fileManager.removeItem(at: destination)
            return nil
        }
        return item
    }

    /// Indexes an existing local project without copying or modifying its package.
    @discardableResult
    func indexProject(
        at projectURL: URL,
        exportURL: URL? = nil,
        recoveryState: HistoryRecoveryState = .none
    ) -> HistoryItem? {
        let item = HistoryItem(fileName: "", pixelWidth: 0, pixelHeight: 0, kind: .project,
                               projectURL: projectURL, exportURL: exportURL,
                               recoveryState: recoveryState,
                               sourceState: fileManager.fileExists(atPath: projectURL.path) ? .available : .missing)
        return insert(item) ? item : nil
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
        let ownedFile = item.fileName.isEmpty ? nil : fileURL(for: item)
        let journalsRemoval = ownedFile.map { fileManager.fileExists(atPath: $0.path) } == true
        if journalsRemoval, !writeRemovalJournal(for: item) { return false }
        let previousItems = items
        var candidateItems = items
        candidateItems.removeAll { $0.id == item.id }
        do {
            try persist(candidateItems)
        } catch {
            clearRemovalJournal(for: item)
            lastError = .writeIndex(error.localizedDescription)
            return false
        }
        do {
            if let ownedFile, fileManager.fileExists(atPath: ownedFile.path) { try trashHandler(ownedFile) }
            clearRemovalJournal(for: item)
            items = candidateItems
            return true
        } catch {
            do {
                try persist(previousItems)
                clearRemovalJournal(for: item)
                lastError = .moveToTrash(error.localizedDescription)
            } catch {
                lastError = .writeIndex(error.localizedDescription)
            }
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
        let scan = HistoryReconciler.scan(items: items, directory: directory) {
            fileManager.fileExists(atPath: $0.path)
        }
        return apply(scan)
    }

    @discardableResult
    func reconcileInBackground() async -> HistoryReconciliationResult? {
        guard !items.isEmpty else { return .init(removedDuplicateIDs: [], missingItemIDs: []) }
        isReconciling = true
        defer { isReconciling = false }
        while !Task.isCancelled {
            let snapshot = items
            let directory = directory
            let scan = await Task.detached(priority: .utility) {
                HistoryReconciler.scan(items: snapshot, directory: directory) {
                    FileManager.default.fileExists(atPath: $0.path)
                }
            }.value
            guard !Task.isCancelled else { return nil }
            if items == snapshot { return apply(scan) }
        }
        return nil
    }

    private func apply(_ scan: HistoryReconciliationScan) -> HistoryReconciliationResult {
        do {
            try persist(scan.items)
            items = scan.items
        } catch {
            lastError = .writeIndex(error.localizedDescription)
            return .init(removedDuplicateIDs: [], missingItemIDs: scan.missingIDs)
        }
        let removed = scan.duplicateIDs.filter { id in
            guard let item = items.first(where: { $0.id == id }) else { return false }
            return remove(item)
        }
        return .init(removedDuplicateIDs: removed, missingItemIDs: scan.missingIDs)
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

    private func insert(_ item: HistoryItem) -> Bool {
        var candidateItems = items
        candidateItems.insert(item, at: 0)
        let overflow = Array(candidateItems.dropFirst(maxItems))
        let removable = overflow.filter { candidate in
            let url = fileURL(for: candidate)
            return candidate.fileName.isEmpty
                || !fileManager.fileExists(atPath: url.path)
                || writeRemovalJournal(for: candidate)
        }
        let removableIDs = Set(removable.map(\.id))
        candidateItems.removeAll { removableIDs.contains($0.id) }
        do {
            try persist(candidateItems)
        } catch {
            removable.forEach(clearRemovalJournal)
            lastError = .writeIndex(error.localizedDescription)
            return false
        }
        for candidate in removable {
            do {
                let url = fileURL(for: candidate)
                if !candidate.fileName.isEmpty, fileManager.fileExists(atPath: url.path) {
                    try trashHandler(url)
                }
                clearRemovalJournal(for: candidate)
            } catch {
                lastError = .moveToTrash(error.localizedDescription)
                candidateItems.append(candidate)
                do {
                    try persist(candidateItems)
                    clearRemovalJournal(for: candidate)
                } catch {
                    lastError = .writeIndex(error.localizedDescription)
                }
            }
        }
        items = candidateItems
        return true
    }

    private func writeRemovalJournal(for item: HistoryItem) -> Bool {
        do {
            let data = try JSONEncoder().encode(item)
            try data.write(to: removalJournalURL(for: item), options: .atomic)
            return true
        } catch {
            lastError = .writeIndex(error.localizedDescription)
            return false
        }
    }

    private func clearRemovalJournal(for item: HistoryItem) {
        try? fileManager.removeItem(at: removalJournalURL(for: item))
    }

    private func removalJournalURL(for item: HistoryItem) -> URL {
        directory.appendingPathComponent(".pending-removal-\(item.id.uuidString).json")
    }

    private func recoverPendingRemovals() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        var candidateItems = items
        var recovered: [(item: HistoryItem, journal: URL)] = []
        for journal in urls where journal.lastPathComponent.hasPrefix(".pending-removal-") {
            guard let data = try? Data(contentsOf: journal),
                  let item = try? JSONDecoder().decode(HistoryItem.self, from: data)
            else { continue }
            let artifactExists = !item.fileName.isEmpty
                && fileManager.fileExists(atPath: fileURL(for: item).path)
            guard artifactExists else {
                try? fileManager.removeItem(at: journal)
                continue
            }
            guard !candidateItems.contains(where: { $0.id == item.id }) else {
                try? fileManager.removeItem(at: journal)
                continue
            }
            candidateItems.append(item)
            recovered.append((item, journal))
        }
        guard !recovered.isEmpty else { return }
        candidateItems.sort { $0.createdAt > $1.createdAt }
        do {
            try persist(candidateItems)
            items = candidateItems
            recovered.forEach { try? fileManager.removeItem(at: $0.journal) }
        } catch {
            lastError = .writeIndex(error.localizedDescription)
        }
    }

    private func update(_ id: UUID, mutation: (inout HistoryItem) -> Void) {
        var candidateItems = items
        guard let index = candidateItems.firstIndex(where: { $0.id == id }) else { return }
        mutation(&candidateItems[index])
        do {
            try persist(candidateItems)
            items = candidateItems
        } catch {
            lastError = .writeIndex(error.localizedDescription)
        }
    }

    private func load(reconcileOnLoad: Bool) {
        let hasIndex = fileManager.fileExists(atPath: indexURL.path)
        if hasIndex {
            do {
                items = try persistence.load()
            } catch {
                lastError = .readIndex(error.localizedDescription)
                return
            }
        }
        recoverPendingRemovals()
        if reconcileOnLoad, hasIndex || !items.isEmpty { _ = reconcile() }
    }

    private func persist(_ candidateItems: [HistoryItem]) throws {
        try persistence.save(candidateItems)
    }

    nonisolated static func checksum(of url: URL) -> String? {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                hasher.update(data: data)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        } catch {
            return nil
        }
    }
}
