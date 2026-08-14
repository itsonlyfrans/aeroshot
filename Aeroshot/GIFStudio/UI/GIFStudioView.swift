import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// GIF Studio follows the same compact, dark surface language as the design
/// concept while keeping every edit routed through `GIFStudioDocument`.
struct GIFStudioView: View {
    @ObservedObject var model: GIFStudioDocument

    @State private var durationMilliseconds = 100.0
    @State private var annotationText = ""
    @State private var targetBudget = 0
    @State private var dedupeEnabled = false
    @State private var skipRate = 1
    @State private var speed = 1.0
    @State private var reverseEnabled = false
    @State private var selectedAnnotationID: UUID?
    @State private var selectedAnnotationText = ""
    @FocusState private var keyboardFocus: Bool
    @FocusState private var annotationEditorFocused: Bool

    private enum Palette {
        static let background = Color(red: 11.0 / 255.0, green: 12.0 / 255.0, blue: 15.0 / 255.0)
        static let surface = Color(red: 19.0 / 255.0, green: 21.0 / 255.0, blue: 25.0 / 255.0)
        static let raised = Color(red: 25.0 / 255.0, green: 28.0 / 255.0, blue: 34.0 / 255.0)
        static let inset = Color(red: 14.0 / 255.0, green: 16.0 / 255.0, blue: 20.0 / 255.0)
        static let text = Color(red: 237.0 / 255.0, green: 238.0 / 255.0, blue: 241.0 / 255.0)
        static let secondary = Color(red: 156.0 / 255.0, green: 161.0 / 255.0, blue: 171.0 / 255.0)
        static let tertiary = Color(red: 102.0 / 255.0, green: 107.0 / 255.0, blue: 117.0 / 255.0)
        static let border = Color.white.opacity(0.075)
        static let borderStrong = Color.white.opacity(0.15)
        static let accent = Color(red: 1.0, green: 138.0 / 255.0, blue: 107.0 / 255.0)
        static let success = Color(red: 95.0 / 255.0, green: 211.0 / 255.0, blue: 160.0 / 255.0)
        static let warning = Color(red: 1.0, green: 180.0 / 255.0, blue: 84.0 / 255.0)
    }

    private struct RibbonFrame: Identifiable {
        let id: UUID
        var sourceIndices: [Int]
        var durationMicroseconds: Int64
    }

    private struct BudgetPlan {
        let width: Int
        let palette: Int
        let skip: Int
        let bytes: Int64
        let overBudget: Bool
    }

    private var sourceSize: CGSize {
        model.previewImage?.size ?? CGSize(width: 1_280, height: 720)
    }

    private var totalDurationMicroseconds: Int64 {
        max(1, model.document.durationMicroseconds)
    }

    private var selectedFrameIndex: Int {
        min(max(0, model.currentFrameIndex), max(0, model.document.frames.count - 1))
    }

    private var selectedFrame: GIFFrame? {
        model.document.frames.indices.contains(selectedFrameIndex) ? model.document.frames[selectedFrameIndex] : nil
    }

    private var selectedAnnotation: GIFTimedAnnotation? {
        model.document.annotations.first { $0.id == selectedAnnotationID }
    }

    private var selectedFrameStartMicroseconds: Int64 {
        guard let range = try? model.document.timeRange(forFrameAt: selectedFrameIndex) else { return 0 }
        return range.startMicroseconds
    }

    private var activePreset: GIFExportPreset {
        let settings = model.document.settings
        return settings.paletteSize == 128 && settings.dither == .none && settings.preservesTransparency
            ? .documentation
            : .social
    }

    private var ribbonFrames: [RibbonFrame] {
        var result = model.document.frames.enumerated().map {
            RibbonFrame(id: $0.element.id, sourceIndices: [$0.offset], durationMicroseconds: $0.element.durationMicroseconds)
        }

        if dedupeEnabled {
            var merged: [RibbonFrame] = []
            for frame in result {
                if let previous = merged.last,
                   model.document.frames[previous.sourceIndices.last ?? 0].sourceURL == model.document.frames[frame.sourceIndices.first ?? 0].sourceURL {
                    merged[merged.count - 1].durationMicroseconds += frame.durationMicroseconds
                    merged[merged.count - 1].sourceIndices.append(contentsOf: frame.sourceIndices)
                } else {
                    merged.append(frame)
                }
            }
            result = merged
        }

        if skipRate > 1 {
            var skipped: [RibbonFrame] = []
            for (offset, frame) in result.enumerated() {
                if offset % skipRate == 0 || skipped.isEmpty {
                    skipped.append(frame)
                } else {
                    skipped[skipped.count - 1].durationMicroseconds += frame.durationMicroseconds
                    skipped[skipped.count - 1].sourceIndices.append(contentsOf: frame.sourceIndices)
                }
            }
            result = skipped
        }

        if reverseEnabled { result.reverse() }
        return result
    }

