import AppKit
import AVKit
import SwiftUI

struct VideoStudioPlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player }
}

nonisolated enum OverlayResizeCorner: CaseIterable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight
}

nonisolated enum VideoStudioPreviewGeometry {
    static let minimumOverlaySize = 0.04

    static func aspectFitContentRect(container: CGSize, source: CGSize) -> CGRect {
        guard container.width > 0, container.height > 0, source.width > 0, source.height > 0 else { return .zero }
        let scale = min(container.width / source.width, container.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    static func rect(for bounds: NormalizedOverlayBounds, in contentRect: CGRect) -> CGRect {
        CGRect(x: contentRect.minX + bounds.x * contentRect.width,
               y: contentRect.minY + bounds.y * contentRect.height,
               width: bounds.width * contentRect.width,
               height: bounds.height * contentRect.height)
    }

    static func moved(_ bounds: NormalizedOverlayBounds, translation: CGSize, in contentRect: CGRect) -> NormalizedOverlayBounds {
        guard contentRect.width > 0, contentRect.height > 0 else { return bounds }
        var result = bounds
        result.x = min(max(0, bounds.x + translation.width / contentRect.width), 1 - bounds.width)
        result.y = min(max(0, bounds.y + translation.height / contentRect.height), 1 - bounds.height)
        return result
    }

    static func resized(_ bounds: NormalizedOverlayBounds, corner: OverlayResizeCorner,
                        translation: CGSize, in contentRect: CGRect) -> NormalizedOverlayBounds {
        guard contentRect.width > 0, contentRect.height > 0 else { return bounds }
        let dx = translation.width / contentRect.width
        let dy = translation.height / contentRect.height
        let normalizedWidth = min(max(bounds.width, minimumOverlaySize), 1)
        let normalizedHeight = min(max(bounds.height, minimumOverlaySize), 1)
        var left = min(max(0, bounds.x), 1 - normalizedWidth)
        var top = min(max(0, bounds.y), 1 - normalizedHeight)
        var right = left + normalizedWidth
        var bottom = top + normalizedHeight
        switch corner {
        case .topLeft: left = min(max(0, left + dx), right - minimumOverlaySize); top = min(max(0, top + dy), bottom - minimumOverlaySize)
        case .topRight: right = max(min(1, right + dx), left + minimumOverlaySize); top = min(max(0, top + dy), bottom - minimumOverlaySize)
        case .bottomLeft: left = min(max(0, left + dx), right - minimumOverlaySize); bottom = max(min(1, bottom + dy), top + minimumOverlaySize)
        case .bottomRight: right = max(min(1, right + dx), left + minimumOverlaySize); bottom = max(min(1, bottom + dy), top + minimumOverlaySize)
        }
        return .init(x: left, y: top, width: right - left, height: bottom - top)
    }
}

struct VideoStudioView: View {
    @ObservedObject var document: VideoStudioDocument
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inspectorTab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AeroTokens.Spacing.small) {
                Label("Video Studio", systemImage: "film.stack")
                    .font(AeroTokens.Typography.title())
                Text(document.packageURL.deletingPathExtension().lastPathComponent)
                    .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
                    .lineLimit(1)
                Spacer()
                Button("Save", systemImage: "square.and.arrow.down") { Task { await document.save() } }
                    .buttonStyle(AeroButtonStyle(kind: .secondary, size: .compact))
                    .keyboardShortcut("s", modifiers: .command)
                    .accessibilityIdentifier("videoStudio.save")
                Button("Export…", systemImage: "arrow.up.right.square") { chooseExport() }
                    .buttonStyle(AeroButtonStyle(kind: .secondary, size: .compact))
                    .disabled(document.exportProgress != nil)
                    .accessibilityIdentifier("videoStudio.export")
            }
            .padding(AeroTokens.Spacing.medium)
            Divider()

            HSplitView {
                VStack(spacing: 0) {
                    preview
                    Divider()
                    transport
                    Divider()
                    timeline
                }
                .frame(minWidth: 680)
                inspector.frame(minWidth: 250, idealWidth: 285, maxWidth: 340)
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 980, minHeight: 680)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress { press in handleKey(press) }
        .animation(
            AeroTokens.Motion.resolved(AeroTokens.Motion.standard, reduceMotion: reduceMotion),
            value: document.selectedOverlayID
        )
    }

    private var preview: some View {
        GeometryReader { proxy in
            let contentRect = VideoStudioPreviewGeometry.aspectFitContentRect(container: proxy.size, source: previewSourceSize)
            ZStack(alignment: .topLeading) {
                Color.black
                VideoStudioPlayerView(player: document.player)
                    .scaleEffect(x: 1 / max(document.model.canvas?.crop?.width ?? 1, 0.001),
                                 y: 1 / max(document.model.canvas?.crop?.height ?? 1, 0.001),
                                 anchor: cropAnchor)
                    .frame(width: contentRect.width, height: contentRect.height)
                    .clipped()
                    .position(x: contentRect.midX, y: contentRect.midY)
                    .accessibilityLabel("Video preview")
                    .accessibilityIdentifier("videoStudio.preview")
                ForEach(document.activeOverlays) { overlay in
                    callout(overlay, in: contentRect)
                }
                if document.model.effects.cursorEmphasis > 0, let event = document.activeCursorEvent {
                    Circle().stroke(.yellow, lineWidth: 3)
                        .frame(width: 22 + 18 * document.model.effects.cursorEmphasis,
                               height: 22 + 18 * document.model.effects.cursorEmphasis)
                        .position(x: contentRect.minX + event.x * contentRect.width,
                                  y: contentRect.minY + event.y * contentRect.height)
                        .accessibilityHidden(true)
                }
                ForEach(Array(document.activeClickEvents.enumerated()), id: \.offset) { _, event in
                    if document.model.effects.clickEmphasis > 0 {
                        Circle().stroke(.orange, lineWidth: 5)
                            .frame(width: 36 + 24 * document.model.effects.clickEmphasis,
                                   height: 36 + 24 * document.model.effects.clickEmphasis)
                            .position(x: contentRect.minX + event.x * contentRect.width,
                                      y: contentRect.minY + event.y * contentRect.height)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .frame(minHeight: 360)
    }

    private var previewSourceSize: CGSize {
        if let canvas = document.model.canvas {
            return CGSize(width: canvas.width, height: canvas.height)
        }
        let sourceID = document.model.slices.first?.sourceAssetID ?? document.manifest.primarySourceAssetID
        let pixels = document.manifest.assets.first(where: { $0.id == sourceID })?.metadata.pixelSize
        return CGSize(width: pixels?.width ?? 16, height: pixels?.height ?? 9)
    }

    private func callout(_ overlay: TimedOverlay, in contentRect: CGRect) -> some View {
        let rect = VideoStudioPreviewGeometry.rect(for: overlay.bounds, in: contentRect)
        let color = Color(.sRGB, red: overlay.color.red, green: overlay.color.green,
                          blue: overlay.color.blue, opacity: overlay.color.alpha)
        let moveGesture = DragGesture().onChanged { value in
            guard let origin = document.beginOverlayVisualGesture(overlay.id) else { return }
            let moved = VideoStudioPreviewGeometry.moved(origin, translation: value.translation, in: contentRect)
            document.previewOverlayBounds(moved, for: overlay.id)
        }.onEnded { _ in
            document.commitOverlayVisualGesture(overlay.id)
        }
        return ZStack {
            Text(overlay.payload)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .frame(width: rect.width, height: rect.height)
                .clipped()
                .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 2))
                .contentShape(Rectangle())
                .onTapGesture { document.selectedOverlayID = overlay.id }
                .gesture(moveGesture)
                .accessibilityLabel("Video callout")
                .accessibilityHint("Drag to move")
            if document.selectedOverlayID == overlay.id {
                ForEach(OverlayResizeCorner.allCases, id: \.self) { corner in
                    resizeHandle(corner, overlay: overlay, contentRect: contentRect, rect: rect)
                }
            }
        }
        .frame(width: rect.width + 20, height: rect.height + 20)
        .position(x: rect.midX, y: rect.midY)
        .onDisappear { document.cancelOverlayVisualGesture(overlay.id) }
    }

    private func resizeHandle(_ corner: OverlayResizeCorner, overlay: TimedOverlay,
                              contentRect: CGRect, rect: CGRect) -> some View {
        let x: CGFloat = corner == .topLeft || corner == .bottomLeft ? 10 : rect.width + 10
        let y: CGFloat = corner == .topLeft || corner == .topRight ? 10 : rect.height + 10
        return Circle()
            .fill(AeroTokens.ColorRole.accent)
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
            .frame(width: 12, height: 12)
            .position(x: x, y: y)
            .gesture(DragGesture().onChanged { value in
                guard let origin = document.beginOverlayVisualGesture(overlay.id) else { return }
                document.previewOverlayBounds(VideoStudioPreviewGeometry.resized(origin, corner: corner,
                                                                                  translation: value.translation,
                                                                                  in: contentRect), for: overlay.id)
            }.onEnded { _ in document.commitOverlayVisualGesture(overlay.id) })
            .accessibilityLabel("Resize callout \(String(describing: corner))")
    }

    private var cropAnchor: UnitPoint {
        guard let crop = document.model.canvas?.crop else { return .center }
        return UnitPoint(x: crop.x + crop.width / 2, y: crop.y + crop.height / 2)
    }

    private var transport: some View {
        HStack(spacing: AeroTokens.Spacing.small) {
            Button { document.perform(.playReverse) } label: { Image(systemName: "backward.fill") }
                .help("Play backward (J)").accessibilityLabel("Play backward")
            Button { document.perform(.frameBackward) } label: { Image(systemName: "backward.frame.fill") }
                .help("Previous frame (Left Arrow)").accessibilityLabel("Previous frame")
            Button { document.perform(.togglePlayback) } label: {
                Image(systemName: document.player.rate == 0 ? "play.fill" : "pause.fill")
            }
            .keyboardShortcut(.space, modifiers: []).help("Play or pause (Space)")
            .accessibilityLabel(document.player.rate == 0 ? "Play" : "Pause")
            .accessibilityIdentifier("videoStudio.playPause")
            Button { document.perform(.frameForward) } label: { Image(systemName: "forward.frame.fill") }
                .help("Next frame (Right Arrow)").accessibilityLabel("Next frame")
            Button { document.perform(.playForward) } label: { Image(systemName: "forward.fill") }
                .help("Play forward (L)").accessibilityLabel("Play forward")
            Text(document.timecode)
                .font(AeroTokens.Typography.body().monospacedDigit())
                .textSelection(.enabled)
            Spacer()
            Button("Mark In") { document.perform(.setIn) }.help("Set range start (I)")
            Button("Mark Out") { document.perform(.setOut) }.help("Set range end (O)")
            Button("Split") { document.perform(.split) }.help("Split at playhead")
            Button("Delete Range", role: .destructive) { document.perform(.deleteSelection) }
                .disabled(document.selection.range == nil)
        }
        .buttonStyle(AeroButtonStyle(kind: .quiet, size: .compact))
        .padding(.horizontal, AeroTokens.Spacing.medium)
        .frame(height: 48)
    }

    private var timeline: some View {
        VStack(spacing: AeroTokens.Spacing.small) {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                ZStack(alignment: .leading) {
                    HStack(spacing: 1) {
                        if document.thumbnails.isEmpty {
                            RoundedRectangle(cornerRadius: AeroTokens.Radius.small)
                                .fill(AeroTokens.Fill.hover)
                                .overlay(
                                    Text("Generating thumbnails…")
                                        .font(AeroTokens.Typography.small())
                                        .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
                                )
                        } else {
                            ForEach(Array(document.thumbnails.enumerated()), id: \.offset) { _, image in
                                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).clipped()
                            }
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: AeroTokens.Radius.small))
                    if let range = document.selection.range, document.duration.seconds > 0 {
                        Rectangle().fill(AeroTokens.ColorRole.accent.opacity(0.25))
                            .frame(width: width * range.duration.seconds / document.duration.seconds)
                            .offset(x: width * range.start.seconds / document.duration.seconds)
                            .accessibilityLabel("Selected range")
                    }
                    Rectangle().fill(AeroTokens.ColorRole.accent)
                        .overlay(Rectangle().stroke(AeroTokens.ColorRole.border, lineWidth: AeroTokens.Stroke.hairlineWidth))
                        .frame(width: 2)
                        .offset(x: width * document.playhead.seconds / max(document.duration.seconds, 0.001))
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let fraction = max(0, min(1, value.location.x / width))
                    if let time = try? RationalTime(Int64(document.duration.seconds * fraction * 1_000), 1_000) { document.seek(to: time) }
                })
                .accessibilityLabel("Video timeline")
                .accessibilityValue("\(document.timecode), duration \(PlaybackMath.timecode(document.duration, frameRate: document.frameRate))")
                .accessibilityAction(named: "Next frame") { document.perform(.frameForward) }
                .accessibilityAction(named: "Previous frame") { document.perform(.frameBackward) }
                .accessibilityIdentifier("videoStudio.timeline")
            }.frame(height: 92)
            HStack {
                Text("In: \(mark(document.selection.inPoint))")
                Text("Out: \(mark(document.selection.outPoint))")
                Spacer()
                Button("Trim to Range") { document.trimToSelection() }
                    .buttonStyle(AeroButtonStyle(kind: .secondary, size: .compact))
                    .disabled(document.selection.range == nil)
            }
            .font(AeroTokens.Typography.small())
            .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
        }.padding(AeroTokens.Spacing.medium)
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AeroTokens.Spacing.medium) {
                AeroSegmentedControl(
                    options: [0, 1, 2, 3],
                    selection: $inspectorTab,
                    label: { option in
                        switch option {
                        case 0: "Overlays"
                        case 1: "Canvas"
                        case 2: "Audio"
                        default: "Effects"
                        }
                    }
                )
                .accessibilityLabel("Inspector")
                if inspectorTab == 0 { overlayInspector }
                else if inspectorTab == 1 { canvasInspector }
                else if inspectorTab == 2 { audioInspector }
                else { effectsInspector }
            }
            .padding(AeroTokens.Spacing.medium)
        }
    }

    private var overlayInspector: some View {
        AeroPanel("Overlays", symbol: "text.bubble") {
            Button("Add Timed Callout", systemImage: "plus.bubble") { document.addCallout() }
                .buttonStyle(AeroButtonStyle(kind: .secondary, size: .compact))
                .accessibilityIdentifier("videoStudio.addCallout")
            ForEach(document.model.overlays) { overlay in
                Button { document.selectedOverlayID = overlay.id } label: {
                    VStack(alignment: .leading) {
                        Text(overlay.payload).lineLimit(1)
                        Text("\(mark(overlay.range.start)) – \(mark(overlay.range.end))")
                            .font(AeroTokens.Typography.small())
                            .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).padding(AeroTokens.Spacing.small)
                    .background(document.selectedOverlayID == overlay.id ? AeroTokens.Fill.selected : Color.clear,
                                in: RoundedRectangle(cornerRadius: AeroTokens.Radius.small))
                    .overlay {
                        if document.selectedOverlayID == overlay.id {
                            RoundedRectangle(cornerRadius: AeroTokens.Radius.small)
                                .strokeBorder(AeroTokens.Stroke.accentSelected, lineWidth: AeroTokens.Stroke.accentSelectedWidth)
                        }
                    }
            }
            if let overlay = document.model.overlays.first(where: { $0.id == document.selectedOverlayID }) {
                Divider()
                TextField("Callout text", text: Binding(get: { overlay.payload }, set: {
                    document.updateSelectedOverlay(payload: $0, start: overlay.range.start.seconds, duration: overlay.range.duration.seconds)
                }))
                .aeroFieldChrome()
                AeroInspectorRow("Start") {
                    TextField("Start", value: Binding(get: { overlay.range.start.seconds }, set: {
                        document.updateSelectedOverlay(payload: overlay.payload, start: $0, duration: overlay.range.duration.seconds)
                    }), format: .number.precision(.fractionLength(2)))
                    .frame(width: 80)
                    .aeroFieldChrome()
                }
                AeroInspectorRow("Duration") {
                    TextField("Duration", value: Binding(get: { overlay.range.duration.seconds }, set: {
                        document.updateSelectedOverlay(payload: overlay.payload, start: overlay.range.start.seconds, duration: $0)
                    }), format: .number.precision(.fractionLength(2)))
                    .frame(width: 80)
                    .aeroFieldChrome()
                }
                Group {
                    overlayNumberField("X", overlay: overlay, keyPath: \.x)
                    overlayNumberField("Y", overlay: overlay, keyPath: \.y)
                    overlayNumberField("Width", overlay: overlay, keyPath: \.width)
                    overlayNumberField("Height", overlay: overlay, keyPath: \.height)
                    AeroInspectorRow("Color") {
                        ColorPicker("Callout color", selection: Binding(
                            get: { Color(.sRGB, red: overlay.color.red, green: overlay.color.green,
                                         blue: overlay.color.blue, opacity: overlay.color.alpha) },
                            set: { value in
                                guard let color = NSColor(value).usingColorSpace(.sRGB) else { return }
                                let components = [color.redComponent, color.greenComponent,
                                                  color.blueComponent, color.alphaComponent]
                                guard components.allSatisfy(\.isFinite) else { return }
                                let bounded = components.map { min(max(Double($0), 0), 1) }
                                document.updateSelectedOverlayVisual(color: .init(
                                    red: bounded[0], green: bounded[1], blue: bounded[2], alpha: bounded[3]
                                ))
                            }
                        ), supportsOpacity: true).labelsHidden().accessibilityLabel("Callout color")
                    }
                }
            }
        }
    }

    private func overlayNumberField(_ label: String, overlay: TimedOverlay,
                                    keyPath: WritableKeyPath<NormalizedOverlayBounds, Double>) -> some View {
        AeroInspectorRow(label) {
            TextField(label, value: Binding(get: { overlay.bounds[keyPath: keyPath] }, set: { newValue in
                var bounds = overlay.bounds
                bounds[keyPath: keyPath] = newValue
                document.updateSelectedOverlayVisual(bounds: bounds)
            }), format: .number.precision(.fractionLength(3)))
            .frame(width: 80).aeroFieldChrome().accessibilityLabel("Callout \(label)")
        }
    }

    private var canvasInspector: some View {
        AeroPanel("Crop", symbol: "crop") {
            HStack(spacing: AeroTokens.Spacing.small) {
                Button("Reset to Source") { document.setCrop(nil) }
                Button("Inset 5%") { document.setCrop(.init(x: 0.05, y: 0.05, width: 0.9, height: 0.9)) }
            }
            .buttonStyle(AeroButtonStyle(kind: .secondary, size: .compact))
            Text("Crop is non-destructive and applies to preview/export state.")
                .font(AeroTokens.Typography.small())
                .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
        }
    }

    private var audioInspector: some View {
        AeroPanel("Audio", symbol: "speaker.wave.2") {
            if !document.waveform.isEmpty {
                AudioWaveformView(samples: document.waveform)
                    .frame(height: 48)
                    .accessibilityLabel("Audio waveform")
            }
            AeroInspectorRow("Mute") {
                AeroCompactToggle(title: "", isOn: Binding(get: { document.model.audio.isMuted }, set: { document.setAudio(muted: $0) }))
                    .accessibilityLabel("Mute")
            }
            AeroInspectorRow("Gain") {
                Slider(value: Binding(get: { Double(document.model.audio.gain) }, set: { document.setAudio(gain: Float($0)) }), in: 0...2)
                    .tint(AeroTokens.ColorRole.accent)
                    .frame(width: 120)
                    .accessibilityLabel("Gain")
            }
            Text(String(format: "%.0f%%", document.model.audio.gain * 100))
                .font(AeroTokens.Typography.small())
                .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
            AeroInspectorRow("Fade in") {
                Slider(value: Binding(get: { document.model.audio.fadeIn.seconds }, set: { document.setAudio(fadeIn: $0) }), in: 0...min(5, max(0, document.duration.seconds / 2)))
                    .tint(AeroTokens.ColorRole.accent)
                    .frame(width: 120)
                    .accessibilityLabel("Fade in")
            }
            AeroInspectorRow("Fade out") {
                Slider(value: Binding(get: { document.model.audio.fadeOut.seconds }, set: { document.setAudio(fadeOut: $0) }), in: 0...min(5, max(0, document.duration.seconds / 2)))
                    .tint(AeroTokens.ColorRole.accent)
                    .frame(width: 120)
                    .accessibilityLabel("Fade out")
            }
        }
    }

    private var effectsInspector: some View {
        AeroPanel("Recorded metadata", symbol: "cursorarrow.motionlines") {
            AeroInspectorRow("Cursor samples") {
                Text("\(document.model.effects.events.filter { $0.kind == .cursor }.count)")
                    .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
            }
            AeroInspectorRow("Click events") {
                Text("\(document.model.effects.events.filter { $0.kind == .click }.count)")
                    .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
            }
            AeroInspectorRow("Cursor emphasis") {
                Slider(value: Binding(get: { document.model.effects.cursorEmphasis },
                                      set: { document.setEffects(cursorEmphasis: $0) }), in: 0...2)
                    .tint(AeroTokens.ColorRole.accent)
                    .frame(width: 120)
                    .accessibilityLabel("Cursor emphasis")
            }
            AeroInspectorRow("Click emphasis") {
                Slider(value: Binding(get: { document.model.effects.clickEmphasis },
                                      set: { document.setEffects(clickEmphasis: $0) }), in: 0...2)
                    .tint(AeroTokens.ColorRole.accent)
                    .frame(width: 120)
                    .accessibilityLabel("Click emphasis")
            }
            Text("Webcam presentation is baked into recordings when a separate camera stream is unavailable.")
                .font(AeroTokens.Typography.small())
                .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
        }
    }

    private var statusBar: some View {
        HStack {
            if let progress = document.exportProgress {
                AeroProgress(label: document.statusMessage, value: progress)
                    .frame(width: 220)
                    .accessibilityLabel("Export progress")
                Button("Cancel") { document.cancelExport() }
                    .buttonStyle(AeroButtonStyle(kind: .secondary, size: .compact))
            } else {
                Text(document.statusMessage).lineLimit(1)
            }
            Spacer()
            if let url = document.lastExportURL {
                Button("Reveal Export") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(AeroButtonStyle(kind: .secondary, size: .compact))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, AeroTokens.Spacing.medium)
        .frame(minHeight: 34)
    }

    private func chooseExport() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.mpeg4Movie]; panel.nameFieldStringValue = "Aeroshot Export.mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        document.export(to: url)
    }

    private func mark(_ time: RationalTime?) -> String { time.map { PlaybackMath.timecode($0, frameRate: document.frameRate) } ?? "—" }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isEmpty else {
            if press.modifiers == .command, press.characters.lowercased() == "z" { document.perform(.undo); return .handled }
            if press.modifiers == [.command, .shift], press.characters.lowercased() == "z" { document.perform(.redo); return .handled }
            return .ignored
        }
        switch press.key {
        case .space: document.perform(.togglePlayback)
        case .leftArrow: document.perform(.frameBackward)
        case .rightArrow: document.perform(.frameForward)
        case .delete: document.perform(.deleteSelection)
        default:
            switch press.characters.lowercased() {
            case "j": document.perform(.playReverse)
            case "k": document.perform(.pause)
            case "l": document.perform(.playForward)
            case "i": document.perform(.setIn)
            case "o": document.perform(.setOut)
            default: return .ignored
            }
        }
        return .handled
    }
}

private struct AudioWaveformView: View {
    let samples: [Float]

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let midpoint = proxy.size.height / 2
                let step = proxy.size.width / CGFloat(max(samples.count - 1, 1))
                for (index, sample) in samples.enumerated() {
                    let height = max(1, CGFloat(sample) * midpoint)
                    let x = CGFloat(index) * step
                    path.move(to: CGPoint(x: x, y: midpoint - height))
                    path.addLine(to: CGPoint(x: x, y: midpoint + height))
                }
            }.stroke(.secondary, lineWidth: 1)
        }
    }
}
