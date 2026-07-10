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

struct VideoStudioView: View {
    @ObservedObject var document: VideoStudioDocument
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inspectorTab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("Video Studio", systemImage: "film.stack")
                    .font(.headline)
                Text(document.packageURL.deletingPathExtension().lastPathComponent).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("Save", systemImage: "square.and.arrow.down") { Task { await document.save() } }
                    .keyboardShortcut("s", modifiers: .command)
                    .accessibilityIdentifier("videoStudio.save")
                Button("Export…", systemImage: "arrow.up.right.square") { chooseExport() }
                    .disabled(document.exportProgress != nil)
                    .accessibilityIdentifier("videoStudio.export")
            }
            .padding(12)
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: document.selectedOverlayID)
    }

    private var preview: some View {
        ZStack {
            Color.black
            VideoStudioPlayerView(player: document.player)
                .scaleEffect(x: 1 / max(document.model.canvas?.crop?.width ?? 1, 0.001),
                             y: 1 / max(document.model.canvas?.crop?.height ?? 1, 0.001),
                             anchor: cropAnchor)
                .clipped()
                .accessibilityLabel("Video preview")
                .accessibilityIdentifier("videoStudio.preview")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(document.activeOverlays) { overlay in
                    Text(overlay.payload)
                        .font(.title3.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.yellow, lineWidth: 2))
                }
                Spacer()
            }
            .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            GeometryReader { proxy in
                if document.model.effects.cursorEmphasis > 0, let event = document.activeCursorEvent {
                    Circle().stroke(.yellow, lineWidth: 3)
                        .frame(width: 22 + 18 * document.model.effects.cursorEmphasis,
                               height: 22 + 18 * document.model.effects.cursorEmphasis)
                        .position(x: event.x * proxy.size.width, y: event.y * proxy.size.height)
                        .accessibilityHidden(true)
                }
                ForEach(Array(document.activeClickEvents.enumerated()), id: \.offset) { _, event in
                    if document.model.effects.clickEmphasis > 0 {
                        Circle().stroke(.orange, lineWidth: 5)
                            .frame(width: 36 + 24 * document.model.effects.clickEmphasis,
                                   height: 36 + 24 * document.model.effects.clickEmphasis)
                            .position(x: event.x * proxy.size.width, y: event.y * proxy.size.height)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .frame(minHeight: 360)
    }

    private var cropAnchor: UnitPoint {
        guard let crop = document.model.canvas?.crop else { return .center }
        return UnitPoint(x: crop.x + crop.width / 2, y: crop.y + crop.height / 2)
    }

    private var transport: some View {
        HStack(spacing: 8) {
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
            Text(document.timecode).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            Spacer()
            Button("Mark In") { document.perform(.setIn) }.help("Set range start (I)")
            Button("Mark Out") { document.perform(.setOut) }.help("Set range end (O)")
            Button("Split") { document.perform(.split) }.help("Split at playhead")
            Button("Delete Range", role: .destructive) { document.perform(.deleteSelection) }
                .disabled(document.selection.range == nil)
        }
        .buttonStyle(.borderless).padding(.horizontal, 14).frame(height: 48)
    }

    private var timeline: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                ZStack(alignment: .leading) {
                    HStack(spacing: 1) {
                        if document.thumbnails.isEmpty {
                            RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.2))
                                .overlay(Text("Generating thumbnails…").foregroundStyle(.secondary))
                        } else {
                            ForEach(Array(document.thumbnails.enumerated()), id: \.offset) { _, image in
                                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).clipped()
                            }
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 6))
                    if let range = document.selection.range, document.duration.seconds > 0 {
                        Rectangle().fill(.accent.opacity(0.25))
                            .frame(width: width * range.duration.seconds / document.duration.seconds)
                            .offset(x: width * range.start.seconds / document.duration.seconds)
                            .accessibilityLabel("Selected range")
                    }
                    Rectangle().fill(.white).shadow(color: .black, radius: 1).frame(width: 2)
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
                Button("Trim to Range") { document.trimToSelection() }.disabled(document.selection.range == nil)
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(12)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Inspector", selection: $inspectorTab) {
                Text("Overlays").tag(0); Text("Canvas").tag(1); Text("Audio").tag(2); Text("Effects").tag(3)
            }.pickerStyle(.segmented).labelsHidden()
            if inspectorTab == 0 { overlayInspector }
            else if inspectorTab == 1 { canvasInspector }
            else if inspectorTab == 2 { audioInspector }
            else { effectsInspector }
            Spacer()
        }.padding(14).background(.quaternary.opacity(0.25))
    }

    private var overlayInspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("Add Timed Callout", systemImage: "plus.bubble") { document.addCallout() }
                .accessibilityIdentifier("videoStudio.addCallout")
            ForEach(document.model.overlays) { overlay in
                Button { document.selectedOverlayID = overlay.id } label: {
                    VStack(alignment: .leading) {
                        Text(overlay.payload).lineLimit(1)
                        Text("\(mark(overlay.range.start)) – \(mark(overlay.range.end))").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).padding(8)
                    .background(document.selectedOverlayID == overlay.id ? Color.accentColor.opacity(0.2) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6))
            }
            if let overlay = document.model.overlays.first(where: { $0.id == document.selectedOverlayID }) {
                Divider()
                TextField("Callout text", text: Binding(get: { overlay.payload }, set: {
                    document.updateSelectedOverlay(payload: $0, start: overlay.range.start.seconds, duration: overlay.range.duration.seconds)
                }))
                LabeledContent("Start") { TextField("Start", value: Binding(get: { overlay.range.start.seconds }, set: {
                    document.updateSelectedOverlay(payload: overlay.payload, start: $0, duration: overlay.range.duration.seconds)
                }), format: .number.precision(.fractionLength(2))).frame(width: 80) }
                LabeledContent("Duration") { TextField("Duration", value: Binding(get: { overlay.range.duration.seconds }, set: {
                    document.updateSelectedOverlay(payload: overlay.payload, start: overlay.range.start.seconds, duration: $0)
                }), format: .number.precision(.fractionLength(2))).frame(width: 80) }
            }
        }
    }

    private var canvasInspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Crop").font(.headline)
            Button("Reset to Source") { document.setCrop(nil) }
            Button("Inset 5%") { document.setCrop(.init(x: 0.05, y: 0.05, width: 0.9, height: 0.9)) }
            Text("Crop is non-destructive and applies to preview/export state.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var audioInspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !document.waveform.isEmpty {
                AudioWaveformView(samples: document.waveform)
                    .frame(height: 48)
                    .accessibilityLabel("Audio waveform")
            }
            Toggle("Mute", isOn: Binding(get: { document.model.audio.isMuted }, set: { document.setAudio(muted: $0) }))
            LabeledContent("Gain") {
                Slider(value: Binding(get: { Double(document.model.audio.gain) }, set: { document.setAudio(gain: Float($0)) }), in: 0...2)
            }
            Text(String(format: "%.0f%%", document.model.audio.gain * 100)).font(.caption).foregroundStyle(.secondary)
            LabeledContent("Fade in") {
                Slider(value: Binding(get: { document.model.audio.fadeIn.seconds }, set: { document.setAudio(fadeIn: $0) }), in: 0...min(5, max(0, document.duration.seconds / 2)))
            }
            LabeledContent("Fade out") {
                Slider(value: Binding(get: { document.model.audio.fadeOut.seconds }, set: { document.setAudio(fadeOut: $0) }), in: 0...min(5, max(0, document.duration.seconds / 2)))
            }
        }
    }

    private var effectsInspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recorded metadata").font(.headline)
            LabeledContent("Cursor samples", value: "\(document.model.effects.events.filter { $0.kind == .cursor }.count)")
            LabeledContent("Click events", value: "\(document.model.effects.events.filter { $0.kind == .click }.count)")
            LabeledContent("Cursor emphasis") {
                Slider(value: Binding(get: { document.model.effects.cursorEmphasis },
                                      set: { document.setEffects(cursorEmphasis: $0) }), in: 0...2)
            }
            LabeledContent("Click emphasis") {
                Slider(value: Binding(get: { document.model.effects.clickEmphasis },
                                      set: { document.setEffects(clickEmphasis: $0) }), in: 0...2)
            }
            Text("Webcam presentation is baked into recordings when a separate camera stream is unavailable.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var statusBar: some View {
        HStack {
            if let progress = document.exportProgress {
                ProgressView(value: progress).frame(width: 160).accessibilityLabel("Export progress")
                Button("Cancel") { document.cancelExport() }
            }
            Text(document.statusMessage).lineLimit(1)
            Spacer()
            if let url = document.lastExportURL { Button("Reveal Export") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).frame(height: 34)
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
