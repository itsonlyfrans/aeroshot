import AppKit
import Combine
import SwiftUI

nonisolated struct HUDRecordingOptions: Equatable, Sendable {
    var microphoneEnabled: Bool
    var systemAudioEnabled: Bool
    var cameraEnabled: Bool
    var countdownSeconds: Int
}

enum HUDCaptureBarStage: Equatable {
    case idle
    case countdown
    case recording
    case saved
    case flying
    case thumbnail
}

@MainActor
final class HUDToolbarModel: ObservableObject {
    @Published var selected: CaptureIntent
    @Published var stage: HUDCaptureBarStage = .idle
    @Published var options: HUDRecordingOptions
    @Published var recordingFormat: RecordingFormat
    @Published var countdownRemaining = 0
    @Published var elapsed = "0:00"
    @Published var isPaused = false
    @Published private(set) var startedFromCountdown = false
    @Published var systemAudioLevel: Float = 0
    @Published var microphoneLevel: Float = 0
    @Published var blockingMessage: String?
    @Published private(set) var savedURL: URL?
    @Published private(set) var hasSelection = false
    @Published private(set) var isAreaSelection = false
    @Published private(set) var isRequestingMicrophonePermission = false
    @Published private(set) var isRequestingCameraPermission = false

    let reviewSelection: Bool

    var onSelect: ((CaptureIntent) -> Void)?
    var onRecord: ((CaptureIntent, HUDRecordingOptions) -> Void)?
    var onOptionsChanged: ((HUDRecordingOptions) -> Void)?
    var onRequestMicrophonePermission: (() async -> Bool)?
    var onRequestCameraPermission: (() async -> Bool)?
    var onCancel: (() -> Void)?
    var onStop: (() -> Void)?
    var onPauseResume: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onShare: ((URL) -> Void)?

    private var parkTask: Task<Void, Never>?
    private var postCaptureModel: RecordingPostCaptureModel?

    init(
        selected: CaptureIntent,
        options: HUDRecordingOptions,
        reviewSelection: Bool = false,
        recordingFormat: RecordingFormat = .mp4
    ) {
        self.selected = selected
        self.options = options
        self.reviewSelection = reviewSelection
        self.recordingFormat = recordingFormat
    }

    deinit {
        parkTask?.cancel()
    }

    func select(_ intent: CaptureIntent) {
        blockingMessage = nil
        selected = intent
        onSelect?(intent)
    }

    func toggleMicrophone() {
        guard supportsAudioAndPause else { return }
        if options.microphoneEnabled {
            options.microphoneEnabled = false
            optionsChanged()
            return
        }
        guard let onRequestMicrophonePermission else {
            options.microphoneEnabled = true
            optionsChanged()
            return
        }
        isRequestingMicrophonePermission = true
        Task { [weak self] in
            let granted = await onRequestMicrophonePermission()
            guard let self else { return }
            isRequestingMicrophonePermission = false
            guard granted else {
                blockingMessage = "Microphone permission was not granted."
                return
            }
            options.microphoneEnabled = true
            optionsChanged()
        }
    }

    func toggleSystemAudio() {
        guard supportsAudioAndPause else { return }
        options.systemAudioEnabled.toggle()
        optionsChanged()
    }

    func toggleCamera() {
        if options.cameraEnabled {
            options.cameraEnabled = false
            optionsChanged()
            return
        }
        guard let onRequestCameraPermission else {
            options.cameraEnabled = true
            optionsChanged()
            return
        }
        isRequestingCameraPermission = true
        Task { [weak self] in
            let granted = await onRequestCameraPermission()
            guard let self else { return }
            isRequestingCameraPermission = false
            guard granted else {
                blockingMessage = "Camera permission was not granted."
                return
            }
            options.cameraEnabled = true
            optionsChanged()
        }
    }

    func cycleCountdown() {
        options.countdownSeconds = [3: 5, 5: 10, 10: 0, 0: 3][options.countdownSeconds] ?? 3
        optionsChanged()
    }

    func startRecording(_ intent: CaptureIntent) {
        blockingMessage = nil
        onRecord?(intent, options)
    }

    func updateSelection(isReady: Bool, supportsAreaActions: Bool = false) {
        hasSelection = isReady
        isAreaSelection = isReady && supportsAreaActions
        if isReady { blockingMessage = nil }
    }

    func showCountdown(total: Int, remaining: Int) {
        options.countdownSeconds = total
        countdownRemaining = remaining
        stage = .countdown
    }

    func showRecording(startedFromCountdown: Bool) {
        isPaused = false
        self.startedFromCountdown = startedFromCountdown
        stage = .recording
    }