    private var estimatedBytes: Int64 {
        model.estimatedOutputBytes(sourceSize: sourceSize)
    }

    private var budgetPlan: BudgetPlan? {
        guard targetBudget > 0 else { return nil }
        let cap = Int64(targetBudget) * 1_024 * 1_024
        let currentWidth = model.document.settings.outputWidth ?? max(1, Int(sourceSize.width))
        let currentPalette = model.document.settings.paletteSize
        let widths = [currentWidth, 1_280, 900, 640, 480].filter { $0 > 0 }
        let palettes = [currentPalette, 128, 64, 32, 16]
        let frameCount = max(1, ribbonFrames.count)

        for skip in 1...3 {
            let count = Int64((frameCount + skip - 1) / skip)
            for width in widths {
                for palette in palettes {
                    let bytes = estimateBytes(width: width, palette: palette, frameCount: count)
                    if bytes <= cap { return BudgetPlan(width: width, palette: palette, skip: skip, bytes: bytes, overBudget: false) }
                }
            }
        }

        let floorWidth = widths.last ?? 480
        let floorPalette = palettes.last ?? 16
        return BudgetPlan(width: floorWidth, palette: floorPalette,
                          skip: 3, bytes: estimateBytes(width: floorWidth, palette: floorPalette,
                                                         frameCount: Int64((frameCount + 2) / 3)), overBudget: true)
    }

    private var fpsText: String {
        let seconds = Double(totalDurationMicroseconds) / 1_000_000
        guard seconds > 0 else { return "0.0 fps" }
        return String(format: "%.1f fps", Double(ribbonFrames.count) / seconds)
    }

    var body: some View {
        VStack(spacing: 0) {
            titlebar
            Rectangle().fill(Palette.border).frame(height: 1)
            HSplitView {
                VStack(spacing: 0) {
                    preview
                    Rectangle().fill(Palette.border).frame(height: 1)
                    transportAndTimeline
                }
                .frame(minWidth: 720)

                inspector
                    .frame(minWidth: 320, idealWidth: 334, maxWidth: 390)
            }
            Rectangle().fill(Palette.border).frame(height: 1)
            statusBar
        }
        .background(Palette.surface)
        .preferredColorScheme(.dark)
        .frame(minWidth: 1_100, minHeight: 720)
        .focusable()
        .focused($keyboardFocus)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.accent.opacity(keyboardFocus ? 0.9 : 0), lineWidth: 2)
                .padding(1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onKeyPress { handleKey($0) }
        .onAppear { syncDuration() }
        .onChange(of: model.currentFrameIndex) { _, _ in syncDuration() }
        .onDisappear { model.cancelPlayback() }
    }

