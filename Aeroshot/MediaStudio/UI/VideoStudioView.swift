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
        case .topLeft:
            left = min(max(0, left + dx), right - minimumOverlaySize)
            top = min(max(0, top + dy), bottom - minimumOverlaySize)
        case .topRight:
            right = max(min(1, right + dx), left + minimumOverlaySize)
            top = min(max(0, top + dy), bottom - minimumOverlaySize)
        case .bottomLeft:
            left = min(max(0, left + dx), right - minimumOverlaySize)
            bottom = max(min(1, bottom + dy), top + minimumOverlaySize)
        case .bottomRight:
            right = max(min(1, right + dx), left + minimumOverlaySize)
            bottom = max(min(1, bottom + dy), top + minimumOverlaySize)
        }
        return .init(x: left, y: top, width: right - left, height: bottom - top)
    }
}

private enum VideoStudioPalette {
    static let background = Color(red: 0.043, green: 0.047, blue: 0.059)
    static let surface = Color(red: 0.075, green: 0.082, blue: 0.098)
    static let surfaceRaised = Color(red: 0.098, green: 0.110, blue: 0.133)
    static let surfaceDeep = Color(red: 0.055, green: 0.063, blue: 0.078)
    static let border = Color.white.opacity(0.09)
    static let borderStrong = Color.white.opacity(0.17)
    static let text = Color(red: 0.929, green: 0.933, blue: 0.945)
    static let secondary = Color(red: 0.612, green: 0.631, blue: 0.671)
    static let tertiary = Color(red: 0.400, green: 0.420, blue: 0.459)
    static let accent = Color(red: 1.0, green: 0.541, blue: 0.420)
    static let warning = Color(red: 1.0, green: 0.706, blue: 0.329)
    static let blue = Color(red: 0.298, green: 0.553, blue: 1.0)
    static let success = Color(red: 0.373, green: 0.827, blue: 0.627)
    static let danger = Color(red: 0.898, green: 0.282, blue: 0.302)
    static let mono = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let label = Font.system(size: 10, weight: .semibold, design: .monospaced)
}

private enum VideoStudioInspectorMode: String, CaseIterable, Identifiable {
    case effects, audio, slice, overlay, deadAir, reframe, webcam, cursorPunch, sfx

    var id: Self { self }

    var title: String {
        switch self {
        case .effects: "Effects"
        case .audio: "Audio"
        case .slice: "Slice"
        case .overlay: "Overlay"
        case .deadAir: "Dead air"
        case .reframe: "Reframe"
        case .webcam: "Webcam"
        case .cursorPunch: "Cursor / punch"
        case .sfx: "Click SFX"
        }
    }

    var symbol: String {
        switch self {
        case .effects: "wand.and.stars"
        case .audio: "waveform"
        case .slice: "scissors"
        case .overlay: "text.bubble"
        case .deadAir: "pause.circle"
        case .reframe: "rectangle.arrowtriangle.2.inward"
        case .webcam: "web.camera"
        case .cursorPunch: "cursorarrow.motionlines"
        case .sfx: "speaker.wave.2"
        }
    }
}

private struct VideoStudioGap: Identifiable, Hashable {
    let id: Int
    let range: RationalTimeRange

    var duration: Double { range.duration.seconds }
}

private struct VideoStudioChapter: Identifiable, Hashable {
    let id: Int
    let time: RationalTime
    let label: String
}

struct VideoStudioView: View {
    @ObservedObject var document: VideoStudioDocument
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var inspectorMode: VideoStudioInspectorMode = .effects
    @State private var codec = "h264"
    @State private var selectedSliceID: UUID?
    @State private var idleThreshold = 1.5
    @State private var chaptersVisible = true
    @State private var playbackSpeed = 1.0
    @State private var toast: String?

    private let reframeOptions = ["16:9", "1:1", "9:16", "4:5"]
    private let clickSoundOptions = ["Off", "snug_click", "pebble_tap", "latch_tap", "wisp_puff"]
    private let webcamCorners = ["TL", "TR", "BL", "BR"]

