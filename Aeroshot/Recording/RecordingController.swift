import AppKit
import AVFoundation
import QuartzCore
import ScreenCaptureKit

/// Orchestrates area/screen recording to MP4 or GIF with optional click highlighting.
@MainActor
final class RecordingController {

    private unowned let appState: AppState
    private var recorder: (any RecordingServicing)?
    private var gifRecorder: GIFRecordingService?
    private var clickHighlights: ClickHighlightController?
    private var effectEventRecorder: RecordingEffectEventRecorder?
    private var webcamOverlay: WebcamOverlayController?
    private var boundaryOverlay: RecordingBoundaryOverlayController?
    private var captureBar: HUDToolbarPanel?
    private var captureBarModel: HUDToolbarModel?
    private var timer: Timer?
    private var startDate: Date?
    private var outputURL: URL?
    private var session = RecordingSessionController()
    private var activeSnapshot: RecordingSessionSnapshot?
    private var recoveryManifestURL: URL?

    private var isRecording: Bool {
        switch session.state {
        case .preflighting, .countdown, .recording, .paused, .stopping: true
        default: false
        }
    }

    init(appState: AppState) {
        self.appState = appState
    }

    func beginAreaRecording() {
        guard !isRecording else { return }
        let options = recordingOptions
        Task {
            guard await appState.permissions.ensurePermission() else { return }
            guard let selection = await appState.captureController.selectArea(mode: .area) else { return }
            await beginAreaRecording(
                with: selection.rect,
                on: selection.display,
                options: options,
                captureBar: nil
            )
        }
    }

    func beginAreaRecording(with cocoaRect: CGRect, on display: DisplayInfo) async {
        await beginAreaRecording(
            with: cocoaRect,
            on: display,
            options: recordingOptions,
            captureBar: nil
        )
    }

    func beginAreaRecording(
        with cocoaRect: CGRect,
        on display: DisplayInfo,
        options: HUDRecordingOptions,
        captureBar: HUDToolbarPanel?
    ) async {
        guard !isRecording else { return }
        guard await appState.permissions.ensurePermission() else { return }
        let local = GeometryConversions.cocoaGlobalToDisplayLocalTopLeft(cocoaRect, screen: display.nsScreen)
        await startRecording(
            display: display,
            rectInDisplayTopLeft: local,
            selectedIntent: captureBar?.model?.selected ?? .area,
            options: options,
            captureBar: captureBar
        )
    }

    func beginScreenRecording() {
        beginScreenRecording(options: recordingOptions, captureBar: nil)
    }

    func beginScreenRecording(options: HUDRecordingOptions, captureBar: HUDToolbarPanel?) {
        beginScreenRecording(on: nil, options: options, captureBar: captureBar)
    }

    func beginScreenRecording(on display: DisplayInfo) {
        beginScreenRecording(on: display, options: recordingOptions, captureBar: nil)
    }

    func beginScreenRecording(
        on selectedDisplay: DisplayInfo,
        options: HUDRecordingOptions,
        captureBar: HUDToolbarPanel?
    ) {
        beginScreenRecording(on: Optional(selectedDisplay), options: options, captureBar: captureBar)
    }

    private func beginScreenRecording(
        on selectedDisplay: DisplayInfo?,
        options: HUDRecordingOptions,
        captureBar: HUDToolbarPanel?
    ) {
        guard !isRecording else { return }
        Task {
            guard await appState.permissions.ensurePermission() else { return }
            do {
                let displays = try await WindowEnumerator.shareableDisplays()
                let mouse = NSEvent.mouseLocation
                let target = selectedDisplay
                    .flatMap { selected in displays.first { $0.displayID == selected.displayID } }
                    ?? displays.first { $0.cocoaFrame.contains(mouse) }
                    ?? displays.first
                guard let target else { return }
                let rect = CGRect(x: 0, y: 0,
                                  width: target.scDisplay.width,
                                  height: target.scDisplay.height)
                await startRecording(
                    display: target,
                    rectInDisplayTopLeft: rect,
                    selectedIntent: .fullScreen,
                    options: options,
                    captureBar: captureBar
                )
            } catch {
                NSLog("Screen recording setup failed: \(error)")
            }
        }
    }

