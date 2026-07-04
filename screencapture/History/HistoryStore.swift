import Combine
import AppKit

/// Persists capture history as image files plus a JSON index in
/// ~/Library/Application Support/ScreenCapture/History.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var items: [HistoryItem] = []

    private let maxItems = 500

    let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ScreenCapture/History", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    private init() {
        load()
    }

    func fileURL(for item: HistoryItem) -> URL {
        directory.appendingPathComponent(item.fileName)
    }

    @discardableResult
    func add(image: CGImage) -> HistoryItem {
        let id = UUID()
        let fileName = "\(id.uuidString).png"
        let url = directory.appendingPathComponent(fileName)
        try? ImageExporter.write(image, to: url, format: .png)
        let item = HistoryItem(id: id, fileName: fileName,
                               pixelWidth: image.width, pixelHeight: image.height,
                               kind: .image)
        items.insert(item, at: 0)
        trim()
        save()
        return item
    }

    @discardableResult
    func add(textCapture text: String) -> HistoryItem {
        let id = UUID()
        let fileName = "\(id.uuidString).txt"
        let url = directory.appendingPathComponent(fileName)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        let lineCount = text.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
        let item = HistoryItem(id: id, fileName: fileName, ocrText: text,
                               pixelWidth: lineCount, pixelHeight: 0, kind: .text)
        items.insert(item, at: 0)
        trim()
        save()
        return item
    }

    /// Copies a finished recording into the history folder and indexes it.
    @discardableResult
    func add(recordingFrom sourceURL: URL, durationSeconds: Int) -> HistoryItem? {
        let ext = sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension
        let id = UUID()
        let fileName = "\(id.uuidString).\(ext)"
        let dest = directory.appendingPathComponent(fileName)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: sourceURL, to: dest)
        } catch {
            NSLog("History recording copy failed: \(error)")
            return nil
        }
        let item = HistoryItem(
            id: id,
            fileName: fileName,
            pixelWidth: max(durationSeconds, 1),
            pixelHeight: 0,
            kind: .recording
        )
        items.insert(item, at: 0)
        trim()
        save()
        return item
    }

    func setOCRText(_ text: String, for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].ocrText = text
        save()
    }

    func remove(_ item: HistoryItem) {
        try? FileManager.default.removeItem(at: fileURL(for: item))
        items.removeAll { $0.id == item.id }
        save()
    }

    func search(_ query: String) -> [HistoryItem] {
        guard !query.isEmpty else { return items }
        let q = query.lowercased()
        return items.filter {
            $0.fileName.lowercased().contains(q) || ($0.ocrText?.lowercased().contains(q) ?? false)
        }
    }

    private func trim() {
        while items.count > maxItems {
            let removed = items.removeLast()
            try? FileManager.default.removeItem(at: fileURL(for: removed))
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) else { return }
        items = decoded.filter { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
