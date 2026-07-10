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
        .animation(
            AeroTokens.Motion.resolved(AeroTokens.Motion.standard, reduceMotion: reduceMotion),
            value: model.currentFrameIndex
        )
    }

    private var header: some View {
        HStack(spacing: AeroTokens.Spacing.small) {
            Label("GIF Studio", systemImage: "photo.stack")
                .font(AeroTokens.Typography.title())
            Text("\(model.document.frames.count) frames")
                .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
            Spacer()
            Button("Save", systemImage: "square.and.arrow.down") { model.saveNow() }
                .buttonStyle(AeroButtonStyle(kind: .secondary, size: .compact))
                .keyboardShortcut("s", modifiers: .command)
                .accessibilityIdentifier("gifStudio.save")
            Button("Export…", systemImage: "arrow.up.right.square") { chooseExport() }
                .buttonStyle(AeroButtonStyle(kind: .secondary, size: .compact))
                .disabled(model.exportProgress != nil)
                .accessibilityIdentifier("gifStudio.export")
        }
        .padding(AeroTokens.Spacing.medium)
    }

    private var preview: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if let image = model.previewImage {
                Image(nsImage: image).resizable().scaledToFit().padding(AeroTokens.Spacing.extraLarge)
                    .accessibilityLabel("Preview of frame \(model.currentFrameIndex + 1)")
                VStack(alignment: .leading) {
                    ForEach(model.activeAnnotations) { annotation in
                        Text(annotation.text).font(.headline).foregroundStyle(.white)
                            .padding(8).background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 6))
                    }
                    Spacer()
                }.padding(36).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                AeroEmptyState(title: "Preview unavailable", message: "", symbol: "photo.badge.exclamationmark")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: AeroTokens.Spacing.small) {
            HStack {
                Button("Trim", systemImage: "crop") { model.perform(.trim) }.keyboardShortcut("t", modifiers: .command)
                Button("Split", systemImage: "scissors") { model.perform(.split) }
                Button("Delete", systemImage: "trash") { model.perform(.delete) }.keyboardShortcut(.delete, modifiers: [])
                Button("Duplicate", systemImage: "plus.square.on.square") { model.perform(.duplicate) }.keyboardShortcut("d", modifiers: .command)
                Spacer()
                Button("Undo", systemImage: "arrow.uturn.backward") { model.perform(.undo) }.disabled(!model.canUndo).keyboardShortcut("z", modifiers: .command)
                Button("Redo", systemImage: "arrow.uturn.forward") { model.perform(.redo) }.disabled(!model.canRedo).keyboardShortcut("z", modifiers: [.command, .shift])
            }
            .buttonStyle(AeroButtonStyle(kind: .secondary, size: .compact))
            ScrollView(.horizontal) {
                LazyHStack(spacing: AeroTokens.Spacing.xs) {
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
                            .background(
                                model.selection.range.contains(index) ? AeroTokens.Fill.selected : AeroTokens.Fill.hover,
                                in: RoundedRectangle(cornerRadius: AeroTokens.Radius.small)
                            )
                            .overlay {
                                if model.selection.range.contains(index) {
                                    RoundedRectangle(cornerRadius: AeroTokens.Radius.small)
                                        .strokeBorder(AeroTokens.Stroke.accentSelected, lineWidth: AeroTokens.Stroke.accentSelectedWidth)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Frame \(index + 1), \(frame.durationMicroseconds / 1_000) milliseconds")
                        .accessibilityAddTraits(model.selection.range.contains(index) ? .isSelected : [])
                    }
                }.padding(.vertical, AeroTokens.Spacing.xxs)
            }
            .accessibilityLabel("GIF frame timeline")
            Text("Selection: frames \(model.selection.lowerBound + 1)–\(model.selection.upperBound), \(model.selectedDurationMicroseconds / 1_000) ms")
                .font(AeroTokens.Typography.small())
                .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
        }
        .padding(AeroTokens.Spacing.medium)
        .frame(height: 140)
    }

    private var inspector: some View {
        ScrollView {
            VStack(spacing: AeroTokens.Spacing.medium) {
                presetsPanel
                timingPanel
                loopControls
                playbackPanel
                dimensionsPanel
                annotationsPanel
                colorPanel
                qualityPanel
            }
            .padding(AeroTokens.Spacing.medium)
        }
    }

    private var presetsPanel: some View {
        AeroPanel("Presets", symbol: "square.grid.2x2") {
            HStack(spacing: AeroTokens.Spacing.small) {
                ForEach(GIFExportPreset.allCases) { preset in
                    Button(preset.displayName) { model.applyPreset(preset) }
                }
            }
            .buttonStyle(AeroButtonStyle(kind: .secondary, size: .compact))
            let sourceSize = model.previewImage?.size ?? CGSize(width: 1280, height: 720)
            HStack {
                LabeledContent("Documentation", value: ByteCountFormatter.string(fromByteCount: estimatedBytes(for: .documentation, sourceSize: sourceSize), countStyle: .file))
                Divider()
                LabeledContent("Social", value: ByteCountFormatter.string(fromByteCount: estimatedBytes(for: .social, sourceSize: sourceSize), countStyle: .file))
            }
            .font(AeroTokens.Typography.small())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Preset quality and size comparison")
        }
    }

    private var timingPanel: some View {
        AeroPanel("Timing", symbol: "timer") {
            AeroInspectorRow("Range duration") {
                TextField("Milliseconds", value: $durationMilliseconds, format: .number.precision(.fractionLength(0)))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .aeroFieldChrome()
                    .onSubmit { model.setSelectedDuration(milliseconds: durationMilliseconds) }
                    .accessibilityLabel("Selected range duration in milliseconds")
            }
            Text(model.effectiveDelayDescription(for: durationMilliseconds))
                .font(AeroTokens.Typography.small())
                .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
        }
    }

    private var playbackPanel: some View {
        AeroPanel("Playback", symbol: "play.circle") {
            AeroInspectorRow("Ping-pong") {
                AeroCompactToggle(title: "", isOn: settingsBinding(\.pingPong))
                    .accessibilityLabel("Ping-pong")
            }
            AeroInspectorRow("Speed") {
                HStack(spacing: AeroTokens.Spacing.xs) {
                    Button("0.5×") { model.setSelectedSpeed(0.5) }
                    Button("1×") { model.setSelectedSpeed(1) }
                    Button("2×") { model.setSelectedSpeed(2) }
                }
                .buttonStyle(AeroButtonStyle(kind: .secondary, size: .compact))
            }
        }
    }

    private var dimensionsPanel: some View {
        AeroPanel("Dimensions", symbol: "aspectratio") {
            optionalIntegerField("Width", value: model.document.settings.outputWidth) { value in model.updateSettings { $0.outputWidth = value } }
            optionalIntegerField("Height", value: model.document.settings.outputHeight) { value in model.updateSettings { $0.outputHeight = value } }
            HStack(spacing: AeroTokens.Spacing.small) {
                Button("Crop 5%") { model.updateSettings { $0.crop = .init(x: 0.05, y: 0.05, width: 0.9, height: 0.9) } }
                Button("Reset Crop") { model.updateSettings { $0.crop = nil } }
            }
            .buttonStyle(AeroButtonStyle(kind: .secondary, size: .compact))
        }
    }

    private var annotationsPanel: some View {
        AeroPanel("Timed annotations", symbol: "text.bubble") {
            TextField("Annotation text", text: $annotationText)
                .aeroFieldChrome()
            Button("Add to selected range") {
                model.addTimedAnnotation(annotationText)
                annotationText = ""
            }
            .buttonStyle(AeroButtonStyle(kind: .secondary, size: .compact))
            .disabled(annotationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ForEach(model.document.annotations) { annotation in
                Text("\(annotation.text) · \(annotation.range.startMicroseconds / 1_000)–\(annotation.range.endMicroseconds / 1_000) ms")
                    .font(AeroTokens.Typography.small())
            }
        }
    }

    private var colorPanel: some View {
        AeroPanel("Color", symbol: "paintpalette") {
            AeroInspectorRow("Palette") {
                AeroMenuPicker(options: [16, 32, 64, 128, 256], selection: settingsBinding(\.paletteSize), label: { "\($0) colors" })
                    .accessibilityLabel("Palette")
            }
            AeroInspectorRow("Dither") {
                AeroMenuPicker(options: [GIFDither.none, .ordered], selection: settingsBinding(\.dither), label: { $0 == GIFDither.none ? "None" : "Ordered" })
                    .accessibilityLabel("Dither")
            }
            AeroInspectorRow("Preserve transparency") {
                AeroCompactToggle(title: "", isOn: settingsBinding(\.preservesTransparency))
                    .accessibilityLabel("Preserve transparency")
            }
        }
    }

    private var qualityPanel: some View {
        AeroPanel("Quality & size", symbol: "gauge") {
            AeroInspectorRow("Quality") {
                Slider(value: settingsBinding(\.quality), in: 0...1) { Text("Quality") }
                    .labelsHidden()
                    .tint(AeroTokens.ColorRole.accent)
                    .frame(width: 140)
            }
            AeroInspectorRow("Estimate") {
                Text(ByteCountFormatter.string(fromByteCount: model.estimatedOutputBytes(sourceSize: model.previewImage?.size ?? CGSize(width: 1280, height: 720)), countStyle: .file))
                    .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
            }
            if let metadata = model.lastExportMetadata {
                AeroInspectorRow("Last export") {
                    Text(ByteCountFormatter.string(fromByteCount: metadata.byteCount, countStyle: .file))
                        .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
                }
                Text("Estimates are guidance; actual size depends on frame content.")
                    .font(AeroTokens.Typography.small())
                    .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
            }
        }
    }

    private func estimatedBytes(for preset: GIFExportPreset, sourceSize: CGSize) -> Int64 {
        var copy = model.document
        copy.settings = preset.applying(to: copy.settings)
        return copy.estimatedOutputBytes(sourceSize: sourceSize)
    }

    private var loopControls: some View {
        AeroPanel("Loop", symbol: "repeat") {
            AeroInspectorRow("Mode") {
                AeroMenuPicker(
                    options: [0, 1, 2],
                    selection: Binding(
                        get: {
                            switch model.document.settings.loop { case .once: 0; case .count: 1; case .forever: 2 }
                        },
                        set: { value in model.updateSettings { $0.loop = value == 0 ? .once : (value == 1 ? .count(3) : .forever) } }
                    ),
                    label: { value in value == 0 ? "Once" : (value == 1 ? "Count" : "Forever") }
                )
                .accessibilityLabel("Mode")
            }
            if case .count(let current) = model.document.settings.loop {
                AeroInspectorRow("Repeat \(current) times") {
                    Stepper("Repeat \(current) times", value: Binding(
                        get: { current }, set: { count in model.updateSettings { $0.loop = .count(count) } }
                    ), in: 1...100)
                    .labelsHidden()
                }
            }
        }
    }

    private var statusBar: some View {
        HStack {
            if let progress = model.exportProgress {
                AeroProgress(label: model.statusMessage, value: progress)
                    .frame(width: 220)
                Button("Cancel") { model.cancelExport() }
                    .buttonStyle(AeroButtonStyle(kind: .secondary, size: .compact))
            } else {
                Text(model.statusMessage).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Preview cache: ≤ \(GIFStudioDocument.previewCacheCountLimit) decoded frames").foregroundStyle(.tertiary)
        }
        .font(.caption)
        .padding(.horizontal, AeroTokens.Spacing.medium)
        .frame(minHeight: 30)
    }

    private func settingsBinding<T>(_ keyPath: WritableKeyPath<GIFExportSettings, T>) -> Binding<T> {
        Binding(get: { model.document.settings[keyPath: keyPath] }, set: { value in model.updateSettings { $0[keyPath: keyPath] = value } })
    }

    private func optionalIntegerField(_ title: String, value: Int?, set: @escaping (Int?) -> Void) -> some View {
        AeroInspectorRow(title) {
            TextField(title, text: Binding(get: { value.map(String.init) ?? "" }, set: { set(Int($0)) }))
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .aeroFieldChrome()
                .accessibilityLabel("Output \(title.lowercased()) in pixels; blank uses source")
        }
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
