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
        window.setContentSize(NSSize(width: 1080, height: 720))
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
    @State private var showInspector = false

    private var style: ToolStyle {
        ToolStyle(color: NSColor(color), lineWidth: lineWidth, fontSize: fontSize, filled: filled)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            EditorCanvasView(document: document, toolKind: toolKind, style: style)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            VStack(spacing: 8) {
                if showBeautify {
                    BeautifyControls(document: document)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding(.horizontal, 16)
                        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
                }
                
                if showInspector && hasProperties(for: toolKind) {
                    propertiesInspector
                }
                
                toolbar
            }
            .padding(.bottom, 20)
            .padding(.horizontal, 20)
        }
        .frame(minWidth: 960, minHeight: 520)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Tool selector pill
            HStack(spacing: 2) {
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
                            .frame(width: 28, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? Color.accentColor : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(kind == .select ? "Select — drag image to export" : kind.displayName)
                }
            }
            .padding(3)
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
            .fixedSize()
            
            // Undo/Redo/Zoom Pill
            HStack(spacing: 6) {
                // Undo/Redo
                HStack(spacing: 2) {
                    Button { document.undo() } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 26, height: 24)
                    }
                    .buttonStyle(.plain)
                    .disabled(!document.undoStack.canUndo)
                    .opacity(document.undoStack.canUndo ? 1.0 : 0.4)
                    .keyboardShortcut("z", modifiers: .command)
                    
                    Button { document.redo() } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 26, height: 24)
                    }
                    .buttonStyle(.plain)
                    .disabled(!document.undoStack.canRedo)
                    .opacity(document.undoStack.canRedo ? 1.0 : 0.4)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                }
                
                Divider().frame(height: 14)
                
                // Zoom
                HStack(spacing: 2) {
                    Button {
                        document.zoomScale = max(0.1, document.zoomScale - 0.1)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    
                    Text("\(Int(document.zoomScale * 100))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .frame(width: 36, alignment: .center)
                    
                    Button {
                        document.zoomScale = min(10.0, document.zoomScale + 0.1)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            document.zoomScale = 1.0
                            document.panOffset = .zero
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9))
                            .frame(width: 20, height: 20)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
            .fixedSize()
            
            // Beautify & Actions
            HStack(spacing: 8) {
                // Beautify
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
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(showBeautify ? Color.white : Color.accentColor)
                        Text("Beautify")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(showBeautify ? Color.white : Color.primary.opacity(0.85))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(showBeautify ? Color.accentColor : Color.clear)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                // Inspector Toggle
                if hasProperties(for: toolKind) {
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                            showInspector.toggle()
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(showInspector ? Color.white : Color.primary.opacity(0.85))
                            .frame(width: 28, height: 26)
                            .background(showInspector ? Color.accentColor : Color.clear)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .help("Tool Properties")
                }
            }
            .padding(3)
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
            .fixedSize()
            
            // Export actions (Copy Text, Copy Image, Save)
            HStack(spacing: 6) {
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
                        Text("Text")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.purple.opacity(0.15))
                    .foregroundStyle(Color.purple)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button {
                    if let rendered = document.renderFinal() {
                        PasteboardWriter.copy(image: rendered)
                    }
                } label: {
                    Text("Copy")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button {
                    saveAs()
                } label: {
                    Text("Save…")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(3)
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.12))
        .background(.ultraThinMaterial)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 6)
    }

    private var propertiesInspector: some View {
        HStack(spacing: 16) {
            if supportsColor(toolKind) {
                HStack(spacing: 8) {
                    Text("Color")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    
                    ColorPicker("", selection: $color)
                        .labelsHidden()
                        .frame(width: 22, height: 22)
                        .clipShape(Circle())
                }
            }
            
            if supportsLineWidth(toolKind) {
                if supportsColor(toolKind) { Divider().frame(height: 14) }
                HStack(spacing: 6) {
                    Text("Width")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Slider(value: $lineWidth, in: 1...16)
                        .frame(width: 80)
                        .controlSize(.small)
                    Text("\(Int(lineWidth))px")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
            }
            
            if supportsFill(toolKind) {
                Divider().frame(height: 14)
                Toggle(isOn: $filled) {
                    Text("Fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.checkbox)
            }
            
            if supportsFontSize(toolKind) {
                if supportsColor(toolKind) { Divider().frame(height: 14) }
                HStack(spacing: 6) {
                    Text("Size")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Slider(value: $fontSize, in: 12...72)
                        .frame(width: 80)
                        .controlSize(.small)
                    Text("\(Int(fontSize))pt")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        .fixedSize()
    }

    private func hasProperties(for kind: ToolKind) -> Bool {
        switch kind {
        case .select, .pan, .crop, .redactBlur, .redactPixelate:
            return false
        default:
            return true
        }
    }

    private func supportsColor(_ kind: ToolKind) -> Bool {
        switch kind {
        case .select, .pan, .crop, .redactBlur, .redactPixelate: return false
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
