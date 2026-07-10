import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GIFStudioView: View {
    @ObservedObject var model: GIFStudioDocument
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var durationMilliseconds = 100.0
    @State private var annotationText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                VStack(spacing: 0) {
                    preview
                    Divider()
                    timeline
                }
                .frame(minWidth: 620)
                inspector.frame(minWidth: 270, idealWidth: 300, maxWidth: 360)
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 940, minHeight: 660)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress { handleKey($0) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: model.currentFrameIndex)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("GIF Studio", systemImage: "photo.stack")
                .font(.headline)
            Text("\(model.document.frames.count) frames")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Save", systemImage: "square.and.arrow.down") { model.saveNow() }
                .keyboardShortcut("s", modifiers: .command)
                .accessibilityIdentifier("gifStudio.save")
            Button("Export…", systemImage: "arrow.up.right.square") { chooseExport() }
                .disabled(model.exportProgress != nil)
                .accessibilityIdentifier("gifStudio.export")
        }
        .padding(12)
    }

    private var preview: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if let image = model.previewImage {
                Image(nsImage: image).resizable().scaledToFit().padding(24)
                    .accessibilityLabel("Preview of frame \(model.currentFrameIndex + 1)")
                VStack(alignment: .leading) {
                    ForEach(model.activeAnnotations) { annotation in
                        Text(annotation.text).font(.headline).foregroundStyle(.white)
                            .padding(8).background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 6))
                    }
                    Spacer()
                }.padding(36).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView("Preview unavailable", systemImage: "photo.badge.exclamationmark")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Trim", systemImage: "crop") { model.perform(.trim) }.keyboardShortcut("t", modifiers: .command)
                Button("Split", systemImage: "scissors") { model.perform(.split) }
                Button("Delete", systemImage: "trash") { model.perform(.delete) }.keyboardShortcut(.delete, modifiers: [])
                Button("Duplicate", systemImage: "plus.square.on.square") { model.perform(.duplicate) }.keyboardShortcut("d", modifiers: .command)
                Spacer()
                Button("Undo", systemImage: "arrow.uturn.backward") { model.perform(.undo) }.disabled(!model.canUndo).keyboardShortcut("z", modifiers: .command)
                Button("Redo", systemImage: "arrow.uturn.forward") { model.perform(.redo) }.disabled(!model.canRedo).keyboardShortcut("z", modifiers: [.command, .shift])
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 4) {
                    ForEach(Array(model.document.frames.enumerated()), id: \.element.id) { index, frame in
                        Button {
                            model.selectFrame(index)
                            durationMilliseconds = Double(frame.durationMicroseconds) / 1_000
                        } label: {
                            VStack(spacing: 3) {
                                Text("\(index + 1)").font(.caption.monospacedDigit())
                                Text("\(frame.durationMicroseconds / 1_000) ms").font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(width: 58, height: 42)
                            .background(model.selection.range.contains(index) ? Color.accentColor.opacity(0.24) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Frame \(index + 1), \(frame.durationMicroseconds / 1_000) milliseconds")
                        .accessibilityAddTraits(model.selection.range.contains(index) ? .isSelected : [])
                    }
                }.padding(.vertical, 2)
            }
            .accessibilityLabel("GIF frame timeline")
            Text("Selection: frames \(model.selection.lowerBound + 1)–\(model.selection.upperBound), \(model.selectedDurationMicroseconds / 1_000) ms")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(height: 140)
    }

    private var inspector: some View {
            Form {
                Section("Presets") {
                    HStack {
                        ForEach(GIFExportPreset.allCases) { preset in
                            Button(preset.displayName) { model.applyPreset(preset) }
                        }
                    }
                    let sourceSize = model.previewImage?.size ?? CGSize(width: 1280, height: 720)
                    HStack {
                        LabeledContent("Documentation", value: ByteCountFormatter.string(fromByteCount: estimatedBytes(for: .documentation, sourceSize: sourceSize), countStyle: .file))
                        Divider()
                        LabeledContent("Social", value: ByteCountFormatter.string(fromByteCount: estimatedBytes(for: .social, sourceSize: sourceSize), countStyle: .file))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Preset quality and size comparison")
                }
                Section("Timing") {
                LabeledContent("Range duration") {
                    TextField("Milliseconds", value: $durationMilliseconds, format: .number.precision(.fractionLength(0)))
                        .frame(width: 80).multilineTextAlignment(.trailing)
                        .onSubmit { model.setSelectedDuration(milliseconds: durationMilliseconds) }
                        .accessibilityLabel("Selected range duration in milliseconds")
                }
                Text(model.effectiveDelayDescription(for: durationMilliseconds)).font(.caption).foregroundStyle(.secondary)
            }
            loopControls
            Section("Playback") {
                Toggle("Ping-pong", isOn: settingsBinding(\.pingPong))
                HStack {
                    Text("Speed")
                    Button("0.5×") { model.setSelectedSpeed(0.5) }
                    Button("1×") { model.setSelectedSpeed(1) }
                    Button("2×") { model.setSelectedSpeed(2) }
                }
            }
            Section("Dimensions") {
                optionalIntegerField("Width", value: model.document.settings.outputWidth) { value in model.updateSettings { $0.outputWidth = value } }
                optionalIntegerField("Height", value: model.document.settings.outputHeight) { value in model.updateSettings { $0.outputHeight = value } }
                Button("Crop 5%") { model.updateSettings { $0.crop = .init(x: 0.05, y: 0.05, width: 0.9, height: 0.9) } }
                Button("Reset Crop") { model.updateSettings { $0.crop = nil } }
            }
            Section("Timed annotations") {
                TextField("Annotation text", text: $annotationText)
                Button("Add to selected range") {
                    model.addTimedAnnotation(annotationText)
                    annotationText = ""
                }.disabled(annotationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                ForEach(model.document.annotations) { annotation in
                    Text("\(annotation.text) · \(annotation.range.startMicroseconds / 1_000)–\(annotation.range.endMicroseconds / 1_000) ms")
                        .font(.caption)
                }
            }
            Section("Color") {
                Picker("Palette", selection: settingsBinding(\.paletteSize)) {
                    ForEach([16, 32, 64, 128, 256], id: \.self) { Text("\($0) colors").tag($0) }
                }
                Picker("Dither", selection: settingsBinding(\.dither)) {
                    Text("None").tag(GIFDither.none)
                    Text("Ordered").tag(GIFDither.ordered)
                }
                Toggle("Preserve transparency", isOn: settingsBinding(\.preservesTransparency))
            }
            Section("Quality & size") {
                Slider(value: settingsBinding(\.quality), in: 0...1) { Text("Quality") }
                LabeledContent("Estimate", value: ByteCountFormatter.string(fromByteCount: model.estimatedOutputBytes(sourceSize: model.previewImage?.size ?? CGSize(width: 1280, height: 720)), countStyle: .file))
                if let metadata = model.lastExportMetadata {
                    LabeledContent("Last export", value: ByteCountFormatter.string(fromByteCount: metadata.byteCount, countStyle: .file))
                    Text("Estimates are guidance; actual size depends on frame content.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func estimatedBytes(for preset: GIFExportPreset, sourceSize: CGSize) -> Int64 {
        var copy = model.document
        copy.settings = preset.applying(to: copy.settings)
        return copy.estimatedOutputBytes(sourceSize: sourceSize)
    }

    private var loopControls: some View {
        Section("Loop") {
            Picker("Mode", selection: Binding(
                get: {
                    switch model.document.settings.loop { case .once: 0; case .count: 1; case .forever: 2 }
                },
                set: { value in model.updateSettings { $0.loop = value == 0 ? .once : (value == 1 ? .count(3) : .forever) } }
            )) {
                Text("Once").tag(0); Text("Count").tag(1); Text("Forever").tag(2)
            }
            if case .count(let current) = model.document.settings.loop {
                Stepper("Repeat \(current) times", value: Binding(
                    get: { current }, set: { count in model.updateSettings { $0.loop = .count(count) } }
                ), in: 1...100)
            }
        }
    }

    private var statusBar: some View {
        HStack {
            if let progress = model.exportProgress { ProgressView(value: progress).frame(width: 120); Button("Cancel") { model.cancelExport() } }
            Text(model.statusMessage).foregroundStyle(.secondary)
            Spacer()
            Text("Preview cache: ≤ \(GIFStudioDocument.previewCacheCountLimit) decoded frames").foregroundStyle(.tertiary)
        }.font(.caption).padding(.horizontal, 12).frame(height: 30)
    }

    private func settingsBinding<T>(_ keyPath: WritableKeyPath<GIFExportSettings, T>) -> Binding<T> {
        Binding(get: { model.document.settings[keyPath: keyPath] }, set: { value in model.updateSettings { $0[keyPath: keyPath] = value } })
    }

    private func optionalIntegerField(_ title: String, value: Int?, set: @escaping (Int?) -> Void) -> some View {
        TextField(title, text: Binding(get: { value.map(String.init) ?? "" }, set: { set(Int($0)) }))
            .accessibilityLabel("Output \(title.lowercased()) in pixels; blank uses source")
    }

    private func chooseExport() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.gif]; panel.nameFieldStringValue = "Export.gif"
        if panel.runModal() == .OK, let url = panel.url { model.export(to: url) }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .leftArrow: model.moveSelection(by: -1, extending: press.modifiers.contains(.shift)); return .handled
        case .rightArrow: model.moveSelection(by: 1, extending: press.modifiers.contains(.shift)); return .handled
        default: return .ignored
        }
    }
}
