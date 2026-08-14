import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

nonisolated enum EditorWindowProjectError: Error, Equatable {
    case projectHasNotBeenSaved
}

/// Owns an editor window per opened image. Keeps strong references so
/// windows survive until closed.
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {

    private static var openControllers: [EditorWindowController] = []

    private let editorDocument: EditorDocument
    private unowned let appState: AppState
    private let session: EditorProjectSession
    private var sessionObservers: Set<AnyCancellable> = []
    /// Set once the user has resolved the unsaved-work prompt so the deferred
    /// `close()` doesn't prompt again.
    private var isCloseApproved = false

    @discardableResult
    static func open(
        image: CGImage,
        sourceScale: CGFloat = 1,
        appState: AppState,
        privacyScanPending: Bool = false
    ) -> EditorWindowController {
        let document = EditorDocument(image: image, sourceScale: sourceScale)
        document.beautify = appState.settings.defaultBeautifySettings
        document.isPrivacyScanPending = privacyScanPending
        let controller = EditorWindowController(
            session: EditorProjectSession(document: document),
            appState: appState
        )
        openControllers.append(controller)
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        return controller
    }

    /// Opens an editable screenshot project. The existing `open(image:)`
    /// instant-capture path remains separate and unchanged for callers.
    @discardableResult
    static func openProject(
        at packageURL: URL,
        appState: AppState
    ) throws -> EditorWindowController {
        let controller = EditorWindowController(
            session: try EditorProjectSession.openProject(at: packageURL),
            appState: appState
        )
        openControllers.append(controller)
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        return controller
    }

    static func hideAllForCapture() {
        for controller in openControllers {
            controller.window?.orderOut(nil)
        }
    }

    private init(
        session: EditorProjectSession,
        appState: AppState
    ) {
        self.editorDocument = session.document
        self.appState = appState
        self.session = session

        let projectTitle = session.packageURL?.deletingPathExtension().lastPathComponent ?? "Screenshot"
        let contentView = EditorView(
            document: session.document,
            session: session,
            appState: appState,
            projectTitle: projectTitle
        )
        let hosting = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hosting)
        window.title = projectTitle
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 1600, height: 1000))
        window.minSize = NSSize(width: 1180, height: 760)
        window.backgroundColor = NSColor(red: 0.043, green: 0.047, blue: 0.059, alpha: 1)
        Self.placeInitialWindow(window)
        super.init(window: window)
        window.delegate = self
        bindSessionToWindow()
    }

    private static func placeInitialWindow(_ window: NSWindow) {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
                ?? NSScreen.main
                ?? NSScreen.screens.first else { return }

        let visibleFrame = screen.visibleFrame
        let maxContentSize = window.contentRect(
            forFrameRect: NSRect(origin: .zero, size: visibleFrame.size)
        ).size
        let contentSize = NSSize(
            width: max(1, min(1600, maxContentSize.width)),
            height: max(1, min(1000, maxContentSize.height))
        )
        window.minSize = NSSize(
            width: min(1180, contentSize.width),
            height: min(760, contentSize.height)
        )
        window.setContentSize(contentSize)

        var frame = window.frame
        frame.origin.x = visibleFrame.midX - frame.width / 2
        frame.origin.y = visibleFrame.midY - frame.height / 2
        frame.origin.x = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - frame.height)
        window.setFrameOrigin(frame.origin)
    }

    required init?(coder: NSCoder) { fatalError() }

    func finishPrivacyScan(redactionRects: [CGRect], style: ShareSafeRedactionStyle) {
        editorDocument.finishPrivacyScan(redactionRects: redactionRects, style: style)
    }

    /// Saves the live, non-flattened editor state to a project package.
    /// PNG export continues to use the existing `EditorView` actions.
    @discardableResult
    func saveProject(to packageURL: URL) throws -> AeroProjectManifest {
        try session.saveProject(to: packageURL)
    }

    @discardableResult
    func saveProject() throws -> AeroProjectManifest {
        try session.saveProject()
    }

    // MARK: - File menu (responder chain)

    @objc func saveProjectDocument(_ sender: Any?) {
        if session.hasProjectURL {
            saveProjectReportingErrors { try self.session.saveProject() }
        } else {
            saveProjectAs()
        }
    }

    @objc func saveProjectDocumentAs(_ sender: Any?) {
        saveProjectAs()
    }

    @objc func duplicateAnnotation(_ sender: Any?) {
        _ = editorDocument.duplicateSelected()
    }

    @objc func chooseAnnotationTool(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let rawValue = item.representedObject as? String,
              let tool = ToolKind(rawValue: rawValue) else { return }
        editorDocument.selectedToolKind = tool
    }

    private func saveProjectAs() {
        guard let window else { return }
        let panel = NSSavePanel()
        if let type = UTType(filenameExtension: "aeroshot") {
            panel.allowedContentTypes = [type]
        }
        panel.nameFieldStringValue = "Screenshot.aeroshot"
        panel.directoryURL = appState.settings.saveDirectory
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.saveProjectReportingErrors { try self.session.saveProject(to: url) }
        }
    }

    @discardableResult
    private func saveProjectReportingErrors(
        _ save: () throws -> AeroProjectManifest
    ) -> Bool {
        do {
            _ = try save()
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t Save Project"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            if let window {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
            return false
        }
    }

    // MARK: - Dirty tracking + close

    private func bindSessionToWindow() {
        session.$isDirty
            .sink { [weak self] dirty in
                self?.window?.isDocumentEdited = dirty
            }
            .store(in: &sessionObservers)
        // Title stays "Edit Screenshot" (automation and docs key off it);
        // the represented URL still surfaces the package via the proxy icon.
        session.$packageURL
            .sink { [weak self] url in
                self?.window?.representedURL = url
            }
            .store(in: &sessionObservers)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isCloseApproved { return true }
        switch session.closeDecision() {
        case .closeImmediately:
            return true
        case .flushAutosaveAndClose:
            flushAutosaveThenClose(sender)
            return false
        case .promptForUnsavedWork:
            promptForUnsavedWork(sender)
            return false
        }
    }

    private func flushAutosaveThenClose(_ window: NSWindow) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.session.flushPendingAutosave()
                self.isCloseApproved = true
                window.close()
            } catch {
                let alert = NSAlert()
                alert.messageText = "Couldn’t Save Project"
                alert.informativeText = "The latest changes could not be written to the project. \(error.localizedDescription)"
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Close Anyway")
                let response = await alert.beginSheetModal(for: window)
                if response == .alertSecondButtonReturn {
                    self.isCloseApproved = true
                    window.close()
                }
            }
        }
    }

    private func promptForUnsavedWork(_ window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = "Save changes to this screenshot?"
        alert.informativeText = "You can keep an editable project, export a flattened PNG, or discard the edits."
        alert.addButton(withTitle: "Save Project…")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        Task { [weak self] in
            guard let self else { return }
            let response = await alert.beginSheetModal(for: window)
            switch response {
            case .alertFirstButtonReturn:
                let panel = NSSavePanel()
                if let type = UTType(filenameExtension: "aeroshot") {
                    panel.allowedContentTypes = [type]
                }
                panel.nameFieldStringValue = "Screenshot.aeroshot"
                panel.directoryURL = self.appState.settings.saveDirectory
                let panelResponse = await panel.beginSheetModal(for: window)
                guard panelResponse == .OK, let url = panel.url else { return }
                if self.saveProjectReportingErrors({ try self.session.saveProject(to: url) }) {
                    self.isCloseApproved = true
                    window.close()
                }
            case .alertSecondButtonReturn:
                self.isCloseApproved = true
                window.close()
            default:
                break
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        Self.openControllers.removeAll { $0 === self }
    }
}

// MARK: - Editor SwiftUI shell

struct EditorView: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var session: EditorProjectSession
    let appState: AppState
    let projectTitle: String

    @State private var color: Color = .red
    @State private var lineWidth: CGFloat = 4
    @State private var fontSize: CGFloat = 24
    @State private var filled = false
    @State private var mode: EditorMode = .mark
    @State private var recipe: ExportRecipe = .documentation
    @State private var showInspector = true
    @State private var straightenDragStart: Double?
    @State private var scrubPosition = 0
    @State private var mutedIDs: Set<UUID> = []
    @State private var mutedAppearances: [UUID: AnnotationAppearance] = [:]
    @State private var reviewFindings: [CGRect] = []
    @State private var reviewDecisions: [Int: ReviewDecision] = [:]
    @State private var reviewIndex = 0
    @State private var reviewState: ReviewState = .idle
    @State private var reviewError: String?
    @State private var reviewTask: Task<Void, Never>?
    @State private var reviewUndoTick: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum EditorMode: String, CaseIterable, Identifiable {
        case mark, beautify, review, export

        var id: String { rawValue }
        var label: String {
            switch self {
            case .mark: "Mark"
            case .beautify: "Beautify"
            case .review: "ShareSafe"
            case .export: "Export"
            }
        }
        var key: String {
            switch self {
            case .mark: "M"
            case .beautify: "B"
            case .review: "R"
            case .export: "E"
            }
        }
    }

    private enum ExportRecipe: String, CaseIterable, Identifiable {
        case documentation, retina, downscaled, socialSquare, socialLandscape

        var id: String { rawValue }
        var format: String {
            switch self {
            case .socialSquare, .socialLandscape: "JPEG"
            default: "PNG"
            }
        }
        var label: String {
            switch self {
            case .documentation: "Documentation"
            case .retina: "Retina asset"
            case .downscaled: "Downscaled"
            case .socialSquare: "Social square"
            case .socialLandscape: "Social landscape"
            }
        }
        var metadata: String {
            switch self {
            case .documentation: "points · no suffix · Reveal in Finder"
            case .retina: "original · @2x · Clipboard"
            case .downscaled: "scale 0.5 · no suffix · File"
            case .socialSquare: "1080 × 1080 · q0.9 · -square"
            case .socialLandscape: "1600 × 900 · q0.9 · -landscape"
            }
        }
    }

    private enum ReviewState { case idle, scanning, ready, failed }
    private enum ReviewDecision { case blurred, kept }

    private struct StylePreset: Identifiable {
        let id: String
        let label: String
        let color: NSColor
        let width: CGFloat
    }

    private let stylePresets: [StylePreset] = [
        StylePreset(id: "coral", label: "Coral bold", color: .systemOrange, width: 4),
        StylePreset(id: "blue", label: "Blueprint", color: .systemBlue, width: 2.5),
        StylePreset(id: "mint", label: "Soft mint", color: .systemGreen, width: 2),
        StylePreset(id: "ink", label: "Ink", color: .labelColor, width: 5)
    ]

    private var style: ToolStyle {
        ToolStyle(color: NSColor(color), lineWidth: lineWidth, fontSize: fontSize, filled: filled)
    }

    private var totalStackCount: Int {
        document.undoStack.undoCommands.count + document.undoStack.redoCommands.count
    }

    private var stackPosition: Int { document.undoStack.undoCommands.count }

    private var stackPositionBinding: Binding<Double> {
        Binding(
            get: { Double(stackPosition) },
            set: { setScrub(to: Int($0.rounded())) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            titlebar
            HStack(spacing: 0) {
                stackSidebar
                    .frame(width: 250)
                Divider().overlay(shellBorder)
                VStack(spacing: 0) {
                    canvasStage
                    contextBar
                }
            }
        }
        .frame(minWidth: 1180, minHeight: 760)
        .background(shellBackground)
        .preferredColorScheme(.dark)
        .onAppear { scrubPosition = stackPosition }
        .onChange(of: document.undoTick) { _, newTick in
            scrubPosition = stackPosition
            if reviewUndoTick != nil, reviewUndoTick != newTick {
                invalidateShareSafeReview()
            }
        }
        .onDisappear { reviewTask?.cancel() }
    }

    private var titlebar: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(projectTitle).aeroshot")
                    .font(.system(size: 12, weight: .semibold))
                Text(documentMeta)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(tertiaryText)
            }

            Divider().frame(height: 28)
            modeTabs
            editorActions
            Spacer(minLength: 12)
            stackScrubber
            Divider().frame(height: 28)
            Button {
                mode = .export
            } label: {
                HStack(spacing: 8) {
                    Text("Export")
                    Text("⌘E")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .opacity(0.6)
                }
            }
            .buttonStyle(EditorAccentButtonStyle())
            .disabled(document.isPrivacyScanPending)
            .accessibilityIdentifier("editor.exportMode")
            .accessibilityLabel("Export")
        }
        .padding(.leading, 72)
        .padding(.trailing, 14)
        .frame(height: 54)
        .background(shellSurface3)
        .overlay(alignment: .bottom) { Rectangle().fill(shellBorder).frame(height: 1) }
    }

    private var modeTabs: some View {
        HStack(spacing: 3) {
            ForEach(EditorMode.allCases) { item in
                Button {
                    setMode(item)
                } label: {
                    HStack(spacing: 6) {
                        Text(item.key).font(.system(size: 10, weight: .semibold, design: .monospaced)).opacity(0.55)
                        Text(item.label)
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(mode == item ? accent : secondaryText)
                    .padding(.horizontal, 12)
                    .frame(height: 31)
                    .background(mode == item ? accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(EditorControlButtonStyle())
                .accessibilityLabel(item.label)
                .accessibilityValue(mode == item ? "Selected" : "Not selected")
                .accessibilityAddTraits(mode == item ? .isSelected : [])
            }
        }
        .padding(3)
        .background(shellSurface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(shellBorder, lineWidth: 1))
    }

    private var stackScrubber: some View {
        HStack(spacing: 9) {
            Text("STACK")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(tertiaryText)
                .tracking(0.5)
            Slider(value: stackPositionBinding, in: 0...Double(max(totalStackCount, 1)), step: 1)
                .frame(width: 190)
                .tint(accent)
                .disabled(totalStackCount == 0)
            Text("\(stackPosition)/\(totalStackCount)")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(secondaryText)
                .frame(width: 46, alignment: .leading)
            Button { stepStack(-1) } label: { Text("⌫") }
                .buttonStyle(EditorQuietButtonStyle())
                .disabled(!document.undoStack.canUndo)
                .accessibilityLabel("Step backward")
            Button { stepStack(1) } label: { Text("⌦") }
                .buttonStyle(EditorQuietButtonStyle())
                .disabled(!document.undoStack.canRedo)
                .accessibilityLabel("Step forward")
        }
    }

    private var editorActions: some View {
        HStack(spacing: 3) {
            Button { document.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(EditorIconButtonStyle(tint: document.undoStack.canUndo ? secondaryText : tertiaryText))
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!document.undoStack.canUndo)
                .help("Undo")
                .accessibilityLabel("Undo")
            Button { document.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(EditorIconButtonStyle(tint: document.undoStack.canRedo ? secondaryText : tertiaryText))
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!document.undoStack.canRedo)
                .help("Redo")
                .accessibilityLabel("Redo")
            Divider().frame(height: 20)
            Button { document.zoomScale = max(0.1, document.zoomScale - 0.1) } label: { Image(systemName: "minus") }
                .buttonStyle(EditorIconButtonStyle(tint: secondaryText))
                .help("Zoom out")
                .accessibilityLabel("Zoom out")
            Button {
                document.zoomScale = 1
                document.panOffset = .zero
            } label: {
                Text("\(Int(document.zoomScale * 100))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(secondaryText)
                    .frame(width: 40)
            }
            .buttonStyle(EditorControlButtonStyle())
            .accessibilityLabel("Reset zoom")
            .accessibilityValue("\(Int(document.zoomScale * 100)) percent")
            Button { document.zoomScale = min(10, document.zoomScale + 0.1) } label: { Image(systemName: "plus") }
                .buttonStyle(EditorIconButtonStyle(tint: secondaryText))
                .help("Zoom in")
                .accessibilityLabel("Zoom in")
            Divider().frame(height: 20)
            Button { showInspector.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(EditorIconButtonStyle(tint: showInspector ? accent : secondaryText))
                .help("Annotation inspector")
                .accessibilityLabel("Annotation inspector")
                .accessibilityValue(showInspector ? "Shown" : "Hidden")
            Button { document.showRuler.toggle() } label: { Image(systemName: "ruler") }
                .buttonStyle(EditorIconButtonStyle(tint: document.showRuler ? accent : secondaryText))
                .help("Pixel ruler")
                .accessibilityLabel("Pixel ruler")
                .accessibilityValue(document.showRuler ? "Shown" : "Hidden")
            Menu {
                ForEach(AnnotationTemplate.builtIn, id: \.id) { template in
                    Button { document.applyTemplate(template) } label: { Label(template.name, systemImage: template.symbol) }
                }
            } label: {
                Image(systemName: "square.on.square")
                    .foregroundStyle(secondaryText)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Annotation templates")
            .accessibilityLabel("Annotation templates")
        }
        .padding(.horizontal, 4)
    }

    private var stackSidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Move stack").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(document.annotations.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(tertiaryText)
            }
            .padding(.horizontal, 13)
            .padding(.top, 13)
            .padding(.bottom, 9)

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(document.annotations) { annotation in
                        stackRow(annotation)
                    }
                    baseCaptureCard
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }

            VStack(alignment: .leading, spacing: 8) {
                statusLine(
                    color: session.lastAutosaveError == nil && !session.isDirty ? success : warning,
                    text: autosaveStatus
                )
                statusLine(color: shareSafeStatusColor, text: shareSafeStatus)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .overlay(alignment: .top) { Rectangle().fill(shellBorder).frame(height: 1) }
        }
        .background(shellSurface3)
    }

    private func stackRow(_ annotation: Annotation) -> some View {
        let selected = document.selection.contains(annotation.id)
        let muted = isMuted(annotation)
        let layerIndex = document.annotations.firstIndex(where: { $0.id == annotation.id }) ?? 0
        return HStack(spacing: 7) {
            Button {
                document.selectOnly(annotation.id)
                mode = .mark
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: annotationSymbol(annotation.kind))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(muted ? tertiaryText : accent)
                        .frame(width: 24, height: 24)
                        .background((muted ? Color.white : accent).opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(annotationLabel(annotation))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(muted ? secondaryText : primaryText)
                            .lineLimit(1)
                        Text(annotationMeta(annotation))
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(tertiaryText)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(EditorControlButtonStyle())
            .accessibilityLabel("Select \(annotationLabel(annotation))")
            .accessibilityValue("\(selected ? "Selected" : "Not selected"), \(kindDisplayName(annotation.kind)), layer \(layerIndex + 1) of \(document.annotations.count)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            Button { reorder(annotation.id, direction: .backward) } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(EditorIconButtonStyle())
            .disabled(document.annotations.first?.id == annotation.id)
            .accessibilityLabel("Move \(annotationLabel(annotation)) up")
            Button { reorder(annotation.id, direction: .forward) } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(EditorIconButtonStyle())
            .disabled(document.annotations.last?.id == annotation.id)
            .accessibilityLabel("Move \(annotationLabel(annotation)) down")
            Button { toggleMute(annotation) } label: {
                Image(systemName: muted ? "eye.slash" : "eye")
            }
            .buttonStyle(EditorIconButtonStyle(tint: muted ? tertiaryText : accent))
            .disabled(annotation.kind.isRedaction)
            .accessibilityLabel(muted ? "Unmute \(annotationLabel(annotation))" : "Mute \(annotationLabel(annotation))")
            .accessibilityValue(muted ? "Muted" : "Visible")
            .accessibilityHint(annotation.kind.isRedaction ? "Privacy redactions stay visible" : "")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(selected ? accent.opacity(0.13) : shellSurface2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(selected ? accent.opacity(0.55) : shellBorder, lineWidth: 1))
        .opacity(muted ? 0.58 : 1)
    }

    private var baseCaptureCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.dashed")
                .frame(width: 20, height: 20)
                .foregroundStyle(tertiaryText)
                .background(shellSurface2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text("Base capture · \(Int(document.pixelSize.width)) × \(Int(document.pixelSize.height))\nnever rewritten — every move above is reversible")
                .font(.system(size: 10.5))
                .foregroundStyle(tertiaryText)
                .lineLimit(2)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(shellBorder))
        .padding(.top, 4)
    }

    private var canvasStage: some View {
        ZStack(alignment: .topTrailing) {
            EditorCanvasView(document: document, toolKind: $document.selectedToolKind, style: style)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(shellSurface3)

            if showInspector && mode == .mark {
                AnnotationInspector(
                    document: document,
                    toolKind: document.selectedToolKind,
                    defaultColor: $color,
                    defaultLineWidth: $lineWidth,
                    defaultFontSize: $fontSize,
                    defaultFilled: $filled
                )
                .padding(20)
            }

            if mode == .review {
                reviewCard.padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shellSurface3)
    }

    @ViewBuilder
    private var contextBar: some View {
        Group {
            switch mode {
            case .mark: markContextBar
            case .beautify: beautifyContextBar
            case .review: reviewContextBar
            case .export: exportContextBar
            }
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(shellSurface3)
        .overlay(alignment: .top) { Rectangle().fill(shellBorder).frame(height: 1) }
    }

    private var markContextBar: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("TOOLS").contextLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(ToolKind.allCases) { kind in
                        toolButton(kind)
                    }
                }
            }
            Divider().frame(height: 52)
            VStack(alignment: .leading, spacing: 7) {
                Text("STYLE PRESETS").contextLabel()
                HStack(spacing: 5) {
                    ForEach(stylePresets) { preset in
                        Button {
                            apply(preset)
                        } label: {
                            HStack(spacing: 7) {
                                Circle().fill(Color(nsColor: preset.color)).frame(width: 9, height: 9)
                                Text(preset.label)
                            }
                        }
                        .buttonStyle(EditorPresetButtonStyle())
                    }
                }
            }
            if document.selectedToolKind == .crop {
                Divider().frame(height: 52)
                cropControls
            }
            Spacer(minLength: 12)
            Text("Every mark lands as a move in the stack — nothing is burned into pixels until export.")
                .font(.system(size: 10.5))
                .foregroundStyle(tertiaryText)
                .frame(maxWidth: 280, alignment: .leading)
        }
    }

    private var cropControls: some View {
        HStack(spacing: 10) {
            AeroMenuPicker(
                options: [nil, 1, 4.0 / 3.0, 16.0 / 9.0] as [CGFloat?],
                selection: $document.cropAspectRatio,
                label: aspectLabel
            )
            .accessibilityLabel("Crop aspect ratio")
            AeroInlineSlider(
                label: "Straighten",
                value: $document.straightenDegrees,
                range: -10...10,
                step: 0.1,
                width: 90,
                valueText: { String(format: "%.1f°", $0) },
                onEditingChanged: { editing in
                    if editing {
                        if straightenDragStart == nil { straightenDragStart = document.straightenDegrees }
                    } else if let start = straightenDragStart {
                        straightenDragStart = nil
                        if start != document.straightenDegrees {
                            document.perform(SetStraightenCommand(before: start, after: document.straightenDegrees))
                        }
                    }
                }
            )
            Button("Apply") { document.applyPendingCrop() }
                .buttonStyle(EditorAccentButtonStyle())
                .disabled(document.pendingCropRect == nil)
            Button("Cancel") { document.cancelPendingCrop() }
                .buttonStyle(EditorQuietButtonStyle())
                .disabled(document.pendingCropRect == nil)
        }
    }

    private func aspectLabel(_ ratio: CGFloat?) -> String {
        guard let ratio else { return "Free" }
        if ratio == 1 { return "Square 1:1" }
        if ratio == 4.0 / 3.0 { return "Photo 4:3" }
        if ratio == 16.0 / 9.0 { return "Widescreen 16:9" }
        return "Custom"
    }

    private var beautifyContextBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("STAGE").contextLabel()
                HStack(spacing: 5) {
                    ForEach(BeautifySettings.GradientPreset.allCases) { gradient in
                        Button {
                            updateBeautify { $0.gradient = gradient; $0.enabled = true }
                        } label: {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [Color(nsColor: gradient.colors.0), Color(nsColor: gradient.colors.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 42, height: 34)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(document.beautify.gradient == gradient ? .white : .clear, lineWidth: 2))
                        }
                        .buttonStyle(EditorControlButtonStyle())
                        .accessibilityLabel(gradient.displayName)
                    }
                }
            }
            Divider().frame(height: 54)
            VStack(alignment: .leading, spacing: 7) {
                Text("FRAME").contextLabel()
                HStack(spacing: 4) {
                    ForEach(["None", "Window", "Browser"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(secondaryText)
                            .padding(.horizontal, 10)
                            .frame(height: 27)
                            .background(shellSurface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            Divider().frame(height: 54)
            BeautifyControls(document: document)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reviewContextBar: some View {
        HStack(alignment: .center, spacing: 14) {
            Text("FINDINGS").contextLabel()
            if reviewFindings.isEmpty {
                Text(reviewState == .scanning ? "Scanning the canvas…" : "Run an on-device scan to review sensitive regions.")
                    .font(.system(size: 11))
                    .foregroundStyle(secondaryText)
            } else {
                HStack(spacing: 7) {
                    ForEach(reviewFindings.indices, id: \.self) { index in
                        Button {
                            reviewIndex = index
                        } label: {
                            HStack(spacing: 8) {
                                Circle().fill(reviewDotColor(index)).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Finding \(index + 1)")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(reviewDecisionLabel(index))
                                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                        .opacity(0.7)
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 44)
                            .background(reviewIndex == index ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(reviewIndex == index ? accent.opacity(0.55) : shellBorder, lineWidth: 1))
                        }
                        .buttonStyle(EditorControlButtonStyle())
                    }
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 7) {
                Text("SCAN TIER").contextLabel()
                HStack(spacing: 5) {
                    Text(appState.settings.shareSafeSmartScan ? "Smart Scan" : "Pattern")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(secondaryText)
                        .padding(.horizontal, 10)
                        .frame(height: 27)
                        .background(shellSurface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Button(reviewState == .scanning ? "Scanning…" : "Scan") { runShareSafeScan() }
                        .buttonStyle(EditorQuietButtonStyle())
                        .disabled(reviewState == .scanning)
                }
            }
        }
    }

    private var exportContextBar: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("RECIPES").contextLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(ExportRecipe.allCases) { item in
                        Button {
                            recipe = item
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 7) {
                                    Text(item.format)
                                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(recipe == item ? accent : tertiaryText)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 4)
                                        .background((recipe == item ? accent : Color.white).opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    Text(item.label).font(.system(size: 11.5, weight: .semibold))
                                }
                                Text(item.metadata)
                                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(secondaryText)
                            }
                            .frame(width: 160, height: 60, alignment: .leading)
                            .padding(.horizontal, 14)
                            .background(recipe == item ? accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(recipe == item ? accent.opacity(0.55) : shellBorder, lineWidth: 1))
                        }
                        .buttonStyle(EditorControlButtonStyle())
                        .accessibilityIdentifier("editor.exportRecipe.\(item.id)")
                    }
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                Text(recipe.label).font(.system(size: 11.5, weight: .semibold))
                Text("\(recipe.metadata) · \(document.annotations.count) moves flattened")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(tertiaryText)
            }
            Button("Export") { exportRecipe() }
                .buttonStyle(EditorAccentButtonStyle())
                .disabled(document.isPrivacyScanPending)
                .accessibilityIdentifier("editor.export")
        }
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "shield.checkered")
                    .foregroundStyle(accent)
                    .frame(width: 26, height: 26)
                    .background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("ShareSafe review").font(.system(size: 11.5, weight: .semibold))
                    Text(reviewProgress).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(tertiaryText)
                }
                Spacer()
            }
            Divider()
            switch reviewState {
            case .idle:
                Text("Run a privacy scan to review emails, keys, and card numbers before export.")
                    .font(.system(size: 11))
                    .foregroundStyle(secondaryText)
                Button("Scan canvas") { runShareSafeScan() }.buttonStyle(EditorAccentButtonStyle())
            case .scanning:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Scanning on device…") }
                    .font(.system(size: 11)).foregroundStyle(secondaryText)
            case .failed:
                Text(reviewError ?? "The scan failed closed. Nothing will be shared until it completes.")
                    .font(.system(size: 11)).foregroundStyle(secondaryText)
                Button("Try again") { runShareSafeScan() }.buttonStyle(EditorQuietButtonStyle())
            case .ready:
                if reviewIndex < reviewFindings.count {
                    Text("Sensitive region \(reviewIndex + 1) of \(reviewFindings.count)")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Choose a reversible redaction or keep the original region visible.")
                        .font(.system(size: 11)).foregroundStyle(secondaryText)
                    HStack(spacing: 6) {
                        Button("\(appState.settings.shareSafeRedactionStyle.displayName) it") { acceptFinding() }
                            .buttonStyle(EditorAccentButtonStyle())
                        Button("Keep") { skipFinding() }.buttonStyle(EditorQuietButtonStyle())
                    }
                } else {
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(success)
                        Text("Review complete").font(.system(size: 11.5, weight: .semibold))
                    }
                    Text("\(reviewDecisions.values.filter { $0 == .blurred }.count) blurred, \(reviewDecisions.values.filter { $0 == .kept }.count) kept. Redactions remain reversible moves in the stack.")
                        .font(.system(size: 11)).foregroundStyle(secondaryText)
                    Button("Re-scan") { runShareSafeScan() }.buttonStyle(EditorQuietButtonStyle())
                }
            }
        }
        .padding(13)
        .frame(width: 282, alignment: .leading)
        .background(shellSurface3.opacity(0.98), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(shellBorderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
    }

    private var documentMeta: String {
        let head = stackPosition == totalStackCount ? "head" : "scrubbed to \(stackPosition)"
        let saveState = session.isDirty ? "unsaved" : "autosaved"
        return "\(document.annotations.count) moves live · \(head) · \(saveState)"
    }

    private var autosaveStatus: String {
        if session.lastAutosaveError != nil { return "Autosave failed — save project" }
        if session.isDirty { return session.hasProjectURL ? "Autosaving project package…" : "Unsaved — save project to enable autosave" }
        return session.hasProjectURL ? "Autosaved to project package" : "Ready — project not saved"
    }

    private var shareSafeStatus: String {
        if document.isPrivacyScanPending { return "ShareSafe scan in progress" }
        let redactions = document.annotations.filter(\.kind.isRedaction).count
        return redactions == 0 ? "ShareSafe ready · no findings" : "ShareSafe reviewed · \(redactions) redacted"
    }

    private var shareSafeStatusColor: Color {
        if document.isPrivacyScanPending { return warning }
        return document.annotations.contains(where: { $0.kind.isRedaction }) ? success : secondaryText
    }

    private var reviewProgress: String {
        guard !reviewFindings.isEmpty else { return reviewState == .scanning ? "scanning" : "ready to scan" }
        return "finding \(min(reviewIndex + 1, reviewFindings.count)) of \(reviewFindings.count)"
    }

    private func statusLine(color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 10.5)).foregroundStyle(secondaryText)
        }
    }

    private func toolButton(_ kind: ToolKind) -> some View {
        Button {
            withAnimation(AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion)) {
                document.selectedToolKind = kind
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: kind.symbolName).font(.system(size: 15, weight: .semibold))
                Text(kind.displayName).font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
            .frame(width: 62, height: 58)
            .foregroundStyle(document.selectedToolKind == kind ? shellBackground : secondaryText)
            .background(document.selectedToolKind == kind ? accent : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(document.selectedToolKind == kind ? .clear : shellBorder, lineWidth: 1))
        }
        .buttonStyle(EditorControlButtonStyle())
        .help(kind.displayName)
        .accessibilityLabel(kind.displayName)
        .accessibilityValue(document.selectedToolKind == kind ? "Selected" : "Not selected")
        .accessibilityAddTraits(document.selectedToolKind == kind ? .isSelected : [])
    }

    private func setMode(_ newMode: EditorMode) {
        mode = newMode
        if newMode == .beautify, !document.beautify.enabled {
            updateBeautify { $0.enabled = true }
        }
        if newMode != .mark { showInspector = false }
    }

    private func setScrub(to target: Int) {
        let target = min(max(target, 0), totalStackCount)
        while document.undoStack.undoCommands.count > target { document.undo() }
        while document.undoStack.undoCommands.count < target, document.undoStack.canRedo { document.redo() }
        scrubPosition = stackPosition
    }

    private func stepStack(_ delta: Int) {
        setScrub(to: stackPosition + delta)
    }

    private func reorder(_ id: UUID, direction: AnnotationZOrder) {
        document.selectOnly(id)
        _ = document.reorderSelected(direction)
    }

    private func isMuted(_ annotation: Annotation) -> Bool {
        guard !annotation.kind.isRedaction else { return false }
        return mutedIDs.contains(annotation.id) || (annotation.appearance.stroke.opacity == 0 && annotation.appearance.fill.opacity == 0)
    }

    private func toggleMute(_ annotation: Annotation) {
        guard !annotation.kind.isRedaction else { return }
        var updated = annotation
        if mutedIDs.contains(annotation.id) {
            updated.appearance = mutedAppearances.removeValue(forKey: annotation.id) ?? annotation.appearance
            if mutedAppearances[annotation.id] == nil,
               updated.appearance.stroke.opacity == 0,
               updated.appearance.fill.opacity == 0 {
                updated.appearance.stroke.opacity = 1
                updated.appearance.fill.opacity = 1
            }
            guard document.transformAnnotation(id: annotation.id, to: updated) else { return }
            mutedIDs.remove(annotation.id)
        } else {
            mutedAppearances[annotation.id] = annotation.appearance
            updated.appearance.stroke.opacity = 0
            updated.appearance.fill.opacity = 0
            guard document.transformAnnotation(id: annotation.id, to: updated) else { return }
            mutedIDs.insert(annotation.id)
        }
    }

    private func apply(_ preset: StylePreset) {
        if document.selection.isEmpty {
            color = Color(nsColor: preset.color)
            lineWidth = preset.width
            return
        }
        let controller = AnnotationInspectorController(document: document)
        _ = controller.updateColor(preset.color)
        _ = controller.update(.strokeWidth, value: preset.width)
    }

    private func updateBeautify(_ mutate: (inout BeautifySettings) -> Void) {
        var after = document.beautify
        mutate(&after)
        guard after != document.beautify else { return }
        document.perform(SetBeautifyCommand(before: document.beautify, after: after))
    }

    private func runShareSafeScan() {
        reviewTask?.cancel()
        reviewFindings = []
        reviewDecisions = [:]
        reviewIndex = 0
        reviewError = nil
        reviewState = .scanning
        reviewUndoTick = document.undoTick
        guard let image = AnnotationRenderer.renderAnnotated(document: document) else {
            reviewError = "The current canvas could not be prepared for scanning."
            reviewState = .failed
            reviewUndoTick = nil
            return
        }
        let useSmartScan = appState.settings.shareSafeSmartScan
        let usePrivacyFilter = appState.settings.shareSafePrivacyFilter
        let scannedUndoTick = document.undoTick
        reviewTask = Task { @MainActor in
            do {
                let rects = try await ShareSafeService.detectSensitiveRects(
                    in: image,
                    useSmartScan: useSmartScan,
                    usePrivacyFilter: usePrivacyFilter
                )
                guard !Task.isCancelled else { return }
                guard document.undoTick == scannedUndoTick else {
                    invalidateShareSafeReview()
                    return
                }
                reviewFindings = rects
                reviewState = .ready
            } catch {
                guard !Task.isCancelled else { return }
                reviewError = error.localizedDescription
                reviewState = .failed
                reviewUndoTick = nil
            }
        }
    }

    private func acceptFinding() {
        guard reviewUndoTick == document.undoTick else {
            invalidateShareSafeReview()
            return
        }
        guard reviewFindings.indices.contains(reviewIndex) else { return }
        let rect = reviewFindings[reviewIndex]
        let kind = appState.settings.shareSafeRedactionStyle.annotationKind
        let annotation = Annotation(kind: kind, points: [rect.origin, CGPoint(x: rect.maxX, y: rect.maxY)], lineWidth: 0)
        document.perform(AddAnnotationCommand(annotation: annotation, selectsAnnotation: true))
        reviewUndoTick = document.undoTick
        reviewDecisions[reviewIndex] = .blurred
        reviewIndex += 1
    }

    private func skipFinding() {
        guard reviewUndoTick == document.undoTick else {
            invalidateShareSafeReview()
            return
        }
        guard reviewFindings.indices.contains(reviewIndex) else { return }
        reviewDecisions[reviewIndex] = .kept
        reviewIndex += 1
    }

    private func invalidateShareSafeReview() {
        reviewTask?.cancel()
        reviewFindings = []
        reviewDecisions = [:]
        reviewIndex = 0
        reviewError = "The canvas changed. Scan again before applying a finding."
        reviewState = .failed
        reviewUndoTick = nil
    }

    private func reviewDecisionLabel(_ index: Int) -> String {
        switch reviewDecisions[index] {
        case .blurred: "blurred"
        case .kept: "kept"
        default: index == reviewIndex ? "reviewing" : "pending"
        }
    }

    private func reviewDotColor(_ index: Int) -> Color {
        switch reviewDecisions[index] {
        case .blurred: success
        case .kept: tertiaryText
        default: accent
        }
    }

    private func exportRecipe() {
        saveToDefaultLocation()
    }

    private func saveAs() {
        guard let rendered = document.renderFinal() else { return }
        let panel = NSSavePanel()
        let format = appState.settings.imageFormat
        panel.allowedContentTypes = [format.utType]
        panel.nameFieldStringValue = "Screenshot.\(format.fileExtension)"
        panel.directoryURL = appState.settings.saveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            try? ImageExporter.write(
                rendered,
                to: url,
                format: format,
                jpegQuality: appState.settings.jpegQuality,
                scale: document.sourceScale,
                downscaleToPoints: appState.settings.downscaleRetina
            )
        }
    }

    private func saveToDefaultLocation() {
        guard let rendered = document.renderFinal() else { return }
        let settings = appState.settings
        do {
            try ImageExporter.write(
                rendered,
                to: settings.newFileURL(),
                format: settings.imageFormat,
                jpegQuality: settings.jpegQuality,
                scale: document.sourceScale,
                downscaleToPoints: settings.downscaleRetina
            )
        } catch {
            ToastController.shared.show("Couldn’t save screenshot. Check the save folder and available space.", symbol: "exclamationmark.triangle")
        }
    }

    private func annotationLabel(_ annotation: Annotation) -> String {
        switch annotation.kind {
        case .step: "Step \(annotation.stepNumber)"
        case .text: "“\(annotation.text.isEmpty ? "Text" : annotation.text)”"
        case .redactBlur, .redactPixelate, .redactSolid: "\(kindDisplayName(annotation.kind)) · ShareSafe"
        default: kindDisplayName(annotation.kind)
        }
    }

    private func annotationMeta(_ annotation: Annotation) -> String {
        let rect = annotation.boundingRect.integral
        if annotation.kind == .step || annotation.kind == .text {
            return "\(Int(rect.minX)), \(Int(rect.minY))"
        }
        return "\(max(0, Int(rect.width))) × \(max(0, Int(rect.height)))"
    }

    private func annotationSymbol(_ kind: AnnotationKind) -> String {
        switch kind {
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .freehand: "pencil.and.scribble"
        case .highlighter: "highlighter"
        case .text: "textformat"
        case .step: "1.circle"
        case .redactBlur: "drop.halffull"
        case .redactPixelate: "squareshape.split.3x3"
        case .redactSolid: "rectangle.fill"
        }
    }

    private func kindDisplayName(_ kind: AnnotationKind) -> String {
        switch kind {
        case .arrow: "Arrow"
        case .line: "Line"
        case .rectangle: "Box"
        case .ellipse: "Ellipse"
        case .freehand: "Draw"
        case .highlighter: "Highlight"
        case .text: "Text"
        case .step: "Step"
        case .redactBlur: "Blur"
        case .redactPixelate: "Pixelate"
        case .redactSolid: "Redact"
        }
    }

    private var shellBackground: Color { Color(red: 0.043, green: 0.047, blue: 0.059) }
    private var shellSurface2: Color { Color(red: 0.098, green: 0.110, blue: 0.133) }
    private var shellSurface3: Color { Color(red: 0.055, green: 0.063, blue: 0.078) }
    private var shellBorder: Color { Color.white.opacity(0.075) }
    private var shellBorderStrong: Color { Color.white.opacity(0.15) }
    private var primaryText: Color { Color(red: 0.929, green: 0.933, blue: 0.945) }
    private var secondaryText: Color { Color(red: 0.612, green: 0.631, blue: 0.671) }
    private var tertiaryText: Color { Color(red: 0.400, green: 0.420, blue: 0.459) }
    private var accent: Color { Color(red: 1, green: 0.541, blue: 0.420) }
    private var success: Color { Color(red: 0.373, green: 0.827, blue: 0.627) }
    private var warning: Color { Color(red: 1, green: 0.706, blue: 0.329) }
}

