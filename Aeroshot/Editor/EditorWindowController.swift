import AppKit
import SwiftUI

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
    private var projectURL: URL?

    static func open(image: CGImage, appState: AppState) {
        let document = EditorDocument(image: image)
        document.beautify = appState.settings.defaultBeautifySettings
        let controller = EditorWindowController(
            document: document,
            appState: appState,
            projectURL: nil
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
        let document = try EditorProjectBridge.open(from: packageURL)
        let controller = EditorWindowController(
            document: document,
            appState: appState,
            projectURL: packageURL
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
        document: EditorDocument,
        appState: AppState,
        projectURL: URL?
    ) {
        self.editorDocument = document
        self.appState = appState
        self.projectURL = projectURL

        let contentView = EditorView(document: editorDocument, appState: appState)
        let hosting = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Edit Screenshot"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1080, height: 720))
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Saves the live, non-flattened editor state to a project package.
    /// PNG export continues to use the existing `EditorView` actions.
    @discardableResult
    func saveProject(to packageURL: URL) throws -> AeroProjectManifest {
        let saved = try EditorProjectBridge.save(editorDocument, to: packageURL)
        projectURL = packageURL
        return saved
    }

    @discardableResult
    func saveProject() throws -> AeroProjectManifest {
        guard let projectURL else {
            throw EditorWindowProjectError.projectHasNotBeenSaved
        }
        return try saveProject(to: projectURL)
    }

    func windowWillClose(_ notification: Notification) {
        Self.openControllers.removeAll { $0 === self }
    }
}

// MARK: - Editor SwiftUI shell

struct EditorView: View {
    @ObservedObject var document: EditorDocument
    let appState: AppState

    @State private var toolKind: ToolKind = .arrow
    @State private var color: Color = .red
    @State private var lineWidth: CGFloat = 4
    @State private var fontSize: CGFloat = 24
    @State private var filled = false
    @State private var showBeautify = false
    @State private var showInspector = false
    @State private var hoveredMenu: String?
    @State private var hoveredTool: ToolKind?

    private var style: ToolStyle {
        ToolStyle(color: NSColor(color), lineWidth: lineWidth, fontSize: fontSize, filled: filled)
    }

    var body: some View {
        ZStack {
            EditorCanvasView(document: document, toolKind: toolKind, style: style)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                editorToolbar
                Spacer(minLength: 0)
            }
            .padding(16)

            HStack(alignment: .top, spacing: 14) {
                Spacer(minLength: 0)
                if showInspector {
                    AnnotationInspector(
                        document: document,
                        toolKind: toolKind,
                        defaultColor: $color,
                        defaultLineWidth: $lineWidth,
                        defaultFontSize: $fontSize,
                        defaultFilled: $filled
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 68)

            if showBeautify {
                VStack {
                    Spacer(minLength: 0)
                    HStack {
                        Spacer(minLength: 0)
                        BeautifyControls(document: document)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AeroTheme.strokeHairline, lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.24), radius: 16, x: 0, y: 8)
                    }
                }
                .padding(18)
            }
        }
        .frame(minWidth: 960, minHeight: 520)
    }

    /// A single horizontal strip keeps command order stable at the editor's
    /// minimum window size. Tool categories are separated, not turned into
    /// separate floating cards.
    private var editorToolbar: some View {
        HStack(spacing: 7) {
            horizontalToolGroup([.select, .pan, .crop])
            Divider().frame(height: 22)
            horizontalToolGroup([.arrow, .line, .rectangle, .ellipse, .freehand, .highlighter, .text, .step])
            Divider().frame(height: 22)
            horizontalToolGroup([.redactBlur, .redactPixelate, .redactSolid])
            Divider().frame(height: 22)

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
            Button { document.zoomScale = max(0.1, document.zoomScale - 0.1) } label: { Image(systemName: "minus") }
                .help("Zoom out")
                .accessibilityLabel("Zoom out")
            Button {
                document.zoomScale = 1
                document.panOffset = .zero
            } label: {
                Text("\(Int(document.zoomScale * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .frame(width: 34)
            }
            .help("Reset zoom")
            .accessibilityLabel("Reset zoom")
            Button { document.zoomScale = min(10, document.zoomScale + 0.1) } label: { Image(systemName: "plus") }
                .help("Zoom in")
                .accessibilityLabel("Zoom in")
            Divider().frame(height: 22)

            Button { toggleBeautify() } label: { Image(systemName: "sparkles") }
                .foregroundStyle(showBeautify ? Color.accentColor : .primary)
                .help("Beautify canvas")
            Button { withAnimation(.easeOut(duration: 0.16)) { showInspector.toggle() } } label: { Image(systemName: "slider.horizontal.3") }
                .foregroundStyle(showInspector ? Color.accentColor : .primary)
                .help(document.selectedAnnotationID == nil ? "Tool defaults" : "Selected annotation properties")
                .accessibilityLabel(document.selectedAnnotationID == nil ? "Show tool defaults" : "Show selected annotation properties")
            Button { document.showRuler.toggle() } label: { Image(systemName: "ruler") }
                .foregroundStyle(document.showRuler ? Color.accentColor : .primary)
                .help("Pixel ruler")
            Menu {
                ForEach(AnnotationTemplate.builtIn, id: \.id) { template in
                    Button { document.applyTemplate(template) } label: { Label(template.name, systemImage: template.symbol) }
                }
            } label: {
                Image(systemName: "square.on.square")
                    .frame(width: AeroTheme.controlHeight, height: AeroTheme.controlHeight)
                    .background(
                        Color.primary.opacity(hoveredMenu == "templates" ? 0.08 : 0),
                        in: RoundedRectangle(cornerRadius: AeroTheme.controlRadiusS, style: .continuous)
                    )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Annotation templates")
            .onHover { hoveredMenu = $0 ? "templates" : nil }
            Divider().frame(height: 22)

            Button { saveToDefaultLocation() } label: {
                Label("Save", systemImage: "square.and.arrow.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Save the annotated screenshot to your output folder")
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
                Button { saveAs() } label: { Label("Save as…", systemImage: "folder") }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: AeroTheme.controlHeight, height: AeroTheme.controlHeight)
                    .background(
                        Color.primary.opacity(hoveredMenu == "export" ? 0.08 : 0),
                        in: RoundedRectangle(cornerRadius: AeroTheme.controlRadiusS, style: .continuous)
                    )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More export actions")
            .onHover { hoveredMenu = $0 ? "export" : nil }
        }
        .font(.system(size: 11, weight: .semibold))
        .buttonStyle(EditorToolbarButtonStyle())
        .padding(5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(AeroTheme.strokeHairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 5)
        .fixedSize(horizontal: true, vertical: true)
    }

    private func horizontalToolGroup(_ tools: [ToolKind]) -> some View {
        HStack(spacing: 1) {
            ForEach(tools) { kind in
                Button {
                    withAnimation(.easeOut(duration: 0.14)) { toolKind = kind }
                } label: {
                    Image(systemName: kind.symbolName)
                        .foregroundStyle(toolKind == kind ? Color.white : (hoveredTool == kind ? Color.primary : Color.secondary))
                        .frame(width: AeroTheme.controlHeight, height: AeroTheme.controlHeight)
                        .background(toolKind == kind ? AeroTheme.accent : .clear, in: RoundedRectangle(cornerRadius: AeroTheme.controlRadiusS, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(kind == .select ? "Select — drag image to export" : kind.displayName)
                .accessibilityLabel(kind.displayName)
                .accessibilityAddTraits(toolKind == kind ? .isSelected : [])
                .onHover { hoveredTool = $0 ? kind : nil }
            }
        }
    }

    private func toggleBeautify() {
        withAnimation(.easeOut(duration: 0.16)) {
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

private struct EditorToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(configuration.isPressed ? AeroTheme.pressOpacity : 1)
            .scaleEffect(configuration.isPressed ? AeroTheme.pressScale : 1)
    }
}

struct BeautifyControls: View {
    @ObservedObject var document: EditorDocument

    var body: some View {
        HStack(spacing: 16) {
            // Title & Toggle
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(AeroTheme.accent)
                    .font(.system(size: 11, weight: .bold))
                Toggle("Beautify Canvas", isOn: binding(\.enabled))
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            
            Divider().frame(height: 20)
            
            if document.beautify.enabled {
                // Gradient Picker
                HStack(spacing: 4) {
                    Text("Theme")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    Picker("", selection: binding(\.gradient)) {
                        ForEach(BeautifySettings.GradientPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .frame(width: 90)
                    .controlSize(.small)
                }
                
                Divider().frame(height: 20)
                
                // Aspect Ratio Picker
                HStack(spacing: 4) {
                    Text("Aspect")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    Picker("", selection: binding(\.aspectPreset)) {
                        ForEach(BeautifySettings.AspectPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .frame(width: 80)
                    .controlSize(.small)
                }
                
                Divider().frame(height: 20)
                
                // Sliders
                Group {
                    inspectorSlider("Padding", value: binding(\.padding), in: 0...200, width: 80)
                    inspectorSlider("Corner", value: binding(\.cornerRadius), in: 0...40, width: 70)
                    inspectorSlider("Shadow", value: binding(\.shadowRadius), in: 0...80, width: 70)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.02))
    }

    @ViewBuilder
    private func inspectorSlider(_ label: String, value: Binding<CGFloat>, in range: ClosedRange<CGFloat>, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Slider(value: value, in: range)
                .frame(width: width)
                .controlSize(.small)
            Text("\(Int(value.wrappedValue))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
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