    private func startRecording(
        display: DisplayInfo,
        rectInDisplayTopLeft: CGRect,
        selectedIntent: CaptureIntent,
        options: HUDRecordingOptions,
        captureBar existingCaptureBar: HUDToolbarPanel?
    ) async {
        guard existingCaptureBar != nil || !appState.allInOneController.isPresenting else {
            ToastController.shared.show("Finish All-in-One first", symbol: "rectangle.dashed")
            return
        }
        let settings = appState.settings
        if !isRecording {
            session = RecordingSessionController()
        }
        prepareCaptureBar(
            existing: existingCaptureBar,
            selectedIntent: selectedIntent,
            options: options
        )
        captureBarModel?.blockingMessage = nil

        let rawWidth = Int((rectInDisplayTopLeft.width * display.scale).rounded())
        let rawHeight = Int((rectInDisplayTopLeft.height * display.scale).rounded())
        let (pixelWidth, pixelHeight) = ScreenRecordingService.evenPixelSize(width: rawWidth, height: rawHeight)

        let url = settings.newRecordingURL()
        let availableSpace = Self.availableSpace(at: url)
        do {
            let configuration = try RecordingSessionConfiguration(
                source: .region(displayID: "\(display.scDisplay.displayID)", x: Int(rectInDisplayTopLeft.minX),
                                y: Int(rectInDisplayTopLeft.minY), width: Int(rectInDisplayTopLeft.width),
                                height: Int(rectInDisplayTopLeft.height)),
                dimensions: RecordingDimensions(width: pixelWidth, height: pixelHeight),
                frameRate: RecordingFrameRate(framesPerSecond: 30),
                cursorMode: settings.highlightClicksDuringRecording ? .visibleWithClickEffects : .visible,
                audio: RecordingAudioConfiguration(capturesSystemAudio: options.systemAudioEnabled,
                                                   microphoneDeviceID: options.microphoneEnabled ? (settings.recordingMicrophoneDeviceID.isEmpty ? "default" : settings.recordingMicrophoneDeviceID) : nil),
                webcam: options.cameraEnabled ? RecordingWebcamConfiguration(deviceID: "default") : nil,
                countdown: RecordingCountdown(seconds: options.countdownSeconds),
                events: RecordingEventConfiguration(capturesClicks: settings.highlightClicksDuringRecording),
                requiredSpaceEstimateBytes: 512 * 1_024 * 1_024
            )
            _ = try session.handle(.beginPreflight(configuration: configuration, sessionID: UUID(), at: Date()))
            let microphoneGranted = options.microphoneEnabled
                ? await Self.requestMicrophoneAccess()
                : true
            let cameraGranted = options.cameraEnabled
                ? await Self.requestCameraAccess()
                : true
            let readiness = RecordingPreflightReadiness(
                permissionStatuses: [
                    .screenRecording: .granted,
                    .microphone: microphoneGranted ? .granted : .denied,
                    .camera: cameraGranted ? .granted : .denied
                ],
                availableSpaceBytes: availableSpace
            )
            let preflight = RecordingPreflightModel(configuration: configuration, readiness: readiness)
            guard preflight.isReady else {
                _ = try session.handle(.resolvePreflight(readiness))
                captureBarModel?.blockingMessage = preflight.blockingMessage ?? "Recording preflight failed"
                return
            }
            let effect = try session.handle(.resolvePreflight(readiness))
            switch session.state {
            case .countdown(let snapshot, _), .recording(let snapshot):
                activeSnapshot = snapshot
            default:
                break
            }
            appState.isRecording = true
            outputURL = url
            let boundary = RecordingBoundaryOverlayController()
            boundary.show(
                rect: Self.cocoaRect(
                    for: rectInDisplayTopLeft,
                    on: display
                ),
                style: selectedIntent == .fullScreen ? .screen : .region
            )
            boundaryOverlay = boundary
            if options.cameraEnabled {
                let webcam = WebcamOverlayController()
                webcam.start()
                webcamOverlay = webcam
            }
            if effect == .scheduleCountdownTick {
                guard await runCountdown(total: options.countdownSeconds) else { return }
            } else {
                guard effect == .beginCapture else { return }
                captureBarModel?.showRecording(startedFromCountdown: false)
            }
        } catch {
            NSLog("Recording preflight failed: \(error)")
            captureBarModel?.blockingMessage = error.localizedDescription
            return
        }

        let config = SCStreamConfiguration()
        config.sourceRect = rectInDisplayTopLeft
        config.width = pixelWidth
        config.height = pixelHeight
        config.showsCursor = true
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 5
        config.captureResolution = .best

        persistRecovery(lifecycle: .recording)
        try? await Task.sleep(for: .milliseconds(80))

        if settings.highlightClicksDuringRecording {
            let highlights = ClickHighlightController()
            highlights.start()
            clickHighlights = highlights
        }

        do {
            var includeMicrophone = options.microphoneEnabled && settings.recordingFormat == .mp4
            if includeMicrophone {
                let granted = await Self.requestMicrophoneAccess()
                if !granted {
                    ToastController.shared.show("Microphone access is required", symbol: "mic.slash")
                    includeMicrophone = false
                }
            }
            let webcamWindowID = webcamOverlay?.windowID
            let excluded = await WindowEnumerator.ownWindows().filter { window in
                window.windowID != webcamWindowID
            }
            let filter = ScreenCaptureService.filter(for: display, excludingWindows: excluded)
            switch settings.recordingFormat {
            case .mp4:
                let concreteService = ScreenRecordingService()
                concreteService.microphoneDeviceID = settings.recordingMicrophoneDeviceID.isEmpty ? nil : settings.recordingMicrophoneDeviceID
                concreteService.audioLevelHandler = { [weak self] source, value in
                    Task { @MainActor [weak self] in
                        switch source {
                        case .system: self?.captureBarModel?.systemAudioLevel = value
                        case .microphone: self?.captureBarModel?.microphoneLevel = value
                        }
                    }
                }
                let service: any RecordingServicing = concreteService
                recorder = service
                try await service.start(filter: filter,
                                      configuration: config,
                                      outputURL: url,
                                      includeSystemAudio: options.systemAudioEnabled,
                                      includeMicrophone: includeMicrophone)
            case .gif:
                let service = GIFRecordingService(maxFrames: settings.gifMaxFrames)
                gifRecorder = service
                try await service.start(filter: filter, configuration: config, fps: settings.gifFPS)
            }
            startDate = Date()
            if settings.recordingFormat == .mp4, let startedAt = startDate {
                let displayFrame = display.cocoaFrame
                let captureRect = rectInDisplayTopLeft
                let effects = RecordingEffectEventRecorder(startedAt: startedAt) { point in
                    let local = CGPoint(x: point.x - displayFrame.minX, y: displayFrame.maxY - point.y)
                    let x = (local.x - captureRect.minX) / captureRect.width
                    let y = (local.y - captureRect.minY) / captureRect.height
                    guard x.isFinite, y.isFinite else { return nil }
                    return CGPoint(x: x, y: y)
                }
                effects.start()
                effectEventRecorder = effects
                clickHighlights?.onClick = { [weak effects] point in effects?.recordClick(at: point) }
            }
            startElapsedTimer()
            ToastController.shared.show("Recording started", symbol: "record.circle")
        } catch {
            NSLog("Recording failed to start: \(error)")
            captureBarModel?.blockingMessage = "Failed to start recording."
            await stopRecording(save: false)
        }
    }