    func showSaved(url: URL, duration: String) {
        parkTask?.cancel()
        savedURL = url
        elapsed = duration
        postCaptureModel = RecordingPostCaptureModel(outputURL: url)
        stage = .saved
        parkTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled, let self, self.stage == .saved else { return }
            self.stage = .flying
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled, self.stage == .flying else { return }
            self.stage = .thumbnail
        }
    }

    func cancelOrDismiss() {
        switch stage {
        case .countdown, .recording:
            onCancel?()
        case .idle:
            onCancel?()
        case .saved, .flying, .thumbnail:
            parkTask?.cancel()
            onDismiss?()
        }
    }

    func copySavedRecording() {
        postCaptureModel?.copy()
    }

    func editSavedRecording() {
        postCaptureModel?.edit()
    }

    func shareSavedRecording() {
        guard let savedURL else { return }
        onShare?(savedURL)
    }

    var savedLocationName: String {
        savedURL?.deletingLastPathComponent().lastPathComponent ?? "folder"
    }

    private func optionsChanged() {
        blockingMessage = nil
        onOptionsChanged?(options)
    }

    var supportsAudioAndPause: Bool { recordingFormat == .mp4 }
}

struct HUDToolbarView: View {
    @ObservedObject var model: HUDToolbarModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredIntent: CaptureIntent?
    @State private var recordDotVisible = true
    @State private var recordDotScale: CGFloat = 1

    private let captureIntents: [CaptureIntent] = [.area, .window, .fullScreen, .scrolling, .ocr]
    private let recordingRed = Color(red: 0.898, green: 0.282, blue: 0.302)
    private let pausedAmber = Color(red: 0.996, green: 0.737, blue: 0.180)