    private var reframe: String { document.model.effects.reframeAspectRatio ?? "16:9" }
    private var webcamOn: Bool { document.model.effects.webcam.isEnabled && document.hasWebcamMedia }
    private var webcamCorner: String { document.model.effects.webcam.corner }
    private var webcamShape: String { document.model.effects.webcam.isCircular ? "Circle" : "Rounded" }
    private var clickSound: String { document.model.effects.clickSound }
    private var punchedClicks: [Int64] { document.model.effects.punchInClickTimes }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            HSplitView {
                VStack(spacing: 0) {
                    preview
                    transport
                    timeline
                }
                .frame(minWidth: 760, maxWidth: .infinity)
                inspector
                    .frame(minWidth: 310, idealWidth: 334, maxWidth: 380)
            }
            statusBar
        }
        .background(VideoStudioPalette.background)
        .foregroundStyle(VideoStudioPalette.text)
        .frame(minWidth: 1120, minHeight: 760)
        .focusable()
        .onKeyPress { press in handleKey(press) }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VideoStudioPalette.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(VideoStudioPalette.surfaceDeep.opacity(0.98), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(VideoStudioPalette.borderStrong))
                    .shadow(color: .black.opacity(0.45), radius: 16, y: 7)
                    .padding(.bottom, 44)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(AeroTokens.Motion.resolved(AeroTokens.Motion.standard, reduceMotion: reduceMotion), value: toast)
    }

    private var titleBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Circle().fill(Color(red: 1, green: 0.373, blue: 0.341)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 0.996, green: 0.737, blue: 0.180)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 0.157, green: 0.784, blue: 0.251)).frame(width: 12, height: 12)
            }
            .accessibilityHidden(true)
            Image(systemName: "sparkles").foregroundStyle(VideoStudioPalette.accent).font(.system(size: 15, weight: .bold))
            VStack(alignment: .leading, spacing: 3) {
                Text(document.packageURL.deletingPathExtension().lastPathComponent + ".mp4")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(documentMeta)
                    .font(VideoStudioPalette.mono)
                    .foregroundStyle(VideoStudioPalette.tertiary)
                    .lineLimit(1)
            }
            Divider().frame(height: 26).overlay(VideoStudioPalette.border)
            codecTabs
            Text(codecMeta)
                .font(VideoStudioPalette.mono)
                .foregroundStyle(VideoStudioPalette.tertiary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                collapseIdleGaps()
            } label: {
                Label(idleGaps.isEmpty ? "Collapse idle gaps" : "Collapse \(idleGaps.count) idle gaps · \(formatSeconds(idleGapDuration))",
                      systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(VideoStudioChromeButtonStyle(tint: VideoStudioPalette.warning, filled: false))
            .disabled(idleGaps.isEmpty)
            .accessibilityIdentifier("videoStudio.collapseIdleGaps")
            VStack(alignment: .trailing, spacing: 2) {
                Text("EST").font(VideoStudioPalette.label).foregroundStyle(VideoStudioPalette.tertiary)
                Text(estimatedSize).font(VideoStudioPalette.mono)
            }
            Button("Save", systemImage: "square.and.arrow.down") {
                Task { await document.save() }
            }
            .buttonStyle(VideoStudioChromeButtonStyle(tint: VideoStudioPalette.secondary, filled: false))
            .keyboardShortcut("s", modifiers: .command)
            .accessibilityIdentifier("videoStudio.save")
            Button {
                chooseExport()
            } label: {
                Text("Export")
                Text("⌘E").font(VideoStudioPalette.label).opacity(0.55)
            }
            .buttonStyle(VideoStudioChromeButtonStyle(tint: VideoStudioPalette.accent, filled: true))
            .disabled(document.exportProgress != nil)
            .keyboardShortcut("e", modifiers: .command)
            .accessibilityIdentifier("videoStudio.export")
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(VideoStudioPalette.surfaceDeep)
        .overlay(alignment: .bottom) { Rectangle().fill(VideoStudioPalette.border).frame(height: 1) }
    }

    private var codecTabs: some View {
        HStack(spacing: 3) {
            ForEach([("h264", "H.264"), ("hevc", "HEVC")], id: \.0) { item in
                Button(item.1) {
                    codec = item.0
                }
                .buttonStyle(VideoStudioTabButtonStyle(isSelected: codec == item.0))
                .accessibilityAddTraits(codec == item.0 ? .isSelected : [])
            }
        }
        .padding(3)
        .background(VideoStudioPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(VideoStudioPalette.border))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Export codec")
    }

    private var preview: some View {
        GeometryReader { proxy in
            let available = CGRect(origin: .zero, size: proxy.size).insetBy(dx: 22, dy: 22)
            let stageRect = VideoStudioPreviewGeometry.aspectFitContentRect(container: available.size, source: stageCanvasSize)
                .offsetBy(dx: available.minX, dy: available.minY)
            let contentRect = CGRect(origin: .zero, size: stageRect.size)
            let layout = cropLayout(outputRect: CGRect(origin: .zero, size: stageRect.size), punchIn: document.activePunchInEvent)
            ZStack {
                VideoStudioGrid()
                ZStack(alignment: .topLeading) {
                    Color.black
                    if let layout {
                        VideoStudioPlayerView(player: document.player)
                            .frame(width: layout.transformedSourceRect.width, height: layout.transformedSourceRect.height)
                            .position(x: layout.transformedSourceRect.midX - layout.fittedCropRect.minX,
                                      y: layout.transformedSourceRect.midY - layout.fittedCropRect.minY)
                            .frame(width: layout.fittedCropRect.width, height: layout.fittedCropRect.height)
                            .clipped()
                    }
                    if document.model.canvas?.crop != nil {
                        Rectangle()
                            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(18)
                            .overlay(alignment: .topLeading) {
                                Text("CanvasState.crop")
                                    .font(VideoStudioPalette.label)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .padding(.top, 3)
                                    .padding(.leading, 6)
                            }
                    }
                    ForEach(document.activeOverlays) { overlay in
                        callout(overlay, in: contentRect)
                    }
                    if let event = document.activeCursorEvent,
                       let point = layout?.outputPoint(forSourceNormalized: CGPoint(x: event.x, y: event.y)) {
                        Circle()
                            .fill(.white)
                            .frame(width: 9 + document.model.effects.cursorEmphasis * 5,
                                   height: 9 + document.model.effects.cursorEmphasis * 5)
                            .overlay(Circle().stroke(VideoStudioPalette.accent.opacity(0.7), lineWidth: 2))
                            .position(point)
                            .shadow(color: .white.opacity(0.3), radius: 4)
                            .accessibilityHidden(true)
                    }
                    ForEach(Array(document.activeClickEvents.enumerated()), id: \.offset) { _, event in
                        if document.model.effects.clickEmphasis > 0,
                           let point = layout?.outputPoint(forSourceNormalized: CGPoint(x: event.x, y: event.y)) {
                            Circle()
                                .stroke(VideoStudioPalette.accent, lineWidth: 2)
                                .frame(width: 28, height: 28)
                                .position(point)
                                .accessibilityHidden(true)
                        }
                    }
                    if webcamOn {
                        webcamPreview
                    }
                    HStack(spacing: 7) {
                        Text(document.timecode).foregroundStyle(VideoStudioPalette.accent)
                        Text(selectedSliceLabel).foregroundStyle(VideoStudioPalette.tertiary)
                    }
                    .font(VideoStudioPalette.mono)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(VideoStudioPalette.surfaceDeep.opacity(0.90), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(VideoStudioPalette.borderStrong))
                    .padding(10)
                }
                .frame(width: stageRect.width, height: stageRect.height)
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(VideoStudioPalette.borderStrong))
                .shadow(color: .black.opacity(0.55), radius: 28, y: 14)
                .position(x: stageRect.midX, y: stageRect.midY)
                if reframe != "16:9" {
                    Text("REFRAME FOLLOWS CURSOR")
                        .font(VideoStudioPalette.label)
                        .foregroundStyle(.white.opacity(0.75))
                        .position(x: stageRect.minX + 12, y: stageRect.minY + 18)
                }
            }
        }
        .frame(minHeight: 390)
        .background(VideoStudioPalette.surfaceDeep)
        .overlay(alignment: .bottom) { Rectangle().fill(VideoStudioPalette.border).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Video preview")
        .accessibilityIdentifier("videoStudio.preview")
    }

    private var transport: some View {
        HStack(spacing: 10) {
            transportButton("backward.fill", label: "Play backward") { document.perform(.playReverse) }
            transportButton("backward.frame.fill", label: "Previous frame") { document.perform(.frameBackward) }
            Button {
                document.perform(.togglePlayback)
            } label: {
                Image(systemName: document.player.rate == 0 ? "play.fill" : "pause.fill")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(VideoStudioPlayButtonStyle())
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(document.player.rate == 0 ? "Play" : "Pause")
            .accessibilityIdentifier("videoStudio.playPause")
            transportButton("forward.frame.fill", label: "Next frame") { document.perform(.frameForward) }
            transportButton("forward.fill", label: "Play forward") { document.perform(.playForward) }
            Text(document.timecode)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(VideoStudioPalette.secondary)
                .frame(width: 130, alignment: .leading)
                .textSelection(.enabled)
            Button("Split  ⌥S") {
                document.perform(.split)
                flash("Split at \(document.timecode)")
            }
            .buttonStyle(VideoStudioChromeButtonStyle(tint: VideoStudioPalette.secondary, filled: false))
            Button("Set In") {
                document.perform(.setIn)
                flash("In point set at \(document.timecode)")
            }
            .buttonStyle(VideoStudioChromeButtonStyle(tint: document.selection.inPoint == nil ? VideoStudioPalette.secondary : VideoStudioPalette.accent, filled: false))
            .accessibilityLabel("Set In point at current time")
            Button("Set Out") {
                document.perform(.setOut)
                flash("Out point set at \(document.timecode)")
            }
            .buttonStyle(VideoStudioChromeButtonStyle(tint: document.selection.outPoint == nil ? VideoStudioPalette.secondary : VideoStudioPalette.accent, filled: false))
            .accessibilityLabel("Set Out point at current time")
            Button("Trim to range") {
                document.trimToSelection()
                flash("Trimmed to In / Out range")
            }
            .buttonStyle(VideoStudioChromeButtonStyle(tint: VideoStudioPalette.accent, filled: false))
            .disabled(document.selection.range == nil)
            .accessibilityHint("Keeps the selected range and removes everything outside it")
            Button("Ripple delete") {
                if document.deleteSelection() {
                    flash("Ripple deleted selected range")
                } else if !document.canRippleDeleteSelection, document.selection.range != nil {
                    flash("Ripple delete is limited to the first slice; use Trim to range across clips")
                }
            }
            .buttonStyle(VideoStudioChromeButtonStyle(tint: VideoStudioPalette.secondary, filled: false))
            .disabled(!document.canRippleDeleteSelection)
            Divider().frame(height: 22).overlay(VideoStudioPalette.border)
            Button("+ Callout") {
                document.addCallout()
                inspectorMode = .overlay
            }
            .buttonStyle(VideoStudioChromeButtonStyle(tint: VideoStudioPalette.secondary, filled: false))
            Button(document.model.canvas?.crop == nil ? "Crop" : "Crop armed") {
                inspectorMode = .reframe
                document.setCrop(document.model.canvas?.crop == nil ? .init(x: 0.06, y: 0.08, width: 0.88, height: 0.82) : nil)
            }
            .buttonStyle(VideoStudioChromeButtonStyle(tint: document.model.canvas?.crop == nil ? VideoStudioPalette.secondary : VideoStudioPalette.accent, filled: false))
            Spacer(minLength: 8)
            Text("Clicks and cursor moves were recorded alongside the frames — editable, not baked in.")
                .font(.system(size: 10.5))
                .foregroundStyle(VideoStudioPalette.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(VideoStudioPalette.surfaceDeep)
        .overlay(alignment: .bottom) { Rectangle().fill(VideoStudioPalette.border).frame(height: 1) }
    }

    private func transportButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 24, height: 24)
        }
        .buttonStyle(VideoStudioQuietButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }

    private var timeline: some View {
        VStack(spacing: 5) {
            timelineTrack(label: "VIDEO", height: 52) { width in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8).fill(VideoStudioPalette.surfaceRaised)
                    timelineThumbnails(width: width, height: 50)
                    timelineSeekOverlay(width: width)
                    ForEach(Array(document.model.slices.enumerated()), id: \.element.id) { index, slice in
                        let start = sliceStart(index)
                        let left = CGFloat(start / max(document.duration.seconds, 0.001)) * width
                        let segmentWidth = CGFloat(slice.sourceRange.duration.seconds / max(document.duration.seconds, 0.001)) * width
                        Button {
                            selectedSliceID = slice.id
                            inspectorMode = .slice
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                LinearGradient(colors: [VideoStudioPalette.accent.opacity(0.22), VideoStudioPalette.blue.opacity(0.16)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                                Text("S\(index + 1) · \(formatSeconds(slice.sourceRange.duration.seconds))")
                                    .font(VideoStudioPalette.label)
                                    .foregroundStyle(VideoStudioPalette.secondary)
                                    .padding(.leading, 7)
                                    .padding(.bottom, 5)
                            }
                            .frame(width: max(8, segmentWidth), height: 50)
                            .overlay(alignment: .trailing) { Rectangle().fill(VideoStudioPalette.border).frame(width: 1) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Video slice \(index + 1)")
                        .accessibilityValue("\(formatSeconds(slice.sourceRange.duration.seconds))")
                        .accessibilityHint("Select this slice to inspect it")
                        .position(x: left + segmentWidth / 2, y: 26)
                    }
                    ForEach(idleGaps) { gap in
                        gapOverlay(gap, width: width, height: 50)
                    }
                }
                .simultaneousGesture(timelineSeekGesture(width: width))
            }
            timelineTrack(label: "MIC", height: 34) { width in
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(VideoStudioPalette.surfaceRaised)
                    waveform(width: width, height: 32)
                    fadeOverlay(start: 0, duration: document.model.audio.fadeIn.seconds, width: width, color: VideoStudioPalette.accent)
                    fadeOverlay(start: max(0, document.duration.seconds - document.model.audio.fadeOut.seconds),
                                duration: document.model.audio.fadeOut.seconds, width: width, color: VideoStudioPalette.accent)
                    timelineSeekOverlay(width: width)
                }
                .simultaneousGesture(timelineSeekGesture(width: width))
            }
            timelineTrack(label: "EVENTS", height: 34) { width in
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(VideoStudioPalette.surfaceRaised)
                    timelineSeekOverlay(width: width)
                    ForEach(Array(document.model.effects.events.enumerated()), id: \.offset) { index, event in
                        let x = CGFloat(Double(event.timeMicroseconds) / 1_000_000 / max(document.duration.seconds, 0.001)) * width
                        Button {
                            document.seek(to: (try? RationalTime(event.timeMicroseconds, 1_000_000)) ?? .zero)
                            if event.kind == .click { inspectorMode = .cursorPunch }
                        } label: {
                            Capsule()
                                .fill(event.kind == .click ? VideoStudioPalette.accent : VideoStudioPalette.blue.opacity(0.65))
                                .frame(width: event.kind == .click ? 12 : 10, height: event.kind == .click ? 22 : 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(event.kind == .click ? "Click" : "Cursor") event")
                        .accessibilityValue(mark((try? RationalTime(event.timeMicroseconds, 1_000_000)) ?? .zero))
                        .accessibilityHint(event.kind == .click ? "Selects this click and seeks to it" : "Seeks to this cursor event")
                            .position(x: x, y: 17)
                    }
                }
                .simultaneousGesture(timelineSeekGesture(width: width))
            }
            timelineTrack(label: "OVERLAYS", height: 28) { width in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8).fill(VideoStudioPalette.surfaceRaised)
                    timelineSeekOverlay(width: width)
                    ForEach(document.model.overlays) { overlay in
                        let left = CGFloat(overlay.range.start.seconds / max(document.duration.seconds, 0.001)) * width
                        let overlayWidth = CGFloat(overlay.range.duration.seconds / max(document.duration.seconds, 0.001)) * width
                        Button {
                            document.selectedOverlayID = overlay.id
                            inspectorMode = .overlay
                        } label: {
                            Text(overlay.payload)
                                .font(VideoStudioPalette.label)
                                .foregroundStyle(VideoStudioPalette.background)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .frame(width: max(18, overlayWidth), height: 26, alignment: .leading)
                                .background(VideoStudioPalette.accent, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Overlay \(overlay.payload)")
                        .accessibilityValue("\(mark(overlay.range.start)) to \(mark(overlay.range.end))")
                        .accessibilityHint("Select this overlay to edit it")
                        .offset(x: left)
                    }
                }
                .simultaneousGesture(timelineSeekGesture(width: width))
            }
            timelineRuler
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(VideoStudioPalette.surfaceDeep)
        .focusSection()
        .focusable()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Media timeline")
        .accessibilityHint("Use the timeline to seek, select clips, and edit ranges")
        .accessibilityIdentifier("videoStudio.timeline")
    }

    private func timelineTrack<Content: View>(label: String, height: CGFloat,
                                               @ViewBuilder content: @escaping (CGFloat) -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(VideoStudioPalette.label)
                .foregroundStyle(VideoStudioPalette.tertiary)
                .frame(width: 74, alignment: .leading)
            GeometryReader { proxy in
                content(proxy.size.width)
            }
            .frame(height: height)
            .accessibilityIdentifier("videoStudio.timeline.\(label.lowercased())")
        }
    }

    private var timelineRuler: some View {
        HStack(spacing: 8) {
            Spacer().frame(width: 74)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    ForEach(chaptersVisible ? chapterMarks : []) { chapter in
                        Button(chapter.label) {
                            document.seek(to: chapter.time)
                        }
                        .buttonStyle(VideoStudioRulerButtonStyle())
                        .accessibilityLabel("Chapter \(chapter.label)")
                        .accessibilityValue(mark(chapter.time))
                        .position(x: rulerX(chapter.time, width: proxy.size.width), y: 9)
                    }
                    ForEach(rulerTicks, id: \.self) { tick in
                        Text(tick)
                            .font(VideoStudioPalette.mono)
                            .foregroundStyle(VideoStudioPalette.tertiary)
                            .position(x: rulerX(time(forRulerLabel: tick), width: proxy.size.width), y: 10)
                    }
                    Rectangle()
                        .fill(.white.opacity(0.9))
                        .frame(width: 2, height: 18)
                        .offset(x: rulerX(document.playhead, width: proxy.size.width))
                    if let inPoint = document.selection.inPoint {
                        timelineBoundaryMarker(label: "IN", time: inPoint, width: proxy.size.width, color: VideoStudioPalette.success)
                    }
                    if let outPoint = document.selection.outPoint {
                        timelineBoundaryMarker(label: "OUT", time: outPoint, width: proxy.size.width, color: VideoStudioPalette.accent)
                    }
                }
            }
            .frame(height: 18)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Timeline ruler")
        }
    }

    private func timelineSeekOverlay(width: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .allowsHitTesting(false)
            .accessibilityLabel("Video timeline")
            .accessibilityValue("\(document.timecode), duration \(PlaybackMath.timecode(document.duration, frameRate: document.frameRate))")
            .accessibilityHint("Drag to seek. Use increment and decrement to move one frame.")
            .accessibilityAdjustableAction { direction in
                guard let step = try? PlaybackMath.frameStep(frameRate: document.frameRate) else { return }
                switch direction {
                case .increment: document.seek(to: min(document.duration, (try? document.playhead + step) ?? document.playhead))
                case .decrement: document.seek(to: max(.zero, (try? document.playhead - step) ?? document.playhead))
                @unknown default: break
                }
            }
            .accessibilityIdentifier("videoStudio.timeline.seek")
    }

    private func timelineSeekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0).onChanged { value in
            guard width > 0,
                  let time = try? RationalTime(Int64(max(0, min(1, value.location.x / width)) * document.duration.seconds * 1_000), 1_000) else { return }
            document.seek(to: time)
        }
    }

    private func timelineBoundaryMarker(label: String, time: RationalTime, width: CGFloat, color: Color) -> some View {
        let x = rulerX(time, width: width)
        return Text(label)
            .font(VideoStudioPalette.label)
            .foregroundStyle(color)
            .padding(.horizontal, 3)
            .background(VideoStudioPalette.surfaceDeep.opacity(0.92), in: RoundedRectangle(cornerRadius: 3))
            .position(x: x, y: 3)
            .accessibilityLabel("\(label) point \(mark(time))")
    }

    private func gapOverlay(_ gap: VideoStudioGap, width: CGFloat, height: CGFloat) -> some View {
        let left = CGFloat(gap.range.start.seconds / max(document.duration.seconds, 0.001)) * width
        let gapWidth = CGFloat(gap.duration / max(document.duration.seconds, 0.001)) * width
        return Button {
            document.selection = .init(inPoint: gap.range.start, outPoint: gap.range.end)
            if document.deleteSelection() {
                flash("Collapsed \(formatSeconds(gap.duration)) of dead air")
            } else {
                flash("This idle gap crosses slices; use Trim to range")
            }
        } label: {
            Text(formatSeconds(gap.duration))
                .font(VideoStudioPalette.label)
                .foregroundStyle(VideoStudioPalette.warning)
                .frame(width: max(8, gapWidth), height: height)
                .background(VideoStudioPalette.warning.opacity(0.10))
                .overlay(Rectangle().stroke(VideoStudioPalette.warning.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
        .buttonStyle(.plain)
        .offset(x: left)
        .help("Collapse this idle gap")
        .accessibilityLabel("Idle gap \(formatSeconds(gap.duration))")
        .accessibilityHint("Collapse this gap when it is within the first video slice")
    }

    @ViewBuilder
    private func timelineThumbnails(width: CGFloat, height: CGFloat) -> some View {
        if document.thumbnails.isEmpty {
            Label(document.thumbnailState == .loading ? "Loading thumbnails…" : "Thumbnails unavailable",
                  systemImage: document.thumbnailState == .loading ? "hourglass" : "photo.slash")
                .font(VideoStudioPalette.label)
                .foregroundStyle(VideoStudioPalette.tertiary)
                .frame(width: width, height: height, alignment: .center)
                .allowsHitTesting(false)
                .accessibilityLabel(document.thumbnailState == .loading ? "Loading video thumbnails" : "Video thumbnails unavailable")
        } else {
            HStack(spacing: 0) {
                ForEach(Array(document.thumbnails.enumerated()), id: \.offset) { _, image in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: height)
                        .clipped()
                }
            }
            .frame(width: width, height: height)
            .opacity(0.3)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func waveform(width: CGFloat, height: CGFloat) -> some View {
        if document.waveform.isEmpty {
            Label(document.waveformState == .loading ? "Loading waveform…" : "Waveform unavailable",
                  systemImage: document.waveformState == .loading ? "hourglass" : "waveform.slash")
                .font(VideoStudioPalette.label)
                .foregroundStyle(VideoStudioPalette.tertiary)
                .frame(width: width, height: height, alignment: .center)
                .allowsHitTesting(false)
                .accessibilityLabel(document.waveformState == .loading ? "Loading audio waveform" : "Audio waveform unavailable")
        } else {
            HStack(spacing: 1) {
                ForEach(Array(document.waveform.enumerated()), id: \.offset) { _, sample in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(document.model.audio.isMuted ? VideoStudioPalette.tertiary : VideoStudioPalette.accent.opacity(0.72))
                        .frame(maxWidth: .infinity, minHeight: 2, maxHeight: max(2, CGFloat(sample) * height * 0.8))
                        .frame(height: height, alignment: .center)
                }
            }
            .padding(.horizontal, 5)
            .frame(width: width)
            .allowsHitTesting(false)
        }
    }

    private func fadeOverlay(start: Double, duration: Double, width: CGFloat, color: Color) -> some View {
        guard duration > 0, document.duration.seconds > 0 else { return AnyView(EmptyView()) }
        let left = CGFloat(start / document.duration.seconds) * width
        let fadeWidth = CGFloat(duration / document.duration.seconds) * width
        return AnyView(
            Rectangle()
                .fill(color.opacity(0.25))
                .frame(width: max(1, fadeWidth), height: 32)
                .offset(x: left)
                .allowsHitTesting(false)
        )
    }

    private var inspector: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(inspectorMode.title).font(.system(size: 12, weight: .semibold))
                Text(inspectorMeta)
                    .font(VideoStudioPalette.mono)
                    .foregroundStyle(VideoStudioPalette.tertiary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .overlay(alignment: .bottom) { Rectangle().fill(VideoStudioPalette.border).frame(height: 1) }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    inspectorModePicker
                    inspectorContent
                }
                .padding(14)
            }
        }
        .background(VideoStudioPalette.surfaceDeep)
        .overlay(alignment: .leading) { Rectangle().fill(VideoStudioPalette.border).frame(width: 1) }
    }

    private var inspectorModePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(VideoStudioInspectorMode.allCases) { mode in
                    Button {
                        inspectorMode = mode
                    } label: {
                        Label(mode.title, systemImage: mode.symbol)
                            .font(.system(size: 10.5, weight: .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(VideoStudioModeButtonStyle(isSelected: inspectorMode == mode))
                    .accessibilityAddTraits(inspectorMode == mode ? .isSelected : [])
                }
            }
        }
        .accessibilityLabel("Inspector modes")
    }

    @ViewBuilder
    private var inspectorContent: some View {
        switch inspectorMode {
        case .effects: effectsInspector
        case .audio: audioInspector
        case .slice: sliceInspector
        case .overlay: overlayInspector
        case .deadAir: deadAirInspector
        case .reframe: reframeInspector
        case .webcam: webcamInspector
        case .cursorPunch: cursorPunchInspector
        case .sfx: sfxInspector
        }
    }

    private var effectsInspector: some View {
        VideoStudioPanel("Presentation effects", symbol: "wand.and.stars") {
            inspectorSummary("Recorded", "\(cursorEventCount) cursor events · \(clickEventCount) clicks")
            inspectorSlider("Cursor emphasis", value: Binding(get: { document.model.effects.cursorEmphasis },
                                                               set: { document.setEffects(cursorEmphasis: $0) }), range: 0...2,
                            valueText: "\(Int(document.model.effects.cursorEmphasis * 50))%")
            inspectorSlider("Click emphasis", value: Binding(get: { document.model.effects.clickEmphasis },
                                                              set: { document.setEffects(clickEmphasis: $0) }), range: 0...2,
                            valueText: "\(Int(document.model.effects.clickEmphasis * 50))%")
            Button("Tune cursor / punch") { inspectorMode = .cursorPunch }
                .buttonStyle(VideoStudioChromeButtonStyle(tint: VideoStudioPalette.secondary, filled: false))
            Button("Choose click sound") { inspectorMode = .sfx }
                .buttonStyle(VideoStudioChromeButtonStyle(tint: VideoStudioPalette.secondary, filled: false))
        }
    }

    private var audioInspector: some View {
        VideoStudioPanel("Audio", symbol: "waveform") {
            if !document.waveform.isEmpty {
                AudioWaveformView(samples: document.waveform)
                    .frame(height: 48)
                    .background(VideoStudioPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Audio waveform")
            } else {
                Label(document.waveformState == .loading ? "Loading waveform…" : "Waveform unavailable",
                      systemImage: document.waveformState == .loading ? "hourglass" : "waveform.slash")
                    .font(VideoStudioPalette.label)
                    .foregroundStyle(VideoStudioPalette.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(VideoStudioPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel(document.waveformState == .loading ? "Loading audio waveform" : "Audio waveform unavailable")
            }
            HStack {
                Text(document.model.audio.isMuted ? "Muted" : "Microphone")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Toggle("", isOn: Binding(get: { !document.model.audio.isMuted }, set: { document.setAudio(muted: !$0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            inspectorSlider("Gain", value: Binding(get: { Double(document.model.audio.gain) },
                                                    set: { document.setAudio(gain: Float($0)) }), range: 0...2,
                            valueText: "\(Int(document.model.audio.gain * 100))%")
            HStack(spacing: 10) {
                inspectorSlider("Fade in", value: Binding(get: { document.model.audio.fadeIn.seconds },
                                                           set: { document.setAudio(fadeIn: $0) }), range: 0...5,
                                valueText: formatSeconds(document.model.audio.fadeIn.seconds))
                inspectorSlider("Fade out", value: Binding(get: { document.model.audio.fadeOut.seconds },
                                                            set: { document.setAudio(fadeOut: $0) }), range: 0...5,
                                valueText: formatSeconds(document.model.audio.fadeOut.seconds))
            }
        }
    }

    private var sliceInspector: some View {
        VideoStudioPanel("This slice", symbol: "scissors") {
            if let slice = selectedSlice {
                inspectorSummary("Source range", "\(formatSeconds(slice.sourceRange.start.seconds)) – \(formatSeconds(slice.sourceRange.end.seconds))")
                inspectorSummary("Duration", formatSeconds(slice.sourceRange.duration.seconds))
                inspectorSlider("Speed", value: $playbackSpeed, range: 0.5...3,
                                valueText: String(format: "%.1f×", playbackSpeed))
                Text("Speed changes are preview-only until a composition speed pass is added.")
                    .font(.system(size: 10))
                    .foregroundStyle(VideoStudioPalette.tertiary)
            } else {
                Text("Select a VIDEO slice to inspect it.")
                    .foregroundStyle(VideoStudioPalette.secondary)
            }
        }
    }

    private var overlayInspector: some View {
        VideoStudioPanel("Overlay", symbol: "text.bubble") {
            Button("Add timed callout", systemImage: "plus.bubble") {
                document.addCallout()
                inspectorMode = .overlay
            }
            .buttonStyle(VideoStudioChromeButtonStyle(tint: VideoStudioPalette.secondary, filled: false))
            ForEach(document.model.overlays) { overlay in
                Button {
                    document.selectedOverlayID = overlay.id
                } label: {
                    HStack {
                        Text(overlay.payload).lineLimit(1)
                        Spacer()
                        Text("\(mark(overlay.range.start)) – \(mark(overlay.range.end))")
                            .font(VideoStudioPalette.mono)
                            .foregroundStyle(VideoStudioPalette.tertiary)
                    }
                    .padding(8)
                    .background(document.selectedOverlayID == overlay.id ? VideoStudioPalette.accent.opacity(0.14) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(document.selectedOverlayID == overlay.id ? VideoStudioPalette.accent.opacity(0.6) : .clear))
            }
            if let overlay = selectedOverlay {
                Divider().overlay(VideoStudioPalette.border)
                TextField("Overlay text", text: Binding(get: { overlay.payload }, set: {
                    document.updateSelectedOverlay(payload: $0, start: overlay.range.start.seconds, duration: overlay.range.duration.seconds)
                }))
                .textFieldStyle(.roundedBorder)
                overlayNumberField("Start", value: overlay.range.start.seconds) {
                    document.updateSelectedOverlay(payload: overlay.payload, start: $0, duration: overlay.range.duration.seconds)
                }
                overlayNumberField("Duration", value: overlay.range.duration.seconds) {
                    document.updateSelectedOverlay(payload: overlay.payload, start: overlay.range.start.seconds, duration: $0)
                }
                overlayNumberField("X", value: overlay.bounds.x) { updateOverlayBounds(overlay, x: $0) }
                overlayNumberField("Y", value: overlay.bounds.y) { updateOverlayBounds(overlay, y: $0) }
                overlayNumberField("Width", value: overlay.bounds.width) { updateOverlayBounds(overlay, width: $0) }
                overlayNumberField("Height", value: overlay.bounds.height) { updateOverlayBounds(overlay, height: $0) }
                ColorPicker("Color", selection: Binding(
                    get: { Color(.sRGB, red: overlay.color.red, green: overlay.color.green, blue: overlay.color.blue, opacity: overlay.color.alpha) },
                    set: { value in
                        guard let color = NSColor(value).usingColorSpace(.sRGB) else { return }
                        document.updateSelectedOverlayVisual(color: .init(red: Double(color.redComponent), green: Double(color.greenComponent),
                                                                         blue: Double(color.blueComponent), alpha: Double(color.alphaComponent)))
                    }
                ), supportsOpacity: true)
            }
        }
    }

    private func overlayNumberField(
        _ label: String,
        value: Double,
        update: @escaping @MainActor @Sendable (Double) -> Void
    ) -> some View {
        HStack {
            Text(label).font(.system(size: 11, weight: .medium))
            Spacer()
            TextField(label, value: Binding(get: { value }, set: update), format: .number.precision(.fractionLength(3)))
                .frame(width: 76)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func updateOverlayBounds(_ overlay: TimedOverlay, x: Double? = nil, y: Double? = nil,
                                     width: Double? = nil, height: Double? = nil) {
        var bounds = overlay.bounds
        if let x { bounds.x = x }
        if let y { bounds.y = y }
        if let width { bounds.width = width }
        if let height { bounds.height = height }
        document.updateSelectedOverlayVisual(bounds: bounds)
    }

    private var deadAirInspector: some View {
        VideoStudioPanel("Dead air", symbol: "pause.circle") {
            inspectorSlider("Min idle length", value: $idleThreshold, range: 1...6, step: 0.5,
                            valueText: formatSeconds(idleThreshold))
            Text("\(idleGaps.count) gaps found · \(formatSeconds(idleGapDuration)) removable")
                .font(VideoStudioPalette.mono)
                .foregroundStyle(idleGaps.isEmpty ? VideoStudioPalette.tertiary : VideoStudioPalette.warning)
            Button("Collapse all idle gaps") { collapseIdleGaps() }
                .buttonStyle(VideoStudioChromeButtonStyle(tint: VideoStudioPalette.warning, filled: false))
                .disabled(idleGaps.isEmpty)
            Button("Freeze frame at playhead") {
                document.addFreezeFrame()
                flash("Freeze frame added")
            }
            .buttonStyle(VideoStudioChromeButtonStyle(tint: VideoStudioPalette.secondary, filled: false))
            Toggle("Chapter markers", isOn: $chaptersVisible)
                .toggleStyle(.switch)
        }
    }

    private var reframeInspector: some View {
        VideoStudioPanel("Reframe", symbol: "rectangle.arrowtriangle.2.inward") {
            Text("Preview canvas")
                .font(VideoStudioPalette.label)
                .foregroundStyle(VideoStudioPalette.tertiary)
            HStack(spacing: 4) {
                ForEach(reframeOptions, id: \.self) { option in
                    Button(option) { document.setReframe(aspectRatio: option) }
                        .buttonStyle(VideoStudioChoiceButtonStyle(isSelected: reframe == option))
                }
            }
            Toggle("Follow the cursor", isOn: Binding(get: { document.model.effects.reframeAspectRatio != nil }, set: { if !$0 { document.setReframe(aspectRatio: nil) } }))
                .toggleStyle(.switch)
            Text("Output framing is previewed here; source pixels remain non-destructive until export.")
                .font(.system(size: 10))
                .foregroundStyle(VideoStudioPalette.tertiary)
        }
    }

    private var webcamInspector: some View {
        VideoStudioPanel("Webcam", symbol: "web.camera") {
            if document.hasWebcamMedia {
                Toggle("Show webcam", isOn: Binding(get: { webcamOn }, set: { document.setWebcam(isEnabled: $0) }))
                    .toggleStyle(.switch)
            } else {
                Label("Webcam media unavailable", systemImage: "web.camera.fill.badge.exclamationmark")
                    .font(.system(size: 11)).foregroundStyle(VideoStudioPalette.warning)
            }
            Text("Corner").font(VideoStudioPalette.label).foregroundStyle(VideoStudioPalette.tertiary)
            HStack(spacing: 4) {
                ForEach(webcamCorners, id: \.self) { corner in
                    Button(corner) { document.setWebcam(corner: corner) }
                        .buttonStyle(VideoStudioChoiceButtonStyle(isSelected: webcamCorner == corner))
                }
            }
            Text("Shape").font(VideoStudioPalette.label).foregroundStyle(VideoStudioPalette.tertiary)
            HStack(spacing: 4) {
                ForEach(["Circle", "Rounded"], id: \.self) { shape in
                    Button(shape) { document.setWebcam(isCircular: shape == "Circle") }
                        .buttonStyle(VideoStudioChoiceButtonStyle(isSelected: webcamShape == shape))
                }
            }
            Text(document.hasWebcamMedia ? "The recorded camera stream is composited into preview and export." : "Add a recorded camera stream to use this effect.")
                .font(.system(size: 10))
                .foregroundStyle(VideoStudioPalette.tertiary)
        }
    }

    private var cursorPunchInspector: some View {
        VideoStudioPanel("Cursor / punch-ins", symbol: "cursorarrow.motionlines") {
            inspectorSlider("Cursor smoothing", value: Binding(get: { document.model.effects.cursorEmphasis },
                                                               set: { document.setEffects(cursorEmphasis: $0) }), range: 0...2,
                            valueText: "\(Int(document.model.effects.cursorEmphasis * 50))%")
            inspectorSlider("Click emphasis", value: Binding(get: { document.model.effects.clickEmphasis },
                                                              set: { document.setEffects(clickEmphasis: $0) }), range: 0...2,
                            valueText: "\(Int(document.model.effects.clickEmphasis * 50))%")
            Button("Punch in on every click") {
                document.setPunchIns(enabled: true)
                flash("Punch-ins added · \(punchedClicks.count) recorded clicks")
            }
            .buttonStyle(VideoStudioChromeButtonStyle(tint: VideoStudioPalette.accent, filled: false))
            Button("Clear punch-ins") { document.setPunchIns(enabled: false) }
                .buttonStyle(VideoStudioChromeButtonStyle(tint: VideoStudioPalette.secondary, filled: false))
            Text("\(punchedClicks.count) click punch-ins enabled")
                .font(VideoStudioPalette.mono)
                .foregroundStyle(VideoStudioPalette.tertiary)
        }
    }

    private var sfxInspector: some View {
        VideoStudioPanel("Click sound", symbol: "speaker.wave.2") {
            Text(clickEventCount == 0 ? "Click sound unavailable without recorded click events" : "Sound applied to recorded click events")
                .font(.system(size: 11))
                .foregroundStyle(clickEventCount == 0 ? VideoStudioPalette.warning : VideoStudioPalette.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                ForEach(clickSoundOptions, id: \.self) { option in
                    Button(option) { document.setClickSound(option == "Off" ? "off" : option) }
                        .buttonStyle(VideoStudioChoiceButtonStyle(isSelected: clickSound == option || (option == "Off" && clickSound == "off")))
                        .disabled(clickEventCount == 0)
                }
            }
            Text("Selected: \(clickSound)")
                .font(VideoStudioPalette.mono)
                .foregroundStyle(VideoStudioPalette.tertiary)
        }
    }

    private func inspectorSummary(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(VideoStudioPalette.label).foregroundStyle(VideoStudioPalette.tertiary)
            Spacer()
            Text(value).font(VideoStudioPalette.mono).foregroundStyle(VideoStudioPalette.secondary)
        }
    }

    private func inspectorSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>,
                                 step: Double = 0.01, valueText: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label).font(VideoStudioPalette.label).foregroundStyle(VideoStudioPalette.tertiary)
                Spacer()
                Text(valueText).font(VideoStudioPalette.mono).foregroundStyle(VideoStudioPalette.secondary)
            }
            Slider(value: value, in: range, step: step).tint(VideoStudioPalette.accent)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if let progress = document.exportProgress {
                ProgressView(value: progress).tint(VideoStudioPalette.accent).frame(width: 180)
                Text(document.statusMessage)
                Button("Cancel") { document.cancelExport() }
                    .buttonStyle(VideoStudioChromeButtonStyle(tint: VideoStudioPalette.secondary, filled: false))
            } else {
                Text(document.statusMessage).lineLimit(1)
            }
            Spacer()
            if let url = document.lastExportURL {
                Button("Reveal export") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(VideoStudioChromeButtonStyle(tint: VideoStudioPalette.secondary, filled: false))
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(VideoStudioPalette.secondary)
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(VideoStudioPalette.surface)
        .overlay(alignment: .top) { Rectangle().fill(VideoStudioPalette.border).frame(height: 1) }
    }

    private var documentMeta: String {
        let size = previewSourceSize
        return "\(Int(size.width)) × \(Int(size.height)) · \(formatSeconds(document.duration.seconds)) after edits · \(clickEventCount) clicks recorded"
    }

    private var codecMeta: String {
        codec == "h264" ? "MediaExportPreset.h264 · \(frameRateText)" : "MediaExportPreset.hevc · \(frameRateText) · smaller"
    }

    private var frameRateText: String {
        String(format: "%.0f fps", document.frameRate.seconds)
    }

    private var estimatedSize: String {
        let mb = max(1, document.duration.seconds * (codec == "h264" ? 0.72 : 0.48))
        return mb > 1024 ? String(format: "%.1f GB", mb / 1024) : "\(Int(mb.rounded())) MB"
    }

    private var inspectorMeta: String {
        switch inspectorMode {
        case .effects: "\(cursorEventCount) cursor · \(clickEventCount) clicks · \(idleGaps.count) idle gaps"
        case .audio: document.model.audio.isMuted ? "microphone muted" : "microphone enabled"
        case .slice: selectedSlice.map { formatSeconds($0.sourceRange.duration.seconds) } ?? "select a video slice"
        case .overlay: selectedOverlay?.payload ?? "select an overlay"
        case .deadAir: "\(formatSeconds(idleGapDuration)) removable"
        case .reframe: "\(reframe) preview canvas"
        case .webcam: webcamOn ? "camera visible · \(webcamCorner)" : "camera hidden"
        case .cursorPunch: "\(punchedClicks.count) punch-ins"
        case .sfx: clickSound
        }
    }

    private var stageCanvasSize: CGSize {
        switch reframe {
        case "16:9": CGSize(width: 16, height: 9)
        case "1:1": CGSize(width: 1, height: 1)
        case "9:16": CGSize(width: 9, height: 16)
        case "4:5": CGSize(width: 4, height: 5)
        default: previewCanvasSize
        }
    }

    private var previewCanvasSize: CGSize {
        let requested = document.model.canvas.map { CGSize(width: $0.width, height: $0.height) } ?? previewSourceSize
        return VideoStudioDocument.normalizedOutputSize(requested) ?? requested
    }

    private var previewSourceSize: CGSize {
        let sourceID = document.model.slices.first?.sourceAssetID ?? document.manifest.primarySourceAssetID
        return document.sourceDisplaySize(for: sourceID) ?? CGSize(width: 16, height: 9)
    }

    private func cropLayout(outputRect: CGRect, punchIn: RecordedEffectEvent?) -> MediaCropLayout? {
        let crop = document.model.canvas?.crop
        let baseCrop = AeroNormalizedRect(x: crop?.x ?? 0, y: crop?.y ?? 0,
                                          width: crop?.width ?? 1, height: crop?.height ?? 1)
        let resolvedCrop = MediaOutputTiming(freezeFrame: document.model.effects.freezeFrame).crop(baseCrop, for: punchIn)
        return MediaCropLayout.make(sourceRect: CGRect(origin: .zero, size: previewSourceSize), outputRect: outputRect,
                                    normalizedCrop: CGRect(x: resolvedCrop.x, y: resolvedCrop.y,
                                                           width: resolvedCrop.width, height: resolvedCrop.height))
    }

    private func callout(_ overlay: TimedOverlay, in contentRect: CGRect) -> some View {
        let rect = VideoStudioPreviewGeometry.rect(for: overlay.bounds, in: contentRect)
        let color = Color(.sRGB, red: overlay.color.red, green: overlay.color.green, blue: overlay.color.blue, opacity: overlay.color.alpha)
        let moveGesture = DragGesture().onChanged { value in
            guard let origin = document.beginOverlayVisualGesture(overlay.id) else { return }
            document.previewOverlayBounds(VideoStudioPreviewGeometry.moved(origin, translation: value.translation, in: contentRect), for: overlay.id)
        }.onEnded { _ in document.commitOverlayVisualGesture(overlay.id) }
        return ZStack {
            Text(overlay.payload)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(VideoStudioPalette.background)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .frame(width: rect.width, height: rect.height)
                .background(color, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.18)))
                .contentShape(Rectangle())
                .onTapGesture { document.selectedOverlayID = overlay.id; inspectorMode = .overlay }
                .gesture(moveGesture)
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

    private func resizeHandle(_ corner: OverlayResizeCorner, overlay: TimedOverlay, contentRect: CGRect, rect: CGRect) -> some View {
        let x: CGFloat = corner == .topLeft || corner == .bottomLeft ? 10 : rect.width + 10
        let y: CGFloat = corner == .topLeft || corner == .topRight ? 10 : rect.height + 10
        return Circle()
            .fill(VideoStudioPalette.accent)
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
            .frame(width: 12, height: 12)
            .position(x: x, y: y)
            .gesture(DragGesture().onChanged { value in
                guard let origin = document.beginOverlayVisualGesture(overlay.id) else { return }
                document.previewOverlayBounds(VideoStudioPreviewGeometry.resized(origin, corner: corner, translation: value.translation, in: contentRect), for: overlay.id)
            }.onEnded { _ in document.commitOverlayVisualGesture(overlay.id) })
            .accessibilityLabel("Resize callout \(String(describing: corner))")
    }

    private var webcamPreview: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 48
            let x = webcamCorner == "TL" || webcamCorner == "BL" ? inset : proxy.size.width - inset
            let y = webcamCorner == "TL" || webcamCorner == "TR" ? inset : proxy.size.height - inset
            Group {
                if let player = document.webcamPlayer {
                    VideoStudioPlayerView(player: player)
                }
            }
            .frame(width: 78, height: 58)
            .overlay(alignment: .bottom) {
                Text("WEBCAM")
                    .font(VideoStudioPalette.label)
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(VideoStudioPalette.background.opacity(0.6))
            }
            .clipShape(webcamShape == "Circle" ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 12)))
            .overlay {
                if webcamShape == "Circle" {
                    Circle().stroke(.white.opacity(0.18))
                } else {
                    RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.18))
                }
            }
            .position(x: x, y: y)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var selectedOverlay: TimedOverlay? {
        document.model.overlays.first(where: { $0.id == document.selectedOverlayID })
    }

    private var selectedSlice: MediaSlice? {
        if let selectedSliceID, let slice = document.model.slices.first(where: { $0.id == selectedSliceID }) { return slice }
        return document.model.slices.first
    }

    private var selectedSliceLabel: String {
        guard let selectedSlice, let index = document.model.slices.firstIndex(where: { $0.id == selectedSlice.id }) else { return "SOURCE" }
        return "SLICE \(index + 1)"
    }

    private var cursorEventCount: Int { document.model.effects.events.filter { $0.kind == .cursor }.count }
    private var clickEventCount: Int { document.model.effects.events.filter { $0.kind == .click }.count }

    private var idleGaps: [VideoStudioGap] {
        let times = document.model.effects.events.map { Double($0.timeMicroseconds) / 1_000_000 }.sorted()
        guard document.duration.seconds > 0, times.count > 1 else { return [] }
        return zip(times, times.dropFirst()).enumerated().compactMap { index, pair in
            let length = pair.1 - pair.0
            guard length >= idleThreshold,
                  let start = try? RationalTime(Int64(pair.0 * 1_000), 1_000),
                  let duration = try? RationalTime(Int64(length * 1_000), 1_000) else { return nil }
            return VideoStudioGap(id: index, range: .init(start: start, duration: duration))
        }
    }

    private var idleGapDuration: Double { idleGaps.reduce(0) { $0 + $1.duration } }

    private var chapterMarks: [VideoStudioChapter] {
        var cursor = RationalTime.zero
        return document.model.slices.enumerated().compactMap { index, slice in
            defer { cursor = (try? cursor + slice.sourceRange.duration) ?? cursor }
            return VideoStudioChapter(id: index, time: cursor, label: index == 0 ? "Intro" : "Slice \(index + 1)")
        }
    }

    private var rulerTicks: [String] {
        guard document.duration.seconds > 0 else { return ["0:00"] }
        let count = 5
        return (0..<count).map { index in formatSeconds(document.duration.seconds * Double(index) / Double(count - 1), includeHundredths: false) }
    }

    private func time(forRulerLabel label: String) -> RationalTime {
        guard let seconds = label.split(separator: ":").last.flatMap({ Double($0) }),
              let minutes = label.split(separator: ":").first.flatMap({ Double($0) }),
              let time = try? RationalTime(Int64((minutes * 60 + seconds) * 1_000), 1_000) else { return .zero }
        return min(time, document.duration)
    }

    private func rulerX(_ time: RationalTime, width: CGFloat) -> CGFloat {
        CGFloat(time.seconds / max(document.duration.seconds, 0.001)) * width
    }

    private func sliceStart(_ index: Int) -> Double {
        document.model.slices.prefix(index).reduce(0) { $0 + $1.sourceRange.duration.seconds }
    }

    private func collapseIdleGaps() {
        let gaps = idleGaps.reversed()
        guard !gaps.isEmpty else { return }
        var collapsed = 0
        var skipped = 0
        var removed = 0.0
        for gap in gaps {
            guard document.canRippleDelete(range: gap.range) else {
                skipped += 1
                continue
            }
            document.selection = .init(inPoint: gap.range.start, outPoint: gap.range.end)
            if document.deleteSelection() {
                collapsed += 1
                removed += gap.duration
            } else {
                skipped += 1
            }
        }
        document.selection = .init()
        if skipped > 0 {
            flash("Collapsed \(collapsed) idle gaps · \(formatSeconds(removed)) removed; skipped \(skipped) across slices")
        } else {
            flash("Collapsed \(collapsed) idle gaps · \(formatSeconds(removed)) removed")
        }
    }

    private func chooseExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "Aeroshot Export.mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        document.export(to: url, codec: codec == "hevc" ? .hevc : .h264)
    }

    private func flash(_ message: String) {
        toast = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            if toast == message { toast = nil }
        }
    }

    private func mark(_ time: RationalTime) -> String { PlaybackMath.timecode(time, frameRate: document.frameRate) }

    private func formatSeconds(_ seconds: Double, includeHundredths: Bool = true) -> String {
        guard seconds.isFinite else { return "0:00" }
        let minutes = Int(seconds) / 60
        let whole = Int(seconds) % 60
        if includeHundredths {
            return String(format: "%d:%02d.%02d", minutes, whole, Int((seconds - floor(seconds)) * 100))
        }
        return String(format: "%d:%02d", minutes, whole)
    }

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
            case "s": document.perform(.split)
            case "g": collapseIdleGaps()
            default: return .ignored
            }
        }
        return .handled
    }
}