private extension View {
    func contextLabel() -> some View {
        self
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color(red: 0.400, green: 0.420, blue: 0.459))
            .tracking(0.5)
    }
}

private struct EditorAccentButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(red: 0.071, green: 0.082, blue: 0.110))
            .padding(.horizontal, 14)
            .frame(minHeight: 30)
            .background(Color(red: 1, green: 0.541, blue: 0.420).opacity(isEnabled ? (configuration.isPressed ? 0.78 : isHovered ? 0.92 : 1) : 0.35), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(isHovered && isEnabled ? 0.28 : 0), lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion), value: isHovered)
            .onHover { hovering in
                withAnimation(AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion)) {
                    isHovered = hovering
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct EditorQuietButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color(red: 0.612, green: 0.631, blue: 0.671).opacity(isEnabled ? 1 : 0.5))
            .padding(.horizontal, 10)
            .frame(minWidth: 30, minHeight: 28)
            .background(Color.white.opacity(isHovered && isEnabled ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(isEnabled ? (isHovered ? 0.16 : 0.075) : 0.04), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion), value: isHovered)
            .onHover { hovering in
                withAnimation(AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion)) {
                    isHovered = hovering
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct EditorIconButtonStyle: ButtonStyle {
    var tint: Color = Color(red: 0.400, green: 0.420, blue: 0.459)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint.opacity(isEnabled ? 1 : 0.5))
            .frame(minWidth: 28, minHeight: 28)
            .background(Color.white.opacity(isHovered && isEnabled ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(isHovered && isEnabled ? 0.14 : 0), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.42)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion), value: isHovered)
            .onHover { hovering in
                withAnimation(AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion)) {
                    isHovered = hovering
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct EditorPresetButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Color(red: 0.612, green: 0.631, blue: 0.671).opacity(isEnabled ? 1 : 0.5))
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Color.white.opacity(isHovered && isEnabled ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(isEnabled ? (isHovered ? 0.16 : 0.075) : 0.04), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion), value: isHovered)
            .onHover { hovering in
                withAnimation(AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion)) {
                    isHovered = hovering
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Shared chrome for the editor's floating strips: capsule material, one
/// hairline, one elevation recipe, and the toolbar type/button defaults.
private struct EditorCapsuleChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(AeroTokens.Typography.small(weight: .semibold))
            .buttonStyle(EditorToolbarButtonStyle())
            .padding(AeroTokens.Spacing.xs)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(AeroTheme.strokeHairline, lineWidth: AeroTokens.Stroke.hairlineWidth))
            .shadow(
                color: .black.opacity(AeroTokens.Elevation.floating.opacity),
                radius: AeroTokens.Elevation.floating.radius,
                x: AeroTokens.Elevation.floating.x,
                y: AeroTokens.Elevation.floating.y
            )
            .fixedSize(horizontal: true, vertical: true)
    }
}

