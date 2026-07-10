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
    @State private var favoritesOnly = false
    @State private var sort: HistorySort = .newest

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 14)]

    enum HistoryTab: String, CaseIterable, Identifiable {
        case all = "All"
        case images = "Images"
        case recordings = "Recordings"
        case projects = "Projects"
        case text = "Text"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .all: return "tray.full"
            case .images: return "photo"
            case .recordings: return "film"
            case .projects: return "shippingbox"
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
                        .accessibilityLabel("Search project library")
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

                Button {
                    favoritesOnly.toggle()
                } label: {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                        .foregroundStyle(favoritesOnly ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(favoritesOnly ? "Show all items" : "Show favorites only")
                .accessibilityLabel(favoritesOnly ? "Showing favorites" : "Show favorites")

                Picker("Sort", selection: $sort) {
                    ForEach(HistorySort.allCases) { option in Text(option.rawValue).tag(option) }
                }
                .labelsHidden()
                .frame(width: 120)
                .accessibilityLabel("Sort project library")
            }
            .padding(12)
            .background(.background)
            
            Divider()
            
            let filter = HistoryFilter(favoritesOnly: favoritesOnly)
            let filteredItems = history.search(query, filter: filter, sort: sort).filter { item in
                switch selectedTab {
                case .all: return true
                case .images: return item.kind == .image
                case .recordings: return item.kind == .recording || item.kind == .gif
                case .text: return item.kind == .text
                case .projects: return item.kind == .project
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
        .alert("Project Library", isPresented: Binding(
            get: { history.lastError != nil },
            set: { showing in if !showing { history.dismissLastError() } }
        )) {
            Button("OK") { history.dismissLastError() }
        } message: {
            Text(history.lastError?.localizedDescription ?? "An unknown error occurred.")
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
    @State private var isEditingTags = false
    @State private var tagEditorText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    switch item.kind {
                    case .text:
                        TextHistoryPreview(item: item)
                    case .recording:
                        RecordingHistoryPreview(item: item)
                    case .gif:
                        RecordingHistoryPreview(item: item)
                    case .project:
                        ProjectHistoryPreview(item: item)
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
                            quickActionBtn("text.viewfinder", "Copy Text", actionID: "copy") {
                                if let text = item.ocrText ?? loadText() {
                                    PasteboardWriter.copy(text: text)
                                }
                            }
                        case .recording, .gif, .project:
                            quickActionBtn("play.fill", "Open", actionID: "open", isEnabled: history.primaryURL(for: item) != nil,
                                           disabledReason: "The local artifact is missing") {
                                openPrimary()
                            }
                            quickActionBtn("square.and.arrow.up", "Share", actionID: "share", isEnabled: history.primaryURL(for: item) != nil,
                                           disabledReason: "The local artifact is missing") {
                                if let url = history.primaryURL(for: item) { ShareService.shareFile(at: url, from: nil) }
                            }
                            quickActionBtn("folder", "Finder", actionID: "finder", isEnabled: history.primaryURL(for: item) != nil,
                                           disabledReason: "The local artifact is missing") {
                                if let url = history.primaryURL(for: item) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            }
                        case .image:
                            quickActionBtn("doc.on.doc", "Copy", actionID: "copy") {
                                if let image = loadImage() {
                                    PasteboardWriter.copy(image: image, fileURL: history.fileURL(for: item))
                                }
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
                                            style: appState.settings.shareSafeRedactionStyle,
                                            useSmartScan: appState.settings.shareSafeSmartScan,
                                            usePrivacyFilter: appState.settings.shareSafePrivacyFilter,
                                            redactBeforeSharing: appState.settings.shareSafeRedactBeforeSharing
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
                            _ = withAnimation(.easeOut(duration: 0.15)) {
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
            Button(item.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                history.toggleFavorite(item)
            }
            Menu("Tags") {
                ForEach(["Work", "Personal", "Reference"], id: \.self) { tag in
                    Button(item.tags.contains(tag) ? "Remove \(tag)" : "Add \(tag)") {
                        var tags = item.tags
                        if let index = tags.firstIndex(of: tag) { tags.remove(at: index) } else { tags.append(tag) }
                        history.setTags(tags, for: item)
                    }
                }
                Divider()
                Button("Edit Tags…") {
                    tagEditorText = item.tags.joined(separator: ", ")
                    isEditingTags = true
                }
            }
            Divider()
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
            case .recording, .gif, .project:
                Button("Open") {
                    openPrimary()
                }
                .disabled(history.primaryURL(for: item) == nil)
                Button("Share…") {
                    if let url = history.primaryURL(for: item) { ShareService.shareFile(at: url, from: nil) }
                }
                .disabled(history.primaryURL(for: item) == nil)
                Button("Show in Finder") {
                    if let url = history.primaryURL(for: item) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                .disabled(history.primaryURL(for: item) == nil)
                if item.recoveryState == .recoverable {
                    Button("Recover Project") { openProjectForRecovery() }
                        .disabled(item.projectURL.map { !FileManager.default.fileExists(atPath: $0.path) } ?? true)
                }
                Divider()
                Button("Delete", role: .destructive) { history.remove(item) }
            case .image:
                Button("Copy") {
                    if let image = loadImage() {
                        PasteboardWriter.copy(image: image, fileURL: history.fileURL(for: item))
                    }
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
                                style: appState.settings.shareSafeRedactionStyle,
                                useSmartScan: appState.settings.shareSafeSmartScan,
                                usePrivacyFilter: appState.settings.shareSafePrivacyFilter,
                                redactBeforeSharing: appState.settings.shareSafeRedactBeforeSharing
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
            case .image, .recording, .gif, .project:
                guard let url = history.primaryURL(for: item) else { return NSItemProvider() }
                return NSItemProvider(contentsOf: url) ?? NSItemProvider()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(kindBadgeText), \(kindDetailText)\(item.isFavorite ? ", favorite" : "")")
        .alert("Edit Tags", isPresented: $isEditingTags) {
            TextField("Comma-separated tags", text: $tagEditorText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                history.setTags(tagEditorText.split(separator: ",").map(String.init), for: item)
            }
        } message: {
            Text("Add searchable local tags separated by commas.")
        }
    }

    private var kindBadgeText: String {
        switch item.kind {
        case .text: return "TEXT"
        case .image: return "IMAGE"
        case .recording: return "VIDEO"
        case .gif: return "GIF"
        case .project: return "PROJECT"
        }
    }

    private var kindBadgeColor: Color {
        switch item.kind {
        case .text: return .purple
        case .image: return .blue
        case .recording: return .red
        case .gif: return .orange
        case .project: return .green
        }
    }

    private var kindDetailText: String {
        switch item.kind {
        case .text:
            return "\(item.pixelWidth) line\(item.pixelWidth == 1 ? "" : "s")"
        case .image:
            return "\(item.pixelWidth) × \(item.pixelHeight)"
        case .recording, .gif:
            let seconds = Int(item.durationSeconds ?? Double(item.pixelWidth))
            let mins = seconds / 60
            let secs = seconds % 60
            let ext = item.fileExtension.uppercased()
            return "\(mins):\(String(format: "%02d", secs)) · \(ext)"
        case .project:
            if item.sourceState == .missing { return "Missing source — locate or recover to open" }
            return item.recoveryState == .recoverable ? "Recovery available" : "Editable project"
        }
    }

    private func quickActionBtn(
        _ symbol: String,
        _ help: String,
        actionID: String,
        isDestructive: Bool = false,
        isEnabled: Bool = true,
        disabledReason: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
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
        .disabled(!isEnabled)
        .help(isEnabled ? help : (disabledReason ?? "Unavailable"))
        .accessibilityLabel(help)
        .accessibilityHint(isEnabled ? "" : (disabledReason ?? "Unavailable"))
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

    private func openPrimary() {
        guard let url = history.primaryURL(for: item) else { return }
        history.markOpened(item)
        NSWorkspace.shared.open(url)
    }

    private func openProjectForRecovery() {
        guard let url = item.projectURL, FileManager.default.fileExists(atPath: url.path) else { return }
        history.markOpened(item)
        NSWorkspace.shared.open(url)
    }
}

struct ProjectHistoryPreview: View {
    let item: HistoryItem

    var body: some View {
        ZStack {
            LinearGradient(colors: [.green.opacity(0.22), .blue.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 8) {
                Image(systemName: item.sourceState == .missing ? "exclamationmark.triangle" : "shippingbox")
                    .font(.system(size: 28, weight: .medium))
                Text(item.sourceState == .missing ? "MISSING" : "PROJECT")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.9))
        }
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