    private func togglePause() {
        do {
            switch session.state {
            case .recording:
                guard recorder?.pause() == true else { return }
                _ = try session.handle(.pause)
                timer?.invalidate()
                timer = nil
                captureBarModel?.isPaused = true
                persistRecovery(lifecycle: .paused)
            case .paused:
                guard recorder?.resume() == true else { return }
                _ = try session.handle(.resume)
                startElapsedTimer()
                captureBarModel?.isPaused = false
                persistRecovery(lifecycle: .recording)
            default: break
            }
        } catch { NSLog("Recording pause transition failed: \(error)") }
    }

    private func stopRecording(save: Bool) async {
        timer?.invalidate()
        timer = nil
        clickHighlights?.stop()
        clickHighlights = nil
        webcamOverlay?.stop()
        webcamOverlay = nil
        boundaryOverlay?.dismiss()
        boundaryOverlay = nil

        var savedURL: URL?
        if save {
            do {
                _ = try session.handle(.stop)
                persistRecovery(lifecycle: .stopping)
                if let recorder {
                    savedURL = try await recorder.stop()
                    self.recorder = nil
                } else if let gifRecorder, let url = outputURL {
                    savedURL = try await gifRecorder.stop(outputURL: url,
                                                          frameDelay: 1.0 / Double(appState.settings.gifFPS))
                    self.gifRecorder = nil
                }
                if let finalizedURL = savedURL {
                    effectEventRecorder?.stopAndWrite(beside: finalizedURL)
                    effectEventRecorder = nil
                    let values = try finalizedURL.resourceValues(forKeys: [.fileSizeKey])
                    let byteCount = Int64(values.fileSize ?? 0)
                    let output = try RecordingCompletedOutput(
                        relativePath: RecordingRelativePath(finalizedURL.lastPathComponent),
                        byteCount: byteCount,
                        finalizedAt: Date()
                    )
                    _ = try session.handle(.finalize(output: output, isDurable: byteCount > 0))
                    if case .completed = session.state { cleanRecovery() } else { savedURL = nil }
                }
            } catch {
                NSLog("Recording stop failed: \(error)")
                if let url = outputURL {
                    try? FileManager.default.removeItem(at: url)
                }
                captureBarModel?.blockingMessage = error.localizedDescription
                // Keep HUD visible briefly so the user sees the error.
                try? await Task.sleep(for: .seconds(2))
            }
        } else {
            effectEventRecorder = nil
            _ = try? session.handle(.cancel)
            if let recorder {
                await recorder.cancel()
                self.recorder = nil
            }
            gifRecorder = nil
            if let url = outputURL {
                try? FileManager.default.removeItem(at: url)
            }
            cleanRecovery()
        }

        let savedDuration = startDate.map { Int(Date().timeIntervalSince($0)) } ?? 0

        appState.isRecording = false
        outputURL = nil
        startDate = nil

        if let savedURL {
            if appState.settings.addRecordingsToHistory {
                _ = appState.history.add(recordingFrom: savedURL, durationSeconds: max(savedDuration, 1))
            }
            captureBarModel?.showSaved(
                url: savedURL,
                duration: Self.durationString(seconds: max(savedDuration, 1))
            )
            appState.settings.playSelectedSound()
            await appState.uploadIfNeeded(fileURL: savedURL)
        } else {
            dismissCaptureBarAndReturnToIdle()
        }
    }

