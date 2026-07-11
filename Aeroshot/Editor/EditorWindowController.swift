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

    static func open(image: CGImage, appState: AppState) {
        let document = EditorDocument(image: image)
        document.beautify = appState.settings.defaultBeautifySettings
        let controller = EditorWindowController(
            session: EditorProjectSession(document: document),
            appState: appState
        )
        openControllers.append(controller)
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
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

        let contentView = EditorView(document: session.document, appState: appState)
        let hosting = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Edit Screenshot"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1080, height: 720))
        window.center()
        super.init(window: window)
        window.delegate = self
        bindSessionToWindow()
    }

    required init?(coder: NSCoder) { fatalError() }

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
            ToastController.shared.show("Project saved", symbol: "checkmark.seal")
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
    let appState: AppState

    @State private var color: Color = .red
    @State private var lineWidth: CGFloat = 4
    @State private var fontSize: CGFloat = 24
    @State private var filled = false
    @State private var showBeautify = false
    @State private var showInspector = false
    @State private var hoveredMenu: String?
    @State private var hoveredTool: ToolKind?
    @State private var straightenDragStart: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var style: ToolStyle {
        ToolStyle(color: NSColor(color), lineWidth: lineWidth, fontSize: fontSize, filled: filled)
    }

    /// Panels below the toolbar clear the strip: outer padding + control
    /// height + capsule padding + one medium gap.
    private var panelTopClearance: CGFloat {
        AeroTokens.Spacing.large + AeroTokens.Control.regularHeight
            + 2 * AeroTokens.Spacing.xs + AeroTokens.Spacing.medium
    }

    var body: some View {
        ZStack {
            EditorCanvasView(document: document, toolKind: $document.selectedToolKind, style: style)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: AeroTokens.Spacing.small) {
                HStack(alignment: .top, spacing: AeroTokens.Spacing.medium) {
                    modesCapsule
                    Spacer(minLength: AeroTokens.Spacing.medium)
                    actionsCapsule
                }
                if document.selectedToolKind == .crop {
                    cropBar
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .move(edge: .top))
                        )
                }
                Spacer(minLength: 0)
            }
            .padding(AeroTokens.Spacing.large)
            .animation(
                AeroTokens.Motion.resolved(AeroTokens.Motion.standard, reduceMotion: reduceMotion),
                value: document.selectedToolKind == .crop
            )

            HStack(alignment: .top, spacing: AeroTokens.Spacing.medium) {
                Spacer(minLength: 0)
                if showInspector {
                    AnnotationInspector(
                        document: document,
                        toolKind: document.selectedToolKind,
                        defaultColor: $color,
                        defaultLineWidth: $lineWidth,
                        defaultFontSize: $fontSize,
                        defaultFilled: $filled
                    )
                }
            }
            .padding(.horizontal, AeroTokens.Spacing.large)
            .padding(.top, panelTopClearance)

            if showBeautify {
                VStack {
                    Spacer(minLength: 0)
                    HStack {
                        Spacer(minLength: 0)
                        BeautifyControls(document: document)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AeroTheme.cardRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AeroTheme.cardRadius, style: .continuous)
                                    .strokeBorder(AeroTheme.strokeHairline, lineWidth: AeroTokens.Stroke.hairlineWidth)
                            )
                            .shadow(
                                color: .black.opacity(AeroTokens.Elevation.floating.opacity),
                                radius: AeroTokens.Elevation.floating.radius,
                                x: AeroTokens.Elevation.floating.x,
                                y: AeroTokens.Elevation.floating.y
                            )
                    }
                }
                .padding(AeroTokens.Spacing.large)
            }
        }
        .frame(minWidth: 960, minHeight: 520)
    }

    /// Two fixed capsules — modes on the left, document actions on the
    /// right — so no tool change ever reflows the strip. Crop's contextual
    /// controls live in their own bar below (`cropBar`).
    private var modesCapsule: some View {
        HStack(spacing: AeroTokens.Spacing.small - 1) {
            horizontalToolGroup([.select, .pan, .crop])
            toolbarDivider
            horizontalToolGroup([.arrow, .line, .rectangle, .ellipse, .freehand, .highlighter, .text, .step])
            toolbarDivider
            horizontalToolGroup([.redactBlur, .redactPixelate, .redactSolid])
        }
        .modifier(EditorCapsuleChrome())
    }

    private var actionsCapsule: some View {
        HStack(spacing: AeroTokens.Spacing.small - 1) {
            Button { document.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!document.undoStack.canUndo)
                .help("Undo")
                .accessibilityLabel("Undo")
            Button { document.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!document.undoStack.canRedo)
                .help("Redo")
                .accessibilityLabel("Redo")
            toolbarDivider
            Button { document.zoomScale = max(0.1, document.zoomScale - 0.1) } label: { Image(systemName: "minus") }
                .help("Zoom out")
                .accessibilityLabel("Zoom out")
            Button {
                document.zoomScale = 1
                document.panOffset = .zero
            } label: {
                Text("\(Int(document.zoomScale * 100))%")
                    .font(AeroTokens.Typography.small(weight: .semibold, design: .monospaced))
                    .frame(width: 40)
            }
            .help("Reset zoom")
            .accessibilityLabel("Reset zoom")
            Button { document.zoomScale = min(10, document.zoomScale + 0.1) } label: { Image(systemName: "plus") }
                .help("Zoom in")
                .accessibilityLabel("Zoom in")
            toolbarDivider
            panelToggle(
                symbol: "sparkles",
                isOn: showBeautify,
                help: "Beautify canvas",
                label: "Beautify canvas"
            ) { toggleBeautify() }
            panelToggle(
                symbol: "slider.horizontal.3",
                isOn: showInspector,
                help: document.selection.isEmpty ? "Tool defaults" : "Selected annotation properties",
                label: document.selection.isEmpty ? "Show tool defaults" : "Show selected annotation properties"
            ) {
                withAnimation(AeroTokens.Motion.resolved(AeroTokens.Motion.standard, reduceMotion: reduceMotion)) {
                    showInspector.toggle()
                }
            }
            panelToggle(
                symbol: "ruler",
                isOn: document.showRuler,
                help: "Pixel ruler",
                label: "Pixel ruler"
            ) { document.showRuler.toggle() }
            Menu {
                ForEach(AnnotationTemplate.builtIn, id: \.id) { template in
                    Button { document.applyTemplate(template) } label: { Label(template.name, systemImage: template.symbol) }
                }
            } label: {
                Image(systemName: "square.on.square")
                    .frame(width: AeroTheme.controlHeight, height: AeroTheme.controlHeight)
                    .background(
                        hoveredMenu == "templates" ? AeroTokens.Fill.hover : Color.clear,
                        in: RoundedRectangle(cornerRadius: AeroTheme.controlRadiusS, style: .continuous)
                    )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Annotation templates")
            .accessibilityLabel("Annotation templates")
            .onHover { hovering in
                withAnimation(AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion)) {
                    hoveredMenu = hovering ? "templates" : nil
                }
            }
            toolbarDivider

            Button { saveToDefaultLocation() } label: {
                Label("Export \(appState.settings.imageFormat.displayName)", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(AeroButtonStyle(kind: .primary, size: .compact))
            .help("Export the flattened \(appState.settings.imageFormat.displayName) to your output folder")
            .accessibilityLabel("Export \(appState.settings.imageFormat.displayName)")
            Menu {
                Button {
                    if let rendered = document.renderFinal() {
                        PasteboardWriter.copy(image: rendered)
                        ToastController.shared.show("Copied to clipboard", symbol: "doc.on.doc")
                    }
                } label: { Label("Copy image", systemImage: "doc.on.doc") }
                Button {
                    Task {
                        if let rendered = document.renderFinal(), let text = try? await OCRService.recognizeText(in: rendered) {
                            PasteboardWriter.copy(text: text)
                            ToastController.shared.show("Text copied", symbol: "text.viewfinder")
                        }
                    }
                } label: { Label("Copy text", systemImage: "text.viewfinder") }
                Divider()
                Button { saveAs() } label: { Label("Export as…", systemImage: "folder") }
                Divider()
                Button {
                    NSApp.sendAction(#selector(EditorWindowController.saveProjectDocument(_:)), to: nil, from: nil)
                } label: { Label("Save Project", systemImage: "internaldrive") }
                Button {
                    NSApp.sendAction(#selector(EditorWindowController.saveProjectDocumentAs(_:)), to: nil, from: nil)
                } label: { Label("Save Project As…", systemImage: "internaldrive") }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: AeroTheme.controlHeight, height: AeroTheme.controlHeight)
                    .background(
                        hoveredMenu == "export" ? AeroTokens.Fill.hover : Color.clear,
                        in: RoundedRectangle(cornerRadius: AeroTheme.controlRadiusS, style: .continuous)
                    )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More export actions")
            .accessibilityLabel("More export actions")
            .onHover { hovering in
                withAnimation(AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion)) {
                    hoveredMenu = hovering ? "export" : nil
                }
            }
        }
        .modifier(EditorCapsuleChrome())
    }

    /// Crop's contextual controls: separate bar, so the main strips stay put.
    private var cropBar: some View {
        HStack(spacing: AeroTokens.Spacing.medium) {
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
                    // Live drag previews directly; one undoable command per gesture.
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
                .buttonStyle(AeroButtonStyle(kind: .primary, size: .compact))
                .disabled(document.pendingCropRect == nil)
            Button("Cancel") { document.cancelPendingCrop() }
                .buttonStyle(AeroButtonStyle(kind: .quiet, size: .compact))
                .disabled(document.pendingCropRect == nil)
        }
        .padding(.horizontal, AeroTokens.Spacing.small)
        .modifier(EditorCapsuleChrome())
    }

    private var toolbarDivider: some View {
        Divider().frame(height: 22)
    }

    private func aspectLabel(_ ratio: CGFloat?) -> String {
        guard let ratio else { return "Free" }
        if ratio == 1 { return "Square 1:1" }
        if ratio == 4.0 / 3.0 { return "Photo 4:3" }
        if ratio == 16.0 / 9.0 { return "Widescreen 16:9" }
        return "Custom"
    }

    /// The one selected-state idiom shared with the tool buttons: accent
    /// fill + white glyph when active, quiet hover fill otherwise.
    private func panelToggle(
        symbol: String,
        isOn: Bool,
        help: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .frame(width: AeroTheme.controlHeight, height: AeroTheme.controlHeight)
                .background(
                    isOn ? AeroTheme.accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: AeroTheme.controlRadiusS, style: .continuous)
                )
        }
        .help(help)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func horizontalToolGroup(_ tools: [ToolKind]) -> some View {
        HStack(spacing: 1) {
            ForEach(tools) { kind in
                Button {
                    withAnimation(AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion)) {
                        document.selectedToolKind = kind
                    }
                } label: {
                    Image(systemName: kind.symbolName)
                        .foregroundStyle(document.selectedToolKind == kind ? Color.white : (hoveredTool == kind ? Color.primary : Color.secondary))
                        .frame(width: AeroTheme.controlHeight, height: AeroTheme.controlHeight)
                        .background {
                            if document.selectedToolKind == kind {
                                RoundedRectangle(cornerRadius: AeroTheme.controlRadiusS, style: .continuous)
                                    .fill(AeroTheme.accent)
                            } else if hoveredTool == kind {
                                RoundedRectangle(cornerRadius: AeroTheme.controlRadiusS, style: .continuous)
                                    .fill(AeroTokens.Fill.hover)
                            }
                        }
                }
                .buttonStyle(AeroPressableStyle())
                .help(kind == .select ? "Select — drag image to export" : kind.displayName)
                .accessibilityLabel(kind.displayName)
                .accessibilityAddTraits(document.selectedToolKind == kind ? .isSelected : [])
                .onHover { hovering in
                    withAnimation(AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion)) {
                        hoveredTool = hovering ? kind : nil
                    }
                }
            }
        }
    }

    private func toggleBeautify() {
        withAnimation(AeroTokens.Motion.resolved(AeroTokens.Motion.standard, reduceMotion: reduceMotion)) {
            showBeautify.toggle()
            if showBeautify, !document.beautify.enabled {
                var updated = document.beautify
                updated.enabled = true
                document.perform(SetBeautifyCommand(before: document.beautify, after: updated))
            }
        }
    }

    private func hasProperties(for kind: ToolKind) -> Bool {
        switch kind {
        case .select, .pan, .crop, .redactBlur, .redactPixelate, .redactSolid:
            return false
        default:
            return true
        }
    }

    private func supportsColor(_ kind: ToolKind) -> Bool {
        switch kind {
        case .select, .pan, .crop, .redactBlur, .redactPixelate, .redactSolid: return false
        default: return true
        }
    }

    private func supportsLineWidth(_ kind: ToolKind) -> Bool {
        switch kind {
        case .arrow, .line, .rectangle, .ellipse, .freehand, .highlighter: return true
        default: return false
        }
    }

    private func supportsFill(_ kind: ToolKind) -> Bool {
        switch kind {
        case .rectangle, .ellipse: return true
        default: return false
        }
    }

    private func supportsFontSize(_ kind: ToolKind) -> Bool {
        switch kind {
        case .text, .step: return true
        default: return false
        }
    }

    private func saveAs() {
        guard let rendered = document.renderFinal() else { return }
        let panel = NSSavePanel()
        let format = appState.settings.imageFormat
        panel.allowedContentTypes = [format.utType]
        panel.nameFieldStringValue = "Screenshot.\(format.fileExtension)"
        panel.directoryURL = appState.settings.saveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            try? ImageExporter.write(rendered, to: url, format: format,
                                     jpegQuality: appState.settings.jpegQuality)
        }
    }

    private func saveToDefaultLocation() {
        guard let rendered = document.renderFinal() else { return }
        let settings = appState.settings
        let url = settings.newFileURL()
        do {
            try ImageExporter.write(
                rendered,
                to: url,
                format: settings.imageFormat,
                jpegQuality: settings.jpegQuality,
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                downscaleToPoints: settings.downscaleRetina
            )
            ToastController.shared.show("Saved", symbol: "square.and.arrow.down")
        } catch {
            ToastController.shared.show(
                "Couldn’t save screenshot. Check the save folder and available space.",
                symbol: "exclamationmark.triangle"
            )
        }
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
                    AeroInlineSlider(label: "Padding", value: binding(\.padding), range: 0...200, width: 80)
                    AeroInlineSlider(label: "Corner", value: binding(\.cornerRadius), range: 0...40, width: 70)
                    AeroInlineSlider(label: "Shadow", value: binding(\.shadowRadius), range: 0...80, width: 70)
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
}