    var body: some View {
        Group {
            switch model.stage {
            case .idle:
                idleBar
            case .countdown:
                countdownBar
            case .recording:
                recordingBar
            case .saved, .flying:
                savedBar
            case .thumbnail:
                thumbnailCard
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(AeroTokens.Stroke.subtle, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.42), radius: 25, x: 0, y: 14)
        .scaleEffect(model.stage == .flying && !reduceMotion ? 0.4 : 1)
        .opacity(model.stage == .flying && !reduceMotion ? 0 : 1)
        .animation(morphAnimation, value: model.stage)
        .accessibilityElement(children: .contain)
    }

    private var idleBar: some View {
        VStack(spacing: AeroTokens.Spacing.xs) {
            HStack(spacing: AeroTokens.Spacing.medium) {
                HStack(spacing: AeroTokens.Spacing.xxs) {
                    ForEach(captureIntents) { intent in
                        intentButton(intent)
                    }
                }

                Divider().frame(height: 30)

                HStack(spacing: AeroTokens.Spacing.xs) {
                    if model.supportsAudioAndPause {
                        optionButton(
                            symbol: "mic",
                            label: "Microphone",
                            enabled: model.options.microphoneEnabled,
                            action: model.toggleMicrophone
                        )
                        .disabled(model.isRequestingMicrophonePermission)
                        optionButton(
                            symbol: "speaker.wave.2",
                            label: "System audio",
                            enabled: model.options.systemAudioEnabled,
                            action: model.toggleSystemAudio
                        )
                    }
                    optionButton(
                        symbol: "video",
                        label: "Camera",
                        enabled: model.options.cameraEnabled,
                        action: model.toggleCamera
                    )
                    .disabled(model.isRequestingCameraPermission)
                    Button(action: model.cycleCountdown) {
                        Text("\(model.options.countdownSeconds)s")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HUDCommandButtonStyle())
                    .help("Countdown")
                    .accessibilityLabel("Recording countdown")
                    .accessibilityValue("\(model.options.countdownSeconds) seconds")
                }

                if let message = model.blockingMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(AeroTokens.Typography.small(weight: .semibold))
                        .foregroundStyle(AeroTokens.ColorRole.warning)
                        .lineLimit(2)
                        .frame(width: 150, alignment: .leading)
                        .accessibilityIdentifier("captureBar.blockingMessage")
                } else if model.reviewSelection {
                    Button {
                        model.startRecording(model.selected)
                    } label: {
                        HStack(spacing: AeroTokens.Spacing.small) {
                            Circle().frame(width: 8, height: 8)
                            Text("Record")
                        }
                        .font(AeroTokens.Typography.body(weight: .bold))
                        .foregroundStyle(AeroTokens.ColorRole.onAccent)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(recordingRed, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(HUDCommandButtonStyle())
                    .disabled(!model.hasSelection)
                    .help("Record the selected target")
                    .accessibilityIdentifier("captureBar.record")
                } else {
                    Menu {
                        Button("Record Area", systemImage: CaptureIntent.area.symbol) {
                            model.startRecording(.area)
                        }
                        Button("Record Window", systemImage: CaptureIntent.window.symbol) {
                            model.startRecording(.window)
                        }
                        Button("Record Screen", systemImage: CaptureIntent.fullScreen.symbol) {
                            model.startRecording(.fullScreen)
                        }
                    } label: {
                        HStack(spacing: AeroTokens.Spacing.small) {
                            Circle().frame(width: 8, height: 8)
                            Text("Record")
                        }
                        .font(AeroTokens.Typography.body(weight: .bold))
                        .foregroundStyle(AeroTokens.ColorRole.onAccent)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(AeroTokens.ColorRole.accent, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .menuStyle(.button)
                    .buttonStyle(HUDCommandButtonStyle())
                    .fixedSize()
                    .help("Choose what to record")
                    .accessibilityLabel("Choose recording source")
                    .accessibilityIdentifier("captureBar.record")
                }
            }
            .padding(.leading, 7)
            .padding(.trailing, 8)
            .padding(.vertical, 7)
        }
        .transition(contentTransition)
    }

    private var countdownBar: some View {
        HStack(spacing: AeroTokens.Spacing.medium) {
            ZStack {
                Circle()
                    .stroke(AeroTokens.Fill.rest, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: countdownProgress)
                    .stroke(AeroTokens.ColorRole.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(model.countdownRemaining)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .contentTransition(.numericText())
            }
            .frame(width: 30, height: 30)

            Text("Starting…")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.secondary)

            ghostButton("Cancel", action: model.cancelOrDismiss)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .transition(contentTransition)
    }

    private var recordingBar: some View {
        HStack(spacing: AeroTokens.Spacing.medium) {
            Circle()
                .fill(model.isPaused ? pausedAmber : recordingRed)
                .frame(width: 10, height: 10)
                .scaleEffect(recordDotScale)
                .opacity(model.isPaused || reduceMotion || recordDotVisible ? 1 : 0.3)
                .onAppear {
                    if model.startedFromCountdown, !reduceMotion {
                        recordDotScale = 3
                        withAnimation(.timingCurve(0.3, 0.9, 0.35, 1, duration: 0.55)) {
                            recordDotScale = 1
                        }
                    }
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                        recordDotVisible = false
                    }
                }

            Text(model.elapsed)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .frame(minWidth: 40, alignment: .leading)

            if model.supportsAudioAndPause {
                audioMeter

                Divider().frame(height: 18)

                circleButton(
                    symbol: model.isPaused ? "play.fill" : "pause.fill",
                    label: model.isPaused ? "Resume" : "Pause",
                    fill: AeroTokens.Fill.rest,
                    foreground: .primary,
                    action: { model.onPauseResume?() }
                )
            }
            circleButton(
                symbol: "stop.fill",
                label: "Stop and save",
                fill: recordingRed,
                foreground: .white,
                action: { model.onStop?() }
            )
            ghostButton("✕", action: model.cancelOrDismiss)
                .help("Discard recording")
                .accessibilityLabel("Discard recording")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .transition(contentTransition)
    }

    private var savedBar: some View {
        HStack(spacing: AeroTokens.Spacing.medium) {
            preview(width: 56, height: 36, radius: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text("Saved to \(model.savedLocationName)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(model.savedURL?.lastPathComponent ?? "Recording") · \(model.elapsed)")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Divider().frame(height: 22)

            HStack(spacing: AeroTokens.Spacing.xxs) {
                actionButton("Copy", action: model.copySavedRecording)
                actionButton("Edit", action: model.editSavedRecording)
                actionButton("Share", action: model.shareSavedRecording)
            }

            ghostButton("✕", action: model.cancelOrDismiss)
                .accessibilityLabel("Dismiss")
        }
        .padding(8)
        .transition(contentTransition)
    }

    private var thumbnailCard: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                preview(width: 220, height: 118, radius: 0)
                Text(model.elapsed)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AeroTokens.ColorRole.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.071, green: 0.082, blue: 0.110).opacity(0.85), in: RoundedRectangle(cornerRadius: 5))
                    .padding(7)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(AeroTokens.ColorRole.success)
                    .frame(width: 5, height: 5)
                Text(model.savedURL?.lastPathComponent ?? "Recording")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                thumbnailAction("Copy", action: model.copySavedRecording)
                thumbnailAction("Edit", action: model.editSavedRecording)
                thumbnailAction("✕", action: model.cancelOrDismiss)
                    .accessibilityLabel("Dismiss")
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 7)
        }
        .frame(width: 220)
        .clipShape(RoundedRectangle(cornerRadius: AeroTokens.Radius.card, style: .continuous))
        .transition(reduceMotion ? .opacity : .scale(scale: 0.82).combined(with: .opacity))
    }

    private func intentButton(_ intent: CaptureIntent) -> some View {
        let selected = model.selected == intent
        let hovered = hoveredIntent == intent
        let unavailableForTarget = model.reviewSelection
            && model.hasSelection
            && (intent == .scrolling || intent == .ocr)
            && !model.isAreaSelection
        return Button { model.select(intent) } label: {
            VStack(spacing: 3) {
                Image(systemName: intent.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(height: 17)
                Text(intent.title)
                    .font(.system(size: 9.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? AeroTokens.ColorRole.accent : Color.secondary)
            .frame(width: 52, height: 46)
            .background(
                selected ? AeroTokens.ColorRole.accent.opacity(0.14) : (hovered ? AeroTokens.Fill.hover : .clear),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(HUDCommandButtonStyle())
        .disabled(unavailableForTarget)
        .help(intent.title)
        .accessibilityLabel(intent.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { hovering in
            hoveredIntent = hovering ? intent : nil
        }
    }

    private func optionButton(symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.55))
                .frame(width: 44, height: 44)
                .background(
                    enabled ? AeroTokens.ColorRole.accent.opacity(0.10) : .clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(alignment: .bottom) {
                    Circle()
                        .fill(enabled ? AeroTokens.ColorRole.accent : .clear)
                        .frame(width: 4, height: 4)
                        .offset(y: -1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(HUDCommandButtonStyle())
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(enabled ? "On" : "Off")
    }

    private var audioMeter: some View {
        let level = model.isPaused
            ? 0
            : max(model.systemAudioLevel, model.microphoneLevel)
        let multipliers: [CGFloat] = [0.6, 1, 0.75, 0.45]
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(multipliers.enumerated()), id: \.offset) { index, multiplier in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(model.isPaused ? Color.secondary : AeroTokens.ColorRole.accent)
                    .frame(width: 3, height: max(3, CGFloat(level) * 14 * multiplier + CGFloat(index % 2)))
                    .animation(reduceMotion ? nil : .linear(duration: 0.14), value: level)
            }
        }
        .frame(width: 20, height: 14, alignment: .bottom)
        .accessibilityElement()
        .accessibilityLabel("Audio level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }

    private func circleButton(
        symbol: String,
        label: String,
        fill: Color,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: 32, height: 32)
                .background(fill, in: Circle())
        }
        .buttonStyle(HUDCommandButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }

    private func ghostButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(HUDGhostButtonStyle())
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(AeroTokens.Typography.small(weight: .semibold))
            .buttonStyle(HUDGhostButtonStyle(foreground: .primary))
    }

    private func thumbnailAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 11, weight: .semibold))
            .buttonStyle(HUDGhostButtonStyle(horizontalPadding: 4, verticalPadding: 3))
    }

    private func preview(width: CGFloat, height: CGFloat, radius: CGFloat) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.20, green: 0.22, blue: 0.29),
                    Color(red: 0.11, green: 0.12, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "play.fill")
                .font(.system(size: height > 60 ? 13 : 9, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: height > 60 ? 36 : 22, height: height > 60 ? 36 : 22)
                .background(.white.opacity(0.15), in: Circle())
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    private var countdownProgress: CGFloat {
        CGFloat(model.countdownRemaining) / CGFloat(max(model.options.countdownSeconds, 1))
    }

    private var cornerRadius: CGFloat {
        switch model.stage {
        case .idle, .countdown, .recording: 999
        case .saved, .flying: 16
        case .thumbnail: AeroTokens.Radius.card
        }
    }

    private var morphAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.16) : .timingCurve(0.3, 0.9, 0.35, 1, duration: 0.38)
    }

    private var contentTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .offset(y: 4))
    }
}

private struct HUDCommandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? AeroTheme.pressOpacity : 1)
            .scaleEffect(configuration.isPressed ? AeroTheme.pressScale : 1)
    }
}

private struct HUDGhostButtonStyle: ButtonStyle {
    var foreground: Color = .secondary
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 7

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AeroTokens.Typography.small(weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(configuration.isPressed ? AeroTokens.Fill.pressed : .clear, in: Capsule())
            .contentShape(Rectangle())
    }
}