    private var titlebar: some View {
        HStack(spacing: 12) {
            // The native traffic lights occupy this leading area in the full-size titlebar.
            Spacer().frame(width: 66)
            Image(systemName: "scope")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.packageURL?.deletingPathExtension().lastPathComponent ?? "reticle-intent-switch.gif")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text("\(ribbonFrames.count) frames · \(fpsText) · \(formatDuration(totalDurationMicroseconds))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.tertiary)
            }
            Rectangle().fill(Palette.border).frame(width: 1, height: 26).padding(.horizontal, 4)
            HStack(spacing: 3) {
                ForEach(GIFExportPreset.allCases) { preset in
                    chip(preset.displayName, selected: activePreset == preset) {
                        model.applyPreset(preset)
                    }
                    .accessibilityIdentifier("gifStudio.preset.\(preset.rawValue)")
                }
            }
            .padding(3)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.border, lineWidth: 1))
            Text(activePreset == .documentation ? "palette 128 · alpha kept" : "max 1280 wide · ordered")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.tertiary)
                .lineLimit(1)

            Spacer(minLength: 10)
            VStack(alignment: .trailing, spacing: 3) {
                Text("EST")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Palette.tertiary)
                Text(ByteCountFormatter.string(fromByteCount: estimatedBytes, countStyle: .file))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.text)
            }
            Text("\(model.document.settings.outputWidth.map(String.init) ?? "source") px wide · palette \(model.document.settings.paletteSize)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.tertiary)
                .lineLimit(1)
            Button { model.saveNow() } label: {
                Image(systemName: "square.and.arrow.down")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(GIFSecondaryButtonStyle())
            .keyboardShortcut("s", modifiers: .command)
            .accessibilityIdentifier("gifStudio.save")
            .accessibilityLabel("Save GIF Studio project")
            .accessibilityHint("Saves the editable project without exporting a GIF")
            Button {
                chooseExport()
            } label: {
                HStack(spacing: 8) {
                    Text("Write GIF")
                    Text("⌘E").font(.system(size: 9, weight: .semibold, design: .monospaced)).opacity(0.6)
                }
            }
            .buttonStyle(GIFPrimaryButtonStyle())
            .keyboardShortcut("e", modifiers: .command)
            .disabled(model.exportProgress != nil)
            .accessibilityIdentifier("gifStudio.export")
            .accessibilityLabel("Export GIF")
            .accessibilityHint("Opens the save panel to write an animated GIF")
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(Palette.inset)
    }

    private var preview: some View {
        GeometryReader { proxy in
            ZStack {
                GIFDotGrid()
                    .fill(Palette.inset)
                if let image = model.previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(24)
                        .shadow(color: .black.opacity(0.55), radius: 24, y: 12)
                        .accessibilityLabel("Preview of frame \(selectedFrameIndex + 1)")
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 30))
                        Text("Preview unavailable")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Palette.secondary)
                }

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 7) {
                        Text("FRAME \(selectedFrameIndex + 1)/\(max(1, model.document.frames.count))")
                            .foregroundStyle(Palette.accent)
                        Text("\(formatDuration(selectedFrameStartMicroseconds)) · \(selectedFrame?.durationMicroseconds ?? 0)µs")
                            .foregroundStyle(Palette.tertiary)
                    }
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Palette.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Palette.borderStrong, lineWidth: 1))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(34)

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.inset)
    }

    private var transportAndTimeline: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    model.togglePlayback()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 36, height: 32)
                }
                .buttonStyle(GIFPrimaryButtonStyle())
                .accessibilityIdentifier("gifStudio.playPause")
                .accessibilityLabel(model.isPlaying ? "Pause animated preview" : "Play animated preview")
                .accessibilityValue(model.isPlaying ? "Playing" : "Paused")
                compactIconButton("chevron.left", label: "Previous frame") { model.moveSelection(by: -1) }
                compactIconButton("chevron.right", label: "Next frame") { model.moveSelection(by: 1) }
                Text("\(formatDuration(model.playbackPositionMicroseconds)) / \(formatDuration(model.playbackDurationMicroseconds))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 126, alignment: .leading)
                Slider(
                    value: Binding(get: { model.playbackProgress }, set: { model.scrub(to: $0) }),
                    in: 0...1,
                    onEditingChanged: { editing in editing ? model.beginScrubbing() : model.endScrubbing() }
                )
                .tint(Palette.accent)
                .frame(width: 140)
                .accessibilityIdentifier("gifStudio.scrubber")
                .accessibilityLabel("Animated preview position")
                .accessibilityValue("Frame \(selectedFrameIndex + 1) of \(max(1, model.document.frames.count))")
                Rectangle().fill(Palette.border).frame(width: 1, height: 24)
                Text("LOOP")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Palette.tertiary)
                chip("Once", selected: loopValue == 0) { setLoopValue(0) }
                chip("3×", selected: loopValue == 1) { setLoopValue(1) }
                chip("∞", selected: loopValue == 2) { setLoopValue(2) }
                chip("Ping-pong", selected: model.document.settings.pingPong) {
                    model.updateSettings { $0.pingPong.toggle() }
                }
                Spacer(minLength: 6)
                Text("Each block's width is its real duration — drag the seam to retime.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.tertiary)
                    .lineLimit(1)
            }

            durationRibbon
            captionsTrack
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Palette.inset)
        .frame(height: 180)
    }

    private var durationRibbon: some View {
        GeometryReader { proxy in
            let frames = ribbonFrames
            let total = max(1, frames.reduce(Int64(0)) { $0 + $1.durationMicroseconds })
            let gaps = CGFloat(max(0, frames.count - 1) * 2)
            let available = max(1, proxy.size.width - 14 - gaps)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Palette.raised)
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Palette.border, lineWidth: 1))
                HStack(spacing: 2) {
                    ForEach(Array(frames.enumerated()), id: \.element.id) { index, frame in
                        let durationFraction = CGFloat(frame.durationMicroseconds) / CGFloat(total)
                        let width = max(14, available * durationFraction)
                        Button {
                            selectRibbonFrame(frame)
                        } label: {
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(LinearGradient(colors: [Palette.accent.opacity(0.12 + Double(index % 5) * 0.04), Color.blue.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .overlay {
                                        if model.previewImage != nil && frame.sourceIndices.contains(selectedFrameIndex) {
                                            Image(nsImage: model.previewImage!)
                                                .resizable()
                                                .scaledToFill()
                                                .opacity(0.35)
                                                .clipped()
                                        }
                                    }
                                Text("\(frame.durationMicroseconds / 1_000)ms")
                                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(frame.sourceIndices.contains(selectedFrameIndex) ? Palette.accent : Palette.tertiary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                            .frame(width: width, height: 60)
                            .background(frame.sourceIndices.contains(selectedFrameIndex) ? Palette.accent.opacity(0.12) : Palette.inset,
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(frame.sourceIndices.contains(selectedFrameIndex) ? Palette.accent : Palette.border, lineWidth: frame.sourceIndices.contains(selectedFrameIndex) ? 1.2 : 1))
                        }
                        .buttonStyle(GIFControlButtonStyle())
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(Palette.accent.opacity(0.85)).frame(width: 2).padding(.vertical, 5)
                                .opacity(frame.sourceIndices.contains(selectedFrameIndex) ? 1 : 0)
                        }
                        .accessibilityLabel("Frame \(frame.sourceIndices.first.map { $0 + 1 } ?? index + 1), \(frame.durationMicroseconds / 1_000) milliseconds")
                        .accessibilityValue(frame.sourceIndices.contains(selectedFrameIndex) ? "Selected" : "Not selected")
                        .accessibilityAddTraits(frame.sourceIndices.contains(selectedFrameIndex) ? .isSelected : [])
                        .contentShape(Rectangle().inset(by: -6))
                    }
                }
                .padding(7)

                Rectangle()
                    .fill(.white)
                    .frame(width: 2)
                    .shadow(color: .white.opacity(0.7), radius: 5)
                    .offset(x: min(max(7, 7 + proxy.size.width * model.playbackProgress), proxy.size.width - 8))
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 74)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("GIF frame timeline")
        .accessibilityValue("Frame \(selectedFrameIndex + 1) of \(max(1, model.document.frames.count))")
    }

    private var captionsTrack: some View {
        GeometryReader { proxy in
            captionsTrack(width: proxy.size.width)
        }
        .frame(height: 34)
    }

    private func captionsTrack(width: CGFloat) -> some View {
        let total = Double(totalDurationMicroseconds)
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Palette.raised)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Palette.border, lineWidth: 1))
            Text("CAPTIONS")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Palette.tertiary)
                .padding(.leading, 9)
            ForEach(model.document.annotations) { annotation in
                let start = CGFloat(Double(annotation.range.startMicroseconds) / total)
                let fraction = CGFloat(Double(annotation.range.durationMicroseconds) / total)
                Button {
                    selectFrame(atMicroseconds: annotation.range.startMicroseconds)
                } label: {
                    Text(annotation.text)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(GIFControlButtonStyle())
                .frame(width: max(42, width * fraction * 0.86), height: 24)
                .offset(x: 84 + width * start * 0.86)
                .background(Palette.text.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Palette.borderStrong, lineWidth: 1))
                .accessibilityLabel("Caption: \(annotation.text)")
                .contentShape(Rectangle().inset(by: -4))
            }
        }
        .clipped()
    }

    private var inspector: some View {
        ScrollView {
            VStack(spacing: 0) {
                selectedFrameSection
                timingFramesSection
                colourOutputSection
                captionsSection
            }
        }
        .background(Palette.inset)
    }

    private var selectedFrameSection: some View {
        inspectorSection("Selected frame") {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.accent.opacity(0.3), Color.blue.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 42)
                    .overlay {
                        if let image = model.previewImage {
                            Image(nsImage: image).resizable().scaledToFill().clipped().opacity(0.45)
                        }
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Frame \(selectedFrameIndex + 1) · \((selectedFrame?.durationMicroseconds ?? 0) / 1_000)ms")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text("\(selectedFrame?.durationMicroseconds ?? 0) µs · starts \(formatDuration(selectedFrameStartMicroseconds))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.tertiary)
                        .lineLimit(1)
                }
            }
            HStack(spacing: 6) {
                inspectorButton("−20ms") { adjustSelectedDuration(by: -20) }
                inspectorButton("+20ms") { adjustSelectedDuration(by: 20) }
                inspectorButton("⌫") { model.perform(.delete) }
                    .foregroundStyle(Palette.tertiary)
                    .accessibilityLabel("Delete selected frame")
            }
            HStack(spacing: 10) {
                Text("Duration")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                Spacer()
                TextField("Milliseconds", value: $durationMilliseconds,
                          format: .number.precision(.fractionLength(0)))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 82)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.setSelectedDuration(milliseconds: durationMilliseconds) }
                    .accessibilityLabel("Selected frame duration in milliseconds")
            }
            HStack(spacing: 6) {
                inspectorButton("Even out all") { evenOutFrames() }
                inspectorButton("Hold last 1s") { holdLastFrame() }
            }
        }
    }

    private var timingFramesSection: some View {
        inspectorSection("Timing & frames") {
            HStack {
                sectionLabel("TARGET SIZE")
                Spacer()
                Text(targetBudget == 0 ? "off" : "(targetBudget) MB")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.tertiary)
            }
            HStack(spacing: 4) {
                chip("Off", selected: targetBudget == 0) { targetBudget = 0 }
                chip("2 MB", selected: targetBudget == 2) { targetBudget = 2 }
                chip("5 MB", selected: targetBudget == 5) { targetBudget = 5 }
                chip("10 MB", selected: targetBudget == 10) { targetBudget = 10 }
            }
            if let plan = budgetPlan {
                Text(plan.overBudget ? "Cannot fit — floor is \(plan.width) px · \(plan.palette) colours" : "Fits at \(plan.width) px · \(plan.palette) colours\(plan.skip > 1 ? " · every \(plan.skip == 2 ? "2nd" : "3rd") frame" : "")")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(plan.overBudget ? Palette.warning : Palette.success)
            }

            Button {
                dedupeEnabled.toggle()
            } label: {
                HStack(spacing: 7) {
                    Text("⧉").font(.system(size: 11, weight: .semibold, design: .monospaced))
                    Text(dedupeEnabled ? "Duplicates merged" : "Merge duplicate frames")
                    Spacer()
                    if dedupeEnabled { Text("on").font(.system(size: 9, weight: .bold, design: .monospaced)) }
                }
                .foregroundStyle(dedupeEnabled ? Palette.accent : Palette.secondary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(dedupeEnabled ? Palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(dedupeEnabled ? Palette.accent.opacity(0.35) : Palette.border, lineWidth: 1))
            }
            .buttonStyle(GIFControlButtonStyle())
            .accessibilityLabel(dedupeEnabled ? "Duplicates merged" : "Merge duplicate frames")
            .accessibilityValue(dedupeEnabled ? "On" : "Off")
            .accessibilityAddTraits(dedupeEnabled ? .isSelected : [])

            segmentedLabel("KEEP FRAMES")
            HStack(spacing: 4) {
                chip("All", selected: skipRate == 1) { skipRate = 1 }
                chip("Every 2nd", selected: skipRate == 2) { skipRate = 2 }
                chip("Every 3rd", selected: skipRate == 3) { skipRate = 3 }
            }

            segmentedLabel("SPEED")
            HStack(spacing: 4) {
                chip("0.5×", selected: speed == 0.5) { setSpeed(0.5) }
                chip("1×", selected: speed == 1) { setSpeed(1) }
                chip("1.5×", selected: speed == 1.5) { setSpeed(1.5) }
                chip("2×", selected: speed == 2) { setSpeed(2) }
            }

            HStack(spacing: 5) {
                chip("Reverse", selected: reverseEnabled) { reverseEnabled.toggle() }
                chip("Crop", selected: model.document.settings.crop != nil) { toggleCrop() }
            }
        }
    }

    private var colourOutputSection: some View {
        inspectorSection("Colour & output") {
            HStack {
                sectionLabel("PALETTE SIZE")
                Spacer()
                Text("\(model.document.settings.paletteSize) colours · \(max(1, Int(ceil(log2(Double(model.document.settings.paletteSize))))) )-bit")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.secondary)
            }
            Slider(
                value: Binding(get: { Double(model.document.settings.paletteSize) }, set: { value in
                    model.previewSettings { $0.paletteSize = min(256, max(2, Int(value.rounded()))) }
                }),
                in: 2...256,
                step: 2,
                onEditingChanged: { editing in
                    if editing { model.beginContinuousEdit() }
                    else { _ = model.commitContinuousEdit() }
                }
            )
            .tint(Palette.accent)
            .accessibilityLabel("Palette size")
            HStack(spacing: 2) {
                ForEach(0..<16, id: \.self) { index in
                    Rectangle().fill(Palette.accent.opacity(0.16 + Double(index % 6) * 0.07)).frame(height: 16)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            HStack {
                sectionLabel("QUALITY")
                Spacer()
                Text("\(Int(model.document.settings.quality * 100))%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.secondary)
            }
            Slider(
                value: continuousSettingsBinding(\.quality),
                in: 0...1,
                step: 0.05,
                onEditingChanged: { editing in
                    if editing { model.beginContinuousEdit() }
                    else { _ = model.commitContinuousEdit() }
                }
            )
                .tint(Palette.accent)
                .accessibilityLabel("GIF quality")

            segmentedLabel("DITHER")
            HStack(spacing: 4) {
                chip("None", selected: model.document.settings.dither == .none) { model.updateSettings { $0.dither = .none } }
                chip("Ordered", selected: model.document.settings.dither == .ordered) { model.updateSettings { $0.dither = .ordered } }
            }

            Button {
                model.updateSettings { $0.preservesTransparency.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(model.document.settings.preservesTransparency ? Palette.accent : Palette.tertiary).frame(width: 7, height: 7)
                    Text("Preserve transparency")
                    Spacer()
                }
                .foregroundStyle(model.document.settings.preservesTransparency ? Palette.accent : Palette.secondary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(model.document.settings.preservesTransparency ? Palette.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(model.document.settings.preservesTransparency ? Palette.accent.opacity(0.35) : Palette.border, lineWidth: 1))
            }
            .buttonStyle(GIFControlButtonStyle())
            .accessibilityLabel("Preserve transparency")
            .accessibilityValue(model.document.settings.preservesTransparency ? "On" : "Off")
            .accessibilityAddTraits(model.document.settings.preservesTransparency ? .isSelected : [])

            HStack {
                sectionLabel("OUTPUT WIDTH")
                Spacer()
                Text(model.document.settings.outputWidth.map { "\($0) px" } ?? "source")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.secondary)
            }
            HStack(spacing: 4) {
                widthChip("640", value: 640)
                widthChip("900", value: 900)
                widthChip("1280", value: 1_280)
                widthChip("Source", value: nil)
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("WRITE PLAN")
                writePlanRow("Frames", "\(ribbonFrames.count) · \(fpsText) · \(formatDuration(totalDurationMicroseconds))")
                writePlanRow("Folded away", ribbonFrames.count == model.document.frames.count ? "none" : "\(model.document.frames.count - ribbonFrames.count) frames", valueColor: ribbonFrames.count == model.document.frames.count ? Palette.tertiary : Palette.success)
                writePlanRow("Loop", loopDescription)
                writePlanRow("Palette / dither", "\(model.document.settings.paletteSize) · \(model.document.settings.dither == .none ? "none" : "ordered")")
                writePlanRow("Alpha", model.document.settings.preservesTransparency ? "preserved" : "flattened", valueColor: model.document.settings.preservesTransparency ? Palette.success : Palette.tertiary)
                writePlanRow("Estimate", ByteCountFormatter.string(fromByteCount: estimatedBytes, countStyle: .file), valueColor: Palette.accent)
            }
            .padding(11)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Palette.border, lineWidth: 1))
        }
    }

    private var captionsSection: some View {
        inspectorSection("Captions") {
            TextField("Caption text", text: $annotationText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Palette.border, lineWidth: 1))
            Button("Add to selected range") {
                model.addTimedAnnotation(annotationText)
                annotationText = ""
            }
            .buttonStyle(GIFSecondaryButtonStyle())
            .disabled(annotationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ForEach(Array(model.document.annotations.enumerated()), id: \.element.id) { index, annotation in
                Button {
                    selectAnnotation(annotation)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(annotation.text).lineLimit(1)
                            Text("Caption · \(index + 1) of \(model.document.annotations.count) · \(formatDuration(annotation.range.startMicroseconds))–\(formatDuration(annotation.range.endMicroseconds))")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(Palette.tertiary)
                        }
                        Spacer()
                    }
                    .padding(7)
                    .background(selectedAnnotationID == annotation.id ? Palette.accent.opacity(0.14) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Caption \(index + 1) of \(model.document.annotations.count), \(annotation.text)")
                .accessibilityValue(selectedAnnotationID == annotation.id ? "Selected" : "Not selected")
                .accessibilityAddTraits(selectedAnnotationID == annotation.id ? .isSelected : [])
            }
            if let annotation = selectedAnnotation {
                TextField("Selected caption", text: $selectedAnnotationText)
                    .textFieldStyle(.roundedBorder)
                    .focused($annotationEditorFocused)
                    .onSubmit { annotationEditorFocused = false }
                    .onChange(of: annotationEditorFocused) { wasFocused, focused in
                        if wasFocused && !focused { commitSelectedAnnotationText() }
                    }
                    .accessibilityIdentifier("gifStudio.captionText")
                HStack {
                    Button("Reveal") { model.revealAnnotation(annotation.id) }
                    Button("Duplicate") {
                        let index = model.document.annotations.firstIndex(where: { $0.id == annotation.id })
                        model.duplicateAnnotation(annotation.id)
                        if let index, model.document.annotations.indices.contains(index + 1) {
                            selectAnnotation(model.document.annotations[index + 1])
                        }
                    }
                    Button("Delete", role: .destructive) {
                        model.deleteAnnotation(annotation.id)
                        selectedAnnotationID = nil
                    }
                }
                .buttonStyle(GIFSecondaryButtonStyle())
                HStack {
                    Button("Move backward") { model.moveAnnotation(annotation.id, by: -1) }
                        .disabled(model.document.annotations.first?.id == annotation.id)
                    Button("Move forward") { model.moveAnnotation(annotation.id, by: 1) }
                        .disabled(model.document.annotations.last?.id == annotation.id)
                }
                .buttonStyle(GIFSecondaryButtonStyle())
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if let progress = model.exportProgress {
                ProgressView(value: progress)
                    .tint(Palette.accent)
                    .frame(width: 180)
                Text(model.statusMessage)
                Button("Cancel") { model.cancelExport() }
                    .buttonStyle(GIFSecondaryButtonStyle())
            } else {
                Text(model.statusMessage)
            }
            Spacer()
            Text("Preview cache: \(model.residentDecodedPreviewCount)/\(GIFStudioDocument.previewCacheCountLimit)")
                .foregroundStyle(Palette.tertiary)
            if let url = model.lastExportURL {
                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(GIFSecondaryButtonStyle())
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(Palette.secondary)
        .padding(.horizontal, 16)
        .frame(minHeight: 34)
        .background(Palette.surface)
    }

    private var loopValue: Int {
        switch model.document.settings.loop {
        case .once: 0
        case .count: 1
        case .forever: 2
        }
    }

    private var loopDescription: String {
        switch model.document.settings.loop {
        case .once: "once"
        case .count(let count): "count(\(count))"
        case .forever: "forever"
        }
    }

    private func setLoopValue(_ value: Int) {
        model.updateSettings { settings in
            settings.loop = value == 0 ? .once : value == 1 ? .count(3) : .forever
        }
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.text)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 1) }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(GIFControlButtonStyle())
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(selected ? Palette.accent : Palette.secondary)
            .padding(.horizontal, 10)
            .frame(minHeight: 29)
            .background(selected ? Palette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(selected ? Palette.accent.opacity(0.35) : Palette.border, lineWidth: 1))
            .accessibilityLabel(chipAccessibilityLabel(title))
            .accessibilityValue(selected ? "Selected" : "Not selected")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func compactIconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 32, height: 32)
        }
        .buttonStyle(GIFSecondaryButtonStyle())
        .accessibilityLabel(label)
        .accessibilityHint("Selects the \(label.lowercased())")
        .contentShape(Rectangle().inset(by: -4))
    }

    private func inspectorButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(GIFSecondaryButtonStyle())
            .frame(maxWidth: .infinity)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .foregroundStyle(Palette.tertiary)
            .tracking(0.4)
    }

    private func segmentedLabel(_ title: String) -> some View {
        sectionLabel(title).padding(.top, 1)
    }

    private func widthChip(_ title: String, value: Int?) -> some View {
        chip(title, selected: model.document.settings.outputWidth == value) {
            model.updateSettings { $0.outputWidth = value }
        }
        .frame(maxWidth: .infinity)
    }

    private func chipAccessibilityLabel(_ title: String) -> String {
        switch title {
        case "∞": return "Loop forever"
        case "3×": return "Loop three times"
        case "0.5×": return "Half speed"
        case "1×": return "Normal speed"
        case "1.5×": return "One and a half times speed"
        case "2×": return "Double speed"
        case "Every 2nd": return "Keep every second frame"
        case "Every 3rd": return "Keep every third frame"
        default: return title
        }
    }

    private func writePlanRow(_ key: String, _ value: String, valueColor: Color = Palette.secondary) -> some View {
        HStack(spacing: 10) {
            Text(key).foregroundStyle(Palette.tertiary)
            Spacer()
            Text(value).foregroundStyle(valueColor).multilineTextAlignment(.trailing)
        }
        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
    }

    private func settingsBinding<T>(_ keyPath: WritableKeyPath<GIFExportSettings, T>) -> Binding<T> {
        Binding(get: { model.document.settings[keyPath: keyPath] }, set: { value in
            model.updateSettings { $0[keyPath: keyPath] = value }
        })
    }

    private func continuousSettingsBinding<T>(_ keyPath: WritableKeyPath<GIFExportSettings, T>) -> Binding<T> {
        Binding(get: { model.document.settings[keyPath: keyPath] }, set: { value in
            model.previewSettings { $0[keyPath: keyPath] = value }
        })
    }

    private func selectRibbonFrame(_ frame: RibbonFrame) {
        guard let sourceIndex = frame.sourceIndices.first else { return }
        model.selectFrame(sourceIndex)
    }

    private func selectFrame(atMicroseconds time: Int64) {
        var cursor: Int64 = 0
        for (index, frame) in model.document.frames.enumerated() {
            if time < cursor + frame.durationMicroseconds {
                model.selectFrame(index)
                return
            }
            cursor += frame.durationMicroseconds
        }
        model.selectFrame(max(0, model.document.frames.count - 1))
    }

    private func adjustSelectedDuration(by milliseconds: Double) {
        let current = Double(selectedFrame?.durationMicroseconds ?? 100_000) / 1_000
        model.setSelectedDuration(milliseconds: max(1, current + milliseconds))
    }

    private func evenOutFrames() {
        guard !model.document.frames.isEmpty else { return }
        let average = Double(model.document.durationMicroseconds) / Double(model.document.frames.count) / 1_000
        let previous = model.selection
        model.setSelection(.init(lowerBound: 0, upperBound: model.document.frames.count))
        model.setSelectedDuration(milliseconds: average)
        model.setSelection(previous)
    }

    private func holdLastFrame() {
        model.selectFrame(max(0, model.document.frames.count - 1))
        model.setSelectedDuration(milliseconds: 1_000)
    }

    private func setSpeed(_ value: Double) {
        speed = value
        model.setSelectedSpeed(value)
    }

    private func toggleCrop() {
        model.updateSettings { settings in
            settings.crop = settings.crop == nil ? .init(x: 0.08, y: 0.1, width: 0.84, height: 0.78) : nil
        }
    }

    private func estimateBytes(width: Int, palette: Int, frameCount: Int64) -> Int64 {
        let sourceWidth = max(1, Int(sourceSize.width))
        let sourceHeight = max(1, Int(sourceSize.height))
        let height = max(1, Int((Double(sourceHeight) * Double(width) / Double(sourceWidth)).rounded()))
        let bits = max(1, Int(ceil(log2(Double(max(2, palette))))))
        let raw = Int64(width * height) * Int64(bits) * max(1, frameCount) / 8
        return max(128, Int64(Double(raw) * (0.25 + model.document.settings.quality * 0.5)) + frameCount * 32)
    }

    private func syncDuration() {
        durationMilliseconds = Double(selectedFrame?.durationMicroseconds ?? 100_000) / 1_000
    }

    private func formatDuration(_ microseconds: Int64) -> String {
        String(format: "%.2fs", Double(microseconds) / 1_000_000)
    }

    private func chooseExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.nameFieldStringValue = "Export.gif"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.export(to: url)
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard EditorShortcutScope.allowsDocumentShortcuts else { return .ignored }
        if press.modifiers.contains(.command), press.characters.lowercased() == "s" {
            DispatchQueue.main.async { model.saveNow() }
            return .handled
        }
        if press.modifiers == .command, press.characters.lowercased() == "z" {
            DispatchQueue.main.async { model.perform(.undo) }
            return .handled
        }
        if press.modifiers == [.command, .shift], press.characters.lowercased() == "z" {
            DispatchQueue.main.async { model.perform(.redo) }
            return .handled
        }
        switch press.key {
        case .space:
            DispatchQueue.main.async { model.togglePlayback() }
            return .handled
        case .leftArrow:
            DispatchQueue.main.async { model.moveSelection(by: -1, extending: press.modifiers.contains(.shift)) }
            return .handled
        case .rightArrow:
            DispatchQueue.main.async { model.moveSelection(by: 1, extending: press.modifiers.contains(.shift)) }
            return .handled
        case .delete:
            DispatchQueue.main.async { model.perform(.delete) }
            return .handled
        default:
            return .ignored
        }
    }

    private func selectAnnotation(_ annotation: GIFTimedAnnotation) {
        commitSelectedAnnotationText()
        selectedAnnotationID = annotation.id
        selectedAnnotationText = annotation.text
        model.revealAnnotation(annotation.id)
    }

    private func commitSelectedAnnotationText() {
        guard let id = selectedAnnotationID else { return }
        model.updateAnnotation(id, text: selectedAnnotationText)
        selectedAnnotationText = model.document.annotations.first(where: { $0.id == id })?.text ?? ""
    }
}