private struct EditorControlButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isHovered && isEnabled ? 0.045 : 0))
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion), value: isHovered)
            .onHover { hovering in
                withAnimation(AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion)) {
                    isHovered = hovering
                }
            }
            .contentShape(Rectangle())
    }
}

private struct EditorToolbarButtonStyle: ButtonStyle {
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: AeroTheme.controlHeight, minHeight: AeroTheme.controlHeight)
            .background(
                isHovered && isEnabled ? AeroTokens.Fill.hover : Color.clear,
                in: RoundedRectangle(cornerRadius: AeroTheme.controlRadiusS, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: AeroTheme.controlRadiusS, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? AeroTheme.pressOpacity : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? AeroTheme.pressScale : 1)
            .animation(
                AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
            .onHover { hovering in
                withAnimation(AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion)) {
                    isHovered = hovering
                }
            }
    }
}

struct BeautifyControls: View {
    @ObservedObject var document: EditorDocument

    var body: some View {
        HStack(spacing: AeroTokens.Spacing.large) {
            HStack(spacing: AeroTokens.Spacing.small - 2) {
                Image(systemName: "sparkles")
                    .foregroundStyle(AeroTheme.accent)
                    .font(AeroTokens.Typography.small(weight: .semibold))
                    .accessibilityHidden(true)
                AeroCompactToggle(title: "Beautify", isOn: binding(\.enabled))
            }

            Divider().frame(height: 20)

            if document.beautify.enabled {
                labeledPicker("Theme", options: Array(BeautifySettings.GradientPreset.allCases), selection: binding(\.gradient)) { $0.displayName }

                Divider().frame(height: 20)

                labeledPicker("Aspect", options: Array(BeautifySettings.AspectPreset.allCases), selection: binding(\.aspectPreset)) { $0.displayName }

                Divider().frame(height: 20)

                Group {
                    beautifySlider("Padding", keyPath: \.padding, range: 0...200, width: 80)
                    beautifySlider("Corner", keyPath: \.cornerRadius, range: 0...40, width: 70)
                    beautifySlider("Shadow", keyPath: \.shadowRadius, range: 0...80, width: 70)
                }
            }

            Spacer()
        }
        .padding(.horizontal, AeroTokens.Spacing.large)
        .padding(.vertical, AeroTokens.Spacing.small)
    }