    private func startElapsedTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateElapsed() }
        }
    }

    private func persistRecovery(lifecycle: RecordingRecoveryLifecycle) {
        guard let snapshot = activeSnapshot, let outputURL,
              let relativePath = try? RecordingRelativePath(outputURL.lastPathComponent) else { return }
        let manifest = RecordingRecoveryManifest(session: snapshot, lifecycle: lifecycle,
                                                 partialMedia: relativePath, updatedAt: Date())
        do {
            let directory = Self.recoveryDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "\(snapshot.sessionID.uuidString).json")
            try JSONEncoder().encode(manifest).write(to: url, options: .atomic)
            recoveryManifestURL = url
        } catch { NSLog("Could not persist recording recovery manifest: \(error)") }
    }

    private func cleanRecovery() {
        if let recoveryManifestURL { try? FileManager.default.removeItem(at: recoveryManifestURL) }
        recoveryManifestURL = nil
    }

    static var recoveryDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Aeroshot/RecordingRecovery", directoryHint: .isDirectory)
    }

    static func discoverRecoverableSessions(at date: Date = Date()) -> [RecordingRecoveryManifest] {
        RecordingRecoveryStore(directoryURL: recoveryDirectory).discover(at: date)
    }

    private static func availableSpace(at url: URL) -> Int64 {
        let directory = url.deletingLastPathComponent()
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    private func updateElapsed() {
        guard let startDate else { return }
        let elapsed = Int(Date().timeIntervalSince(startDate))
        captureBarModel?.elapsed = Self.durationString(seconds: elapsed)
    }

    private func prepareCaptureBar(
        existing: HUDToolbarPanel?,
        selectedIntent: CaptureIntent,
        options: HUDRecordingOptions
    ) {
        let panel = existing ?? HUDToolbarPanel()
        let model: HUDToolbarModel
        if let existingModel = panel.model {
            model = existingModel
        } else {
            model = HUDToolbarModel(selected: selectedIntent, options: options)
            panel.show(model: model)
        }
        model.options = options
        model.selected = selectedIntent
        model.onStop = { [weak self] in Task { await self?.stopRecording(save: true) } }
        model.onCancel = { [weak self] in Task { await self?.stopRecording(save: false) } }
        model.onPauseResume = { [weak self] in self?.togglePause() }
        model.onDismiss = { [weak self] in self?.dismissCaptureBarAndReturnToIdle() }
        captureBar = panel
        captureBarModel = model
    }

    private func runCountdown(total: Int) async -> Bool {
        while case .countdown(_, let remaining) = session.state {
            captureBarModel?.showCountdown(total: total, remaining: remaining)
            try? await Task.sleep(for: .seconds(1))
            guard case .countdown = session.state else { return false }
            do {
                let effect = try session.handle(.countdownTick)
                if effect == .beginCapture {
                    captureBarModel?.showRecording(startedFromCountdown: true)
                    return true
                }
            } catch {
                captureBarModel?.blockingMessage = error.localizedDescription
                return false
            }
        }
        return false
    }

    private func dismissCaptureBarAndReturnToIdle() {
        captureBar?.dismiss()
        captureBar = nil
        captureBarModel = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.appState.allInOneController.begin()
        }
    }

    private var recordingOptions: HUDRecordingOptions {
        let defaults = UserDefaults.standard
        let countdown = defaults.object(forKey: "recordingCountdownSeconds") == nil
            ? 3
            : defaults.integer(forKey: "recordingCountdownSeconds")
        return HUDRecordingOptions(
            microphoneEnabled: appState.settings.recordMicrophone,
            systemAudioEnabled: appState.settings.recordSystemAudio,
            cameraEnabled: appState.settings.showWebcamOverlay,
            countdownSeconds: countdown
        )
    }

    private static func durationString(seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func cocoaRect(
        for displayLocalTopLeftRect: CGRect,
        on display: DisplayInfo
    ) -> CGRect {
        let frame = display.cocoaFrame
        return CGRect(
            x: frame.minX + displayLocalTopLeftRect.minX,
            y: frame.maxY - displayLocalTopLeftRect.maxY,
            width: displayLocalTopLeftRect.width,
            height: displayLocalTopLeftRect.height
        )
    }

    static func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static func requestCameraAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

@MainActor
final class RecordingBoundaryOverlayController {
    enum Style {
        case region
        case screen
    }

    private var panel: NSPanel?

    func show(rect: CGRect, style: Style) {
        dismiss()
        let frame = style == .screen ? rect.insetBy(dx: 5, dy: 5) : rect
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        let border = CAShapeLayer()
        border.frame = view.bounds
        border.path = CGPath(
            roundedRect: view.bounds.insetBy(dx: 1.5, dy: 1.5),
            cornerWidth: style == .screen ? 12 : 6,
            cornerHeight: style == .screen ? 12 : 6,
            transform: nil
        )
        border.fillColor = NSColor.clear.cgColor
        border.strokeColor = NSColor(red: 1, green: 0.541, blue: 0.420, alpha: style == .screen ? 0.75 : 1).cgColor
        border.lineWidth = style == .screen ? 2.5 : 2
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if style == .region {
            border.lineDashPattern = [8, 6]
            if !reduceMotion {
                let march = CABasicAnimation(keyPath: "lineDashPhase")
                march.fromValue = 0
                march.toValue = -14
                march.duration = 0.6
                march.repeatCount = .infinity
                border.add(march, forKey: "march")
            }
        } else if !reduceMotion {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.35
            pulse.duration = 1.2
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            border.add(pulse, forKey: "pulse")
        }
        view.layer?.addSublayer(border)
        panel.contentView = view
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}

protocol RecordingServicing: AnyObject {
    func start(filter: SCContentFilter, configuration: SCStreamConfiguration, outputURL: URL,
               includeSystemAudio: Bool, includeMicrophone: Bool) async throws
    func stop() async throws -> URL
    func cancel() async
    func pause() -> Bool
    func resume() -> Bool
}

extension ScreenRecordingService: RecordingServicing {}
