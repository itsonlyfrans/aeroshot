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
    @State private var selectedTab: HistoryTab = .all

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 14)]

    enum HistoryTab: String, CaseIterable, Identifiable {
        case all = "All"
        case images = "Images"
        case recordings = "Recordings"
        case text = "Text"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .images: return "photo"
            case .recordings: return "film"
            case .text: return "text.alignleft"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Search & Tabs
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13, weight: .medium))
                    TextField("Search filename or OCR text…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                
                HStack(spacing: 2) {
                    ForEach(HistoryTab.allCases) { tab in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                selectedTab = tab
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: tab.symbol)
                                    .font(.system(size: 10, weight: .medium))
                                Text(tab.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                            )
                            .foregroundStyle(selectedTab == tab ? Color.white : Color.primary.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )

                Button {
                    appState.showSettingsWindow()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(12)
            .background(.background)
            
            Divider()
            
            let filteredItems = history.search(query).filter { item in
                switch selectedTab {
                case .all: return true
                case .images: return item.kind == .image
                case .recordings: return item.kind == .recording
                case .text: return item.kind == .text
                }
            }

            if filteredItems.isEmpty {
                historyEmptyState(hasAnyItems: !history.items.isEmpty)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filteredItems) { item in
                            HistoryCell(item: item, appState: appState)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    @ViewBuilder
    private func historyEmptyState(hasAnyItems: Bool) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: hasAnyItems ? "magnifyingglass" : "camera.viewfinder")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(hasAnyItems ? "No captures match your search" : "No captures yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            if !hasAnyItems {
                Text("Use All-in-One from the menu bar or press your All-in-One shortcut.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                Button("Open All-in-One") {
                    appState.allInOneController.begin()
                }
                .controlSize(.regular)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HistoryCell: View {
    let item: HistoryItem
    let appState: AppState
    @EnvironmentObject var history: HistoryStore
    
    @State private var isHovering = false
    @State private var hoveredAction: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    switch item.kind {
                    case .text:
                        TextHistoryPreview(item: item)
                    case .recording:
                        RecordingHistoryPreview(item: item)
                    case .image:
                        AsyncThumbnail(url: history.fileURL(for: item))
                    }
                }
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isHovering ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                
                if isHovering {
                    HStack(spacing: 4) {
                        switch item.kind {
                        case .text:
                            quickActionBtn("doc.on.doc", "Copy Text", actionID: "copy") {
                                if let text = item.ocrText ?? loadText() {
                                    PasteboardWriter.copy(text: text)
                                }
                            }
                        case .recording:
                            quickActionBtn("play.fill", "Open", actionID: "open") {
                                NSWorkspace.shared.open(history.fileURL(for: item))
                            }
                            quickActionBtn("square.and.arrow.up", "Share", actionID: "share") {
                                ShareService.shareFile(at: history.fileURL(for: item), from: nil)
                            }
                            quickActionBtn("folder", "Finder", actionID: "finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([history.fileURL(for: item)])
                            }
                        case .image:
                            quickActionBtn("doc.on.doc", "Copy", actionID: "copy") {
                                if let image = loadImage() { PasteboardWriter.copy(image: image) }
                            }
                            quickActionBtn("pencil.tip.crop.circle", "Edit", actionID: "edit") {
                                if let image = loadImage() { appState.openEditor(with: image) }
                            }
                            quickActionBtn("pin", "Pin", actionID: "pin") {
                                if let image = loadImage() { appState.pinController.pin(image: image) }
                            }
                            quickActionBtn("shield.checkered", "Share Safe", actionID: "shareSafe") {
                                if let image = loadImage() {
                                    Task {
                                        await ShareSafeService.shareSafe(
                                            image: image,
                                            fileURL: history.fileURL(for: item),
                                            from: nil,
                                            style: appState.settings.shareSafeRedactionStyle
                                        )
                                    }
                                }
                            }
                            quickActionBtn("square.and.arrow.up", "Share", actionID: "share") {
                                if let image = loadImage() {
                                    ShareService.shareImage(image, fileURL: history.fileURL(for: item), from: nil)
                                }
                            }
                        }

                        quickActionBtn("trash", "Delete", actionID: "delete", isDestructive: true) {
                            withAnimation(.easeOut(duration: 0.15)) {
                                history.remove(item)
                            }
                        }
                    }
                    .padding(4)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
                    .padding(6)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
            .scaleEffect(isHovering ? 1.015 : 1.0)
            .shadow(color: Color.black.opacity(isHovering ? 0.12 : 0.03), radius: isHovering ? 6 : 1, x: 0, y: isHovering ? 3 : 1)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(relativeTimeString(for: item.createdAt))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.85))
                    Spacer()
                    Text(kindBadgeText)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(kindBadgeColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(kindBadgeColor.opacity(0.12))
                        )
                }

                Text(kindDetailText)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(isHovering ? 0.02 : 0.0))
        )
        .onHover { over in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                isHovering = over
            }
        }
        .contextMenu {
            switch item.kind {
            case .text:
                Button("Copy Text") {
                    if let text = item.ocrText ?? loadText() {
                        PasteboardWriter.copy(text: text)
                    }
                }
                Button("Share…") {
                    ShareService.shareText(item.ocrText ?? loadText() ?? "", from: nil)
                }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([history.fileURL(for: item)])
                }
                Divider()
                Button("Delete", role: .destructive) { history.remove(item) }
            case .recording:
                Button("Open") {
                    NSWorkspace.shared.open(history.fileURL(for: item))
                }
                Button("Share…") {
                    ShareService.shareFile(at: history.fileURL(for: item), from: nil)
                }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([history.fileURL(for: item)])
                }
                Divider()
                Button("Delete", role: .destructive) { history.remove(item) }
            case .image:
                Button("Copy") {
                    if let image = loadImage() { PasteboardWriter.copy(image: image) }
                }
                Button("Edit") {
                    if let image = loadImage() { appState.openEditor(with: image) }
                }
                Button("Pin") {
                    if let image = loadImage() { appState.pinController.pin(image: image) }
                }
                Button("Share Safe…") {
                    if let image = loadImage() {
                        Task {
                            await ShareSafeService.shareSafe(
                                image: image,
                                fileURL: history.fileURL(for: item),
                                from: nil,
                                style: appState.settings.shareSafeRedactionStyle
                            )
                        }
                    }
                }
                Button("Share…") {
                    if let image = loadImage() {
                        ShareService.shareImage(image, fileURL: history.fileURL(for: item), from: nil)
                    }
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
        }
        .onDrag {
            switch item.kind {
            case .text:
                return NSItemProvider(object: (item.ocrText ?? loadText() ?? "") as NSString)
            case .image, .recording:
                return NSItemProvider(contentsOf: history.fileURL(for: item)) ?? NSItemProvider()
            }
        }
    }

    private var kindBadgeText: String {
        switch item.kind {
        case .text: return "TEXT"
        case .image: return "IMAGE"
        case .recording: return "VIDEO"
        }
    }

    private var kindBadgeColor: Color {
        switch item.kind {
        case .text: return .purple
        case .image: return .blue
        case .recording: return .red
        }
    }

    private var kindDetailText: String {
        switch item.kind {
        case .text:
            return "\(item.pixelWidth) line\(item.pixelWidth == 1 ? "" : "s")"
        case .image:
            return "\(item.pixelWidth) × \(item.pixelHeight)"
        case .recording:
            let mins = item.pixelWidth / 60
            let secs = item.pixelWidth % 60
            let ext = item.fileExtension.uppercased()
            return "\(mins):\(String(format: "%02d", secs)) · \(ext)"
        }
    }

    private func quickActionBtn(_ symbol: String, _ help: String, actionID: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isDestructive ? Color.red : (hoveredAction == actionID ? Color.accentColor : Color.primary.opacity(0.75)))
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hoveredAction == actionID ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { over in
            withAnimation(.easeOut(duration: 0.1)) {
                hoveredAction = over ? actionID : nil
            }
        }
    }

    private func relativeTimeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func loadText() -> String? {
        try? String(contentsOf: history.fileURL(for: item), encoding: .utf8)
    }

    private func loadImage() -> CGImage? {
        let url = history.fileURL(for: item)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

struct RecordingHistoryPreview: View {
    let item: HistoryItem

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.red.opacity(0.25), Color.orange.opacity(0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 8) {
                Image(systemName: item.fileExtension == "gif" ? "photo.stack" : "film")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                Text(item.fileExtension.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

/// Loads a downsampled thumbnail off the main thread; keeps 200-item grids smooth.
struct TextHistoryPreview: View {
    let item: HistoryItem
    @EnvironmentObject var history: HistoryStore

    private var previewText: String {
        if let ocrText = item.ocrText, !ocrText.isEmpty { return ocrText }
        return (try? String(contentsOf: history.fileURL(for: item), encoding: .utf8)) ?? ""
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03))
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text(previewText)
                    .font(.system(size: 9))
                    .lineLimit(6)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
        }
    }
}

/// Loads a downsampled thumbnail off the main thread; keeps 200-item grids smooth.
struct AsyncThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color.primary.opacity(0.04))
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