    private func labeledPicker<T: Hashable>(
        _ title: String,
        options: [T],
        selection: Binding<T>,
        label: @escaping (T) -> String
    ) -> some View {
        HStack(spacing: AeroTokens.Spacing.xs) {
            Text(title)
                .font(AeroTokens.Typography.small(weight: .medium))
                .foregroundStyle(.secondary)
            AeroMenuPicker(options: options, selection: selection, label: label)
                .accessibilityLabel(title)
        }
    }

    /// Beautify tweaks route through the undo stack as commands.
    private func binding<T>(_ keyPath: WritableKeyPath<BeautifySettings, T>) -> Binding<T> {
        Binding(
            get: { document.beautify[keyPath: keyPath] },
            set: { newValue in
                var after = document.beautify
                after[keyPath: keyPath] = newValue
                document.perform(SetBeautifyCommand(before: document.beautify, after: after))
            }
        )
    }

    private func beautifySlider(
        _ label: String,
        keyPath: WritableKeyPath<BeautifySettings, CGFloat>,
        range: ClosedRange<CGFloat>,
        width: CGFloat
    ) -> some View {
        AeroInlineSlider(
            label: label,
            value: Binding(
                get: { document.beautify[keyPath: keyPath] },
                set: { value in
                    var preview = document.beautify
                    preview[keyPath: keyPath] = value
                    document.previewBeautify(preview)
                }
            ),
            range: range,
            width: width,
            onEditingChanged: { editing in
                if editing { document.beginBeautifyEdit() }
                else { _ = document.commitBeautifyEdit() }
            }
        )
    }
}
