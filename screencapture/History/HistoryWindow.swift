import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController: NSWindowController, NSWindowDelegate {
    private unowned let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        let hosting = NSHostingController(rootView: HistoryView(appState: appState)
            .environmentObject(appState.history))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Capture History"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 820, height: 560))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct HistoryView: View {
    let appState: AppState
    @EnvironmentObject var history: HistoryStore
    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search filename or text in image…", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(history.search(query)) { item in
                        HistoryCell(item: item, appState: appState)
                    }
                }
                .padding(12)
            }
        }
    }
}

struct HistoryCell: View {
    let item: HistoryItem
    let appState: AppState
    @EnvironmentObject var history: HistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AsyncThumbnail(url: history.fileURL(for: item))
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            Text(item.createdAt, style: .date) + Text(" ") + Text(item.createdAt, style: .time)
            Text("\(item.pixelWidth) × \(item.pixelHeight)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .contextMenu {
            Button("Copy") {
                if let image = loadImage() { PasteboardWriter.copy(image: image) }
            }
            Button("Edit") {
                if let image = loadImage() { appState.openEditor(with: image) }
            }
            Button("Pin") {
                if let image = loadImage() { appState.pinController.pin(image: image) }
            }
            Button("Copy Text (OCR)") {
                if let text = item.ocrText {
                    PasteboardWriter.copy(text: text)
                } else if let image = loadImage() {
                    Task {
                        if let text = try? await OCRService.recognizeText(in: image) {
                            PasteboardWriter.copy(text: text)
                            history.setOCRText(text, for: item.id)
                        }
                    }
                }
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([history.fileURL(for: item)])
            }
            Divider()
            Button("Delete", role: .destructive) { history.remove(item) }
        }
        .onDrag { NSItemProvider(contentsOf: history.fileURL(for: item)) ?? NSItemProvider() }
    }

    private func loadImage() -> CGImage? {
        let url = history.fileURL(for: item)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

/// Loads a downsampled thumbnail off the main thread; keeps 200-item grids smooth.
struct AsyncThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .task(id: url) {
            image = await Self.loadThumbnail(url: url)
        }
    }

    static func loadThumbnail(url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 400,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
    }
}