private struct GIFDotGrid: View {
    let spacing: CGFloat = 17

    var body: some View {
        Canvas { context, size in
            for x in stride(from: CGFloat(1), through: size.width, by: spacing) {
                for y in stride(from: CGFloat(1), through: size.height, by: spacing) {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(Color.white.opacity(0.13)))
                }
            }
        }
    }

    func fill(_ color: Color) -> some View {
        ZStack { color; self }
    }
}

private struct GIFPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(red: 18.0 / 255.0, green: 21.0 / 255.0, blue: 28.0 / 255.0))
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .background(Color(red: 1.0, green: 138.0 / 255.0, blue: 107.0 / 255.0).opacity(isEnabled ? (configuration.isPressed ? 0.78 : isHovered ? 0.92 : 1) : 0.35), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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

private struct GIFSecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Color(red: 156.0 / 255.0, green: 161.0 / 255.0, blue: 171.0 / 255.0).opacity(isEnabled ? 1 : 0.5))
            .padding(.horizontal, 10)
            .frame(minHeight: 29)
            .background(Color.white.opacity(isHovered && isEnabled ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(isEnabled ? (isHovered ? 0.18 : 0.1) : 0.05), lineWidth: 1))
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

private struct GIFControlButtonStyle: ButtonStyle {
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
