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
        .frame(minWidth: 720, minHeight: 480)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Cohesive Tool Selector Pill
            HStack(spacing: 0) {
                ForEach(ToolKind.allCases) { kind in
                    let isSelected = toolKind == kind
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                            toolKind = kind
                        }
                    } label: {
                        Image(systemName: kind.symbolName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.85))
                            .frame(width: 26, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? Color.accentColor : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(kind == .select ? "Select — drag image to export" : kind.displayName)
                    .padding(.horizontal, 1)
                }
            }
            .padding(3)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )

            // Properties Inspector Pill
            HStack(spacing: 8) {
                ColorPicker("", selection: $color)
                    .labelsHidden()
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())
                
                Divider().frame(height: 14)
                
                HStack(spacing: 4) {
                    Image(systemName: "line.horizontal.3")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Slider(value: $lineWidth, in: 1...16)
                        .frame(width: 70)
                        .controlSize(.small)
                    Text("\(Int(lineWidth))px")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                }
                
                Divider().frame(height: 14)
                
                Toggle(isOn: $filled) {
                    Text("Fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.8))
                }
                .toggleStyle(.checkbox)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )

            // History & Beautify Tools
            HStack(spacing: 8) {
                // History Actions Pill
                HStack(spacing: 2) {
                    Button {
                        document.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 26, height: 24)
                    }
                    .buttonStyle(.plain)
                    .disabled(!document.undoStack.canUndo)
                    .opacity(document.undoStack.canUndo ? 1.0 : 0.4)
                    .keyboardShortcut("z", modifiers: .command)
                    
                    Divider().frame(height: 14)
                    
                    Button {
                        document.redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 26, height: 24)
                    }
                    .buttonStyle(.plain)
                    .disabled(!document.undoStack.canRedo)
                    .opacity(document.undoStack.canRedo ? 1.0 : 0.4)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                }
                .padding(2)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )

                // Beautify Toggle
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        showBeautify.toggle()
                        if showBeautify, !document.beautify.enabled {
                            var b = document.beautify
                            b.enabled = true
                            document.perform(SetBeautifyCommand(before: document.beautify, after: b))
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(showBeautify ? Color.white : Color.accentColor)
                        Text("Beautify")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(showBeautify ? Color.white : Color.primary.opacity(0.85))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(showBeautify ? Color.accentColor : Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(showBeautify ? Color.clear : Color.primary.opacity(0.06), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .help("Beautify capture background and borders")
            }

            Spacer()

            // Export Actions
            HStack(spacing: 8) {
                Button {
                    Task {
                        if let rendered = document.renderFinal(),
                           let text = try? await OCRService.recognizeText(in: rendered) {
                            PasteboardWriter.copy(text: text)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 10, weight: .bold))
                        Text("Copy Text")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(Color.purple)
                }
                .buttonStyle(.plain)
                .help("OCR the image and copy the text")
                
                Button {
                    if let rendered = document.renderFinal() {
                        PasteboardWriter.copy(image: rendered)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Copy")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                
                Button {
                    saveAs()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Save…")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.accentColor.opacity(0.25), radius: 4, x: 0, y: 1.5)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("s", modifiers: .command)
            }
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
            // Title & Toggle
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                    .font(.system(size: 11, weight: .bold))
                Toggle("Beautify Canvas", isOn: binding(\.enabled))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                Text("Beautify")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
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
