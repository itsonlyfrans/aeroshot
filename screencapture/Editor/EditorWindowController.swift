import AppKit
import SwiftUI

/// Owns an editor window per opened image. Keeps strong references so
/// windows survive until closed.
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {

    private static var openControllers: [EditorWindowController] = []

    private let editorDocument: EditorDocument
    private unowned let appState: AppState

    static func open(image: CGImage, appState: AppState) {
        let controller = EditorWindowController(image: image, appState: appState)
        openControllers.append(controller)
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }

    private init(image: CGImage, appState: AppState) {
        self.editorDocument = EditorDocument(image: image)
        self.appState = appState

        let contentView = EditorView(document: editorDocument, appState: appState)
        let hosting = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Edit Screenshot"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1000, height: 700))
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

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

    private var style: ToolStyle {
        ToolStyle(color: NSColor(color), lineWidth: lineWidth, fontSize: fontSize, filled: filled)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            EditorCanvasView(document: document, toolKind: toolKind, style: style)
            if showBeautify {
                Divider()
                BeautifyControls(document: document)
            }
        }
        .frame(minWidth: 700, minHeight: 450)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            ForEach(ToolKind.allCases) { kind in
                Button {
                    toolKind = kind
                } label: {
                    Image(systemName: kind.symbolName)
                        .frame(width: 24, height: 20)
                }
                .buttonStyle(.bordered)
                .tint(toolKind == kind ? .accentColor : nil)
                .help(kind.displayName)
            }

            Divider().frame(height: 20)

            ColorPicker("", selection: $color).labelsHidden().frame(width: 36)
            Slider(value: $lineWidth, in: 1...16) { Text("Width") }
                .frame(width: 90)
                .help("Line width")
            Toggle("Fill", isOn: $filled).toggleStyle(.checkbox)

            Divider().frame(height: 20)

            Button {
                document.undo()
            } label: { Image(systemName: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!document.undoStack.canUndo)
            Button {
                document.redo()
            } label: { Image(systemName: "arrow.uturn.forward") }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!document.undoStack.canRedo)

            Button {
                showBeautify.toggle()
                if showBeautify, !document.beautify.enabled {
                    var b = document.beautify
                    b.enabled = true
                    document.perform(SetBeautifyCommand(before: document.beautify, after: b))
                }
            } label: { Image(systemName: "sparkles") }
                .help("Beautify")
                .tint(showBeautify ? .accentColor : nil)

            Spacer()

            Button("Copy Text") {
                Task {
                    if let rendered = document.renderFinal(),
                       let text = try? await OCRService.recognizeText(in: rendered) {
                        PasteboardWriter.copy(text: text)
                    }
                }
            }
            .help("OCR the image and copy the text")

            Button("Copy") {
                if let rendered = document.renderFinal() {
                    PasteboardWriter.copy(image: rendered)
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("Save…") { saveAs() }
                .keyboardShortcut("s", modifiers: .command)
        }
        .padding(10)
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
}

struct BeautifyControls: View {
    @ObservedObject var document: EditorDocument

    var body: some View {
        HStack(spacing: 16) {
            Toggle("Enabled", isOn: binding(\.enabled))
            Picker("Background", selection: binding(\.gradient)) {
                ForEach(BeautifySettings.GradientPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .frame(width: 180)
            Picker("Aspect", selection: binding(\.aspectPreset)) {
                ForEach(BeautifySettings.AspectPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .frame(width: 140)
            HStack {
                Text("Padding")
                Slider(value: binding(\.padding), in: 0...200).frame(width: 100)
            }
            HStack {
                Text("Radius")
                Slider(value: binding(\.cornerRadius), in: 0...40).frame(width: 80)
            }
            HStack {
                Text("Shadow")
                Slider(value: binding(\.shadowRadius), in: 0...80).frame(width: 80)
            }
            Spacer()
        }
        .padding(10)
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