private struct VideoStudioGrid: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(VideoStudioPalette.surfaceDeep))
            for x in stride(from: CGFloat(1), through: size.width, by: 17) {
                for y in stride(from: CGFloat(1), through: size.height, by: 17) {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(VideoStudioPalette.borderStrong))
                }
            }
        }
    }
}

private struct VideoStudioPanel<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    init(_ title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VideoStudioPalette.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(VideoStudioPalette.border))
    }
}

private struct VideoStudioChromeButtonStyle: ButtonStyle {
    let tint: Color
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(filled ? VideoStudioPalette.background : tint)
            .padding(.horizontal, 11)
            .frame(minHeight: 30)
            .background(filled ? tint : tint.opacity(configuration.isPressed ? 0.18 : 0.06),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(filled ? .clear : tint.opacity(0.45)))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private struct VideoStudioQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(VideoStudioPalette.secondary)
            .background(VideoStudioPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(VideoStudioPalette.border))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct VideoStudioPlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(VideoStudioPalette.background)
            .background(VideoStudioPalette.accent, in: RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

private struct VideoStudioTabButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isSelected ? VideoStudioPalette.accent : VideoStudioPalette.tertiary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(isSelected ? VideoStudioPalette.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct VideoStudioModeButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? VideoStudioPalette.accent : VideoStudioPalette.secondary)
            .background(isSelected ? VideoStudioPalette.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(isSelected ? VideoStudioPalette.accent.opacity(0.55) : .clear))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct VideoStudioChoiceButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(isSelected ? VideoStudioPalette.accent : VideoStudioPalette.secondary)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(isSelected ? VideoStudioPalette.accent.opacity(0.14) : VideoStudioPalette.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(isSelected ? VideoStudioPalette.accent.opacity(0.5) : VideoStudioPalette.border))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct VideoStudioRulerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(VideoStudioPalette.label)
            .foregroundStyle(VideoStudioPalette.tertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(VideoStudioPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(VideoStudioPalette.border))
            .opacity(configuration.isPressed ? 0.65 : 1)
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
            }
            .stroke(VideoStudioPalette.accent.opacity(0.75), lineWidth: 1)
        }
    }
}
