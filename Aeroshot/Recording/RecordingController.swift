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
    private var recordingTimeline: RecordingMediaTimeline?
    private var outputURL: URL?
    private var publicationURL: URL?
    private var session = RecordingSessionController()
    private var activeSnapshot: RecordingSessionSnapshot?
    private var recoveryArtifact: RecordingRecoveryArtifact?
    private var recoveryWorkspaceURL: URL?
    private var captureWindowOwner: CaptureWindowRestorationOwner?
    private let startupGate = CaptureStartGate<Void>()
    private var startupGeneration: Int?
    private var startupCaptureWindowOwner: CaptureWindowRestorationOwner?
    private var terminalOperation: Task<Bool, Never>?
    private var isFinalizing = false

    private var isRecording: Bool {
        Self.hasActiveSession(session.state)
    }

    static func hasActiveSession(_ state: RecordingSessionState) -> Bool {
        switch state {
        case .preflighting, .countdown, .recording, .paused, .stopping: true
        default: false
        }
    }

    private func beginStartup(captureWindowOwner: CaptureWindowRestorationOwner?) -> Int? {
        guard !isRecording, !isFinalizing,
              captureWindowOwner != nil ||
                (!appState.captureController.isPresentingOverlay && !appState.allInOneController.isPresenting),
              let generation = startupGate.tryBeginStartOperation()
        else { return nil }
        startupGeneration = generation
        startupCaptureWindowOwner = captureWindowOwner
        appState.beginRecordingCaptureWindowOwnership(captureWindowOwner)
        return generation
    }

    private func ownsStartup(_ generation: Int) -> Bool {
        startupGeneration == generation && startupGate.isActive(for: generation)
    }

    private func finishStartup(_ generation: Int) {
        guard ownsStartup(generation) else { return }
        let owner = startupCaptureWindowOwner
        _ = startupGate.invalidate()
        startupGeneration = nil
        startupCaptureWindowOwner = nil
        appState.restoreCaptureWindows(owner: owner)
    }

    private func releaseStartup() {
        guard let generation = startupGeneration, ownsStartup(generation) else { return }
        _ = startupGate.invalidate()
        startupGeneration = nil
        startupCaptureWindowOwner = nil
    }

    private func cancelStartup() -> CaptureWindowRestorationOwner? {
        guard let generation = startupGeneration, ownsStartup(generation) else { return nil }
        let owner = startupCaptureWindowOwner
        _ = startupGate.invalidate()
        startupGeneration = nil
        startupCaptureWindowOwner = nil
        return owner
    }

    init(
        appState: AppState,
        session: RecordingSessionController = RecordingSessionController()
    ) {
        self.appState = appState
        self.session = session
    }

    @discardableResult
    func beginAreaRecording() -> Task<Void, Never> {
        let options = recordingOptions
        return Task { [weak self] in
            guard let self, let generation = beginStartup(captureWindowOwner: nil) else { return }
            var captureWindowOwner: CaptureWindowRestorationOwner?
            defer {
                startupGate.startOperationDidFinish()
                finishStartup(generation)
            }
            guard await appState.permissions.ensurePermission() else { return }
            guard let selection = await appState.captureController.selectArea(mode: .area) else { return }
            captureWindowOwner = selection.captureWindowOwner
            guard ownsStartup(generation) else {
                appState.restoreCaptureWindows(owner: captureWindowOwner)
                return
            }
            startupCaptureWindowOwner = captureWindowOwner
            appState.beginRecordingCaptureWindowOwnership(captureWindowOwner)
            await beginAreaRecording(
                with: selection.rect,
                on: selection.display,
                options: options,
                captureBar: nil,
                captureWindowOwner: captureWindowOwner,
                startupGeneration: generation
            )
        }
    }

    func beginAreaRecording(
        with cocoaRect: CGRect,
        on display: DisplayInfo,
        captureWindowOwner: CaptureWindowRestorationOwner? = nil
    ) async {
        await beginAreaRecording(
            with: cocoaRect,
            on: display,
            options: recordingOptions,
            captureBar: nil,
            captureWindowOwner: captureWindowOwner,
            startupGeneration: nil
        )
    }

    func beginAreaRecording(
        with cocoaRect: CGRect,
        on display: DisplayInfo,
        options: HUDRecordingOptions,
        captureBar: HUDToolbarPanel?,
        captureWindowOwner: CaptureWindowRestorationOwner? = nil,
        startupGeneration: Int? = nil
    ) async {
        let ownsStartOperation = startupGeneration == nil
        let generation = startupGeneration ?? beginStartup(captureWindowOwner: captureWindowOwner)
        guard let generation else { return }
        defer {
            if ownsStartOperation { startupGate.startOperationDidFinish() }
            finishStartup(generation)
        }
        guard await appState.permissions.ensurePermission() else { return }
        guard ownsStartup(generation) else { return }
        let local = GeometryConversions.cocoaGlobalToDisplayLocalTopLeft(cocoaRect, screen: display.nsScreen)
        await startRecording(
            display: display,
            rectInDisplayTopLeft: local,
            selectedIntent: captureBar?.model?.selected ?? .area,
            options: options,
            captureBar: captureBar,
            captureWindowOwner: captureWindowOwner,
            startupGeneration: generation
        )
    }

    func beginScreenRecording() {
        beginScreenRecording(options: recordingOptions, captureBar: nil)
    }

    func beginScreenRecording(
        options: HUDRecordingOptions,
        captureBar: HUDToolbarPanel?,
        captureWindowOwner: CaptureWindowRestorationOwner? = nil
    ) {
        beginScreenRecording(
            on: nil,
            options: options,
            captureBar: captureBar,
            captureWindowOwner: captureWindowOwner
        )
    }

    func beginScreenRecording(
        on display: DisplayInfo,
        captureWindowOwner: CaptureWindowRestorationOwner? = nil
    ) {
        beginScreenRecording(
            on: display,
            options: recordingOptions,
            captureBar: nil,
            captureWindowOwner: captureWindowOwner
        )
    }

    func beginScreenRecording(
        on selectedDisplay: DisplayInfo,
        options: HUDRecordingOptions,
        captureBar: HUDToolbarPanel?,
        captureWindowOwner: CaptureWindowRestorationOwner? = nil
    ) {
        beginScreenRecording(
            on: Optional(selectedDisplay),
            options: options,
            captureBar: captureBar,
            captureWindowOwner: captureWindowOwner
        )
    }

    private func beginScreenRecording(
        on selectedDisplay: DisplayInfo?,
        options: HUDRecordingOptions,
        captureBar: HUDToolbarPanel?,
        captureWindowOwner: CaptureWindowRestorationOwner?
    ) {
        Task { [weak self] in
            guard let self, let generation = beginStartup(captureWindowOwner: captureWindowOwner) else { return }
            defer {
                startupGate.startOperationDidFinish()
                finishStartup(generation)
            }
            guard await appState.permissions.ensurePermission() else { return }
            guard ownsStartup(generation) else { return }
            do {
                let displays = try await WindowEnumerator.shareableDisplays()
                guard ownsStartup(generation) else { return }
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
                    captureBar: captureBar,
                    captureWindowOwner: captureWindowOwner,
                    startupGeneration: generation
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
        captureBar existingCaptureBar: HUDToolbarPanel?,
        captureWindowOwner: CaptureWindowRestorationOwner?,
        startupGeneration: Int
    ) async {
        guard ownsStartup(startupGeneration) else { return }
        guard existingCaptureBar != nil || !appState.allInOneController.isPresenting else {
            ToastController.shared.show("Finish All-in-One first", symbol: "rectangle.dashed")
            return
        }
        let settings = appState.settings
        let supportsAudio = settings.recordingFormat == .mp4
        if !isRecording {
            session = RecordingSessionController()
            terminalOperation = nil
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
        do {
            let availableSpace: Int64
            try FileManager.default.createDirectory(at: Self.recoveryDirectory, withIntermediateDirectories: true)
            availableSpace = min(
                Self.availableSpace(in: Self.recoveryDirectory),
                Self.availableSpace(forFileAt: url)
            )
            let configuration = try RecordingSessionConfiguration(
                source: .region(displayID: "\(display.scDisplay.displayID)", x: Int(rectInDisplayTopLeft.minX),
                                y: Int(rectInDisplayTopLeft.minY), width: Int(rectInDisplayTopLeft.width),
                                height: Int(rectInDisplayTopLeft.height)),
                dimensions: RecordingDimensions(width: pixelWidth, height: pixelHeight),
                frameRate: RecordingFrameRate(framesPerSecond: 30),
                cursorMode: settings.highlightClicksDuringRecording ? .visibleWithClickEffects : .visible,
                audio: RecordingAudioConfiguration(
                    capturesSystemAudio: supportsAudio && options.systemAudioEnabled,
                    microphoneDeviceID: supportsAudio && options.microphoneEnabled
                        ? (settings.recordingMicrophoneDeviceID.isEmpty ? "default" : settings.recordingMicrophoneDeviceID)
                        : nil
                ),
                webcam: options.cameraEnabled ? RecordingWebcamConfiguration(deviceID: "default") : nil,
                countdown: RecordingCountdown(seconds: options.countdownSeconds),
                events: RecordingEventConfiguration(capturesClicks: settings.highlightClicksDuringRecording),
                requiredSpaceEstimateBytes: 512 * 1_024 * 1_024
            )
            let microphoneGranted = supportsAudio && options.microphoneEnabled
                ? await Self.requestMicrophoneAccess()
                : true
            let cameraGranted = options.cameraEnabled
                ? await Self.requestCameraAccess()
                : true
            guard ownsStartup(startupGeneration) else { return }
            let readiness = RecordingPreflightReadiness(
                permissionStatuses: [
                    .screenRecording: .granted,
                    .microphone: microphoneGranted ? .granted : .denied,
                    .camera: cameraGranted ? .granted : .denied
                ],
                availableSpaceBytes: availableSpace
            )
            guard let effect = try resolvePreflight(configuration: configuration, readiness: readiness) else { return }
            appState.isRecording = true
            switch session.state {
            case .countdown(let snapshot, _), .recording(let snapshot):
                activeSnapshot = snapshot
            default:
                break
            }
            if let snapshot = activeSnapshot {
                outputURL = try prepareRecoveryWorkspace(for: snapshot, intendedURL: url)
                publicationURL = url
            } else {
                outputURL = url
                publicationURL = nil
            }
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
                guard await runCountdown(total: options.countdownSeconds) else {
                    if isRecording { await stopRecording(save: false) }
                    return
                }
                guard ownsStartup(startupGeneration) else { return }
            } else {
                guard effect == .beginCapture else { return }
                captureBarModel?.showRecording(startedFromCountdown: false)
            }
        } catch {
            NSLog("Recording preflight failed: \(error)")
            captureBarModel?.blockingMessage = error.localizedDescription
            await stopRecording(save: false)
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
        guard ownsStartup(startupGeneration) else { return }

        if settings.highlightClicksDuringRecording {
            let highlights = ClickHighlightController()
            highlights.start()
            clickHighlights = highlights
        }

        do {
            var includeMicrophone = options.microphoneEnabled && settings.recordingFormat == .mp4
            if includeMicrophone {
                let granted = await Self.requestMicrophoneAccess()
                guard ownsStartup(startupGeneration) else { return }
                if !granted {
                    ToastController.shared.show("Microphone access is required", symbol: "mic.slash")
                    includeMicrophone = false
                }
            }
            let webcamWindowID = webcamOverlay?.windowID
            let excluded = await WindowEnumerator.ownWindows().filter { window in
                window.windowID != webcamWindowID
            }
            guard ownsStartup(startupGeneration) else { return }
            let filter = ScreenCaptureService.filter(for: display, excludingWindows: excluded)
            switch settings.recordingFormat {
            case .mp4:
                guard ownsStartup(startupGeneration) else { return }
                let mediaTimeline = RecordingMediaTimeline()
                let concreteService = ScreenRecordingService(mediaTimeline: mediaTimeline)
                recordingTimeline = mediaTimeline
                concreteService.microphoneDeviceID = settings.recordingMicrophoneDeviceID.isEmpty ? nil : settings.recordingMicrophoneDeviceID
                concreteService.timelineResumedHandler = { [weak self] in
                    Task { @MainActor [weak self] in self?.effectEventRecorder?.resume() }
                }
                configureUnexpectedStop(for: concreteService)
                concreteService.audioLevelHandler = { [weak self] source, value in
                    Task { @MainActor [weak self] in
                        switch source {
                        case .system: self?.captureBarModel?.systemAudioLevel = value
                        case .microphone: self?.captureBarModel?.microphoneLevel = value
                        }
                    }
                }
                let service: any RecordingServicing = concreteService
                guard ownsStartup(startupGeneration) else { return }
                recorder = service
                guard ownsStartup(startupGeneration) else {
                    self.recorder = nil
                    return
                }
                guard let outputURL else { return }
                try await service.start(filter: filter,
                                      configuration: config,
                                      outputURL: outputURL,
                                      includeSystemAudio: options.systemAudioEnabled,
                                      includeMicrophone: includeMicrophone)
            case .gif:
                guard ownsStartup(startupGeneration) else { return }
                let service = GIFRecordingService(maxFrames: settings.gifMaxFrames)
                configureUnexpectedStop(for: service)
                guard ownsStartup(startupGeneration) else { return }
                gifRecorder = service
                guard ownsStartup(startupGeneration) else {
                    self.gifRecorder = nil
                    return
                }
                try await service.start(filter: filter, configuration: config, fps: settings.gifFPS)
            }
            guard ownsStartup(startupGeneration) else {
                if let recorder { await recorder.cancel(); self.recorder = nil }
                if let gifRecorder { await gifRecorder.cancel(); self.gifRecorder = nil }
                return
            }
            recordingDidStart(captureWindowOwner: captureWindowOwner)
            startDate = Date()
            if settings.recordingFormat == .mp4, let screenRecorder = recorder as? ScreenRecordingService {
                let displayFrame = display.cocoaFrame
                let captureRect = rectInDisplayTopLeft
                let effects = RecordingEffectEventRecorder(timeline: screenRecorder.mediaTimeline) { point in
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

    private func resolvePreflight(
        configuration: RecordingSessionConfiguration,
        readiness: RecordingPreflightReadiness
    ) throws -> RecordingSessionEffect? {
        _ = try session.handle(.beginPreflight(configuration: configuration, sessionID: UUID(), at: Date()))
        let preflight = RecordingPreflightModel(configuration: configuration, readiness: readiness)
        guard preflight.isReady else {
            _ = try session.handle(.resolvePreflight(readiness))
            captureBarModel?.blockingMessage = preflight.blockingMessage ?? "Recording preflight failed"
            return nil
        }
        return try session.handle(.resolvePreflight(readiness))
    }

#if DEBUG
    func runPreflightForTesting(
        configuration: RecordingSessionConfiguration,
        readiness: RecordingPreflightReadiness,
        captureWindowOwner: CaptureWindowRestorationOwner
    ) async throws -> Bool {
        appState.beginRecordingCaptureWindowOwnership(captureWindowOwner)
        defer {
            if !isRecording { appState.restoreCaptureWindows(owner: captureWindowOwner) }
        }
        return try resolvePreflight(configuration: configuration, readiness: readiness) != nil
    }
#endif

    private func togglePause() {
        do {
            switch session.state {
            case .recording:
                guard recorder?.pause() == true else { return }
                _ = try session.handle(.pause)
                effectEventRecorder?.pause()
                timer?.invalidate()
                timer = nil
                captureBarModel?.isPaused = true
                persistRecovery(lifecycle: .paused)
            case .paused:
                guard recorder?.resume() == true else { return }
                _ = try session.handle(.resume)
                effectEventRecorder?.resume()
                startElapsedTimer()
                captureBarModel?.isPaused = false
                persistRecovery(lifecycle: .recording)
            default: break
            }
        } catch { NSLog("Recording pause transition failed: \(error)") }
    }

    func recordingDidStart(captureWindowOwner: CaptureWindowRestorationOwner?) {
        self.captureWindowOwner = captureWindowOwner
        appState.isRecording = true
        releaseStartup()
    }

    private func configureUnexpectedStop(for service: ScreenRecordingService) {
        service.unexpectedStopHandler = { [weak self, weak service] in
            Task { @MainActor in
                guard let self, let service, self.recorder === service else { return }
                self.captureBarModel?.blockingMessage = "Recording interrupted. Finalizing what was captured…"
                await self.stopRecording(save: true)
            }
        }
    }

    private func configureUnexpectedStop(for service: GIFRecordingService) {
        service.unexpectedStopHandler = { [weak self, weak service] in
            Task { @MainActor in
                guard let self, let service, self.gifRecorder === service else { return }
                self.captureBarModel?.blockingMessage = "Recording interrupted. Finalizing what was captured…"
                await self.stopRecording(save: true)
            }
        }
    }

#if DEBUG
    func installRecordingForTesting(recorder: any RecordingServicing, outputURL: URL) {
        self.recorder = recorder
        if let service = recorder as? ScreenRecordingService { configureUnexpectedStop(for: service) }
        self.outputURL = outputURL
        self.startDate = Date()
        appState.isRecording = true
    }

    func installGIFRecordingForTesting(service: GIFRecordingService, outputURL: URL) {
        gifRecorder = service
        configureUnexpectedStop(for: service)
        self.outputURL = outputURL
        startDate = Date()
        appState.isRecording = true
    }
#endif

    @discardableResult
    func stopRecording(save: Bool) async -> Bool {
        if let terminalOperation {
            return await terminalOperation.value
        }
        let operation = Task { @MainActor [weak self] in
            guard let self else { return false }
            return await self.finishRecording(save: save)
        }
        terminalOperation = operation
        return await operation.value
    }

    private func finishRecording(save: Bool) async -> Bool {
        isFinalizing = true
        let startupCaptureWindowOwner = cancelStartup()
        defer {
            isFinalizing = false
            effectEventRecorder?.stop()
            effectEventRecorder = nil
            appState.restoreCaptureWindows(owner: captureWindowOwner ?? startupCaptureWindowOwner)
            captureWindowOwner = nil
        }
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
                if recorder != nil || gifRecorder != nil { persistRecovery(lifecycle: .stopping) }
                let workspaceURL: URL?
                if let recorder {
                    workspaceURL = try await recorder.stop()
                    self.recorder = nil
                } else if let gifRecorder, let url = outputURL {
                    workspaceURL = try await gifRecorder.stop(
                        outputURL: url,
                        frameDelay: 1.0 / Double(appState.settings.gifFPS)
                    )
                    self.gifRecorder = nil
                } else {
                    workspaceURL = nil
                }
                if let workspaceURL, let publicationURL {
                    if let effectEventRecorder {
                        try effectEventRecorder.stopAndWrite(beside: workspaceURL)
                        self.effectEventRecorder = nil
                        try Self.publishWorkspaceMedia(workspaceURL, to: publicationURL)
                    } else {
                        try FileManager.default.moveItem(at: workspaceURL, to: publicationURL)
                    }
                    savedURL = publicationURL
                } else {
                    savedURL = workspaceURL
                }
                if let finalizedURL = savedURL {
                    try effectEventRecorder?.stopAndWrite(beside: finalizedURL)
                    effectEventRecorder = nil
                    let values = try finalizedURL.resourceValues(forKeys: [.fileSizeKey])
                    let byteCount = Int64(values.fileSize ?? 0)
                    let output = try RecordingCompletedOutput(
                        relativePath: RecordingRelativePath(finalizedURL.lastPathComponent),
                        byteCount: byteCount,
                        durationSeconds: recordingTimeline.map { max(Int($0.mediaDuration()?.seconds ?? 0), 1) }
                            ?? max(startDate.map { Int(Date().timeIntervalSince($0)) } ?? 0, 1),
                        finalizedAt: Date()
                    )
                    _ = try session.handle(.finalize(output: output, isDurable: byteCount > 0))
                    if case .completed = session.state { cleanRecovery() } else { savedURL = nil }
                }
            } catch {
                NSLog("Recording stop failed: \(error)")
                savedURL = nil
                _ = try? session.handle(.fail(.captureFailed(code: "finalization")))
                if recoveryArtifact == nil, let url = outputURL {
                    try? FileManager.default.removeItem(at: url)
                }
                captureBarModel?.blockingMessage = error.localizedDescription
                if captureBarModel != nil {
                    ToastController.shared.show(error.localizedDescription, symbol: "exclamationmark.triangle")
                }
            }
        } else {
            _ = try? session.handle(.cancel)
            if let recorder {
                await recorder.cancel()
                self.recorder = nil
            }
            if let gifRecorder {
                await gifRecorder.cancel()
                self.gifRecorder = nil
            }
            if recoveryArtifact == nil, let url = outputURL {
                try? FileManager.default.removeItem(at: url)
            }
            cleanRecovery()
        }

        if let recorder {
            await recorder.cancel()
            self.recorder = nil
        }
        if let gifRecorder {
            await gifRecorder.cancel()
            self.gifRecorder = nil
        }

        let savedDuration = recordingTimeline.map { max(Int($0.mediaDuration()?.seconds ?? 0), 1) }
            ?? max(startDate.map { Int(Date().timeIntervalSince($0)) } ?? 0, 1)

        appState.isRecording = false
        outputURL = nil
        publicationURL = nil
        startDate = nil
        recordingTimeline = nil
        activeSnapshot = nil

        if let savedURL {
            if appState.settings.addRecordingsToHistory {
                let history = appState.history
                Task {
                    guard await history.add(recordingFrom: savedURL, durationSeconds: savedDuration) != nil else {
                        ToastController.shared.show(
                            "Couldn’t add recording to History.",
                            symbol: "exclamationmark.triangle"
                        )
                        return
                    }
                }
            }
            captureBarModel?.showSaved(
                url: savedURL,
                duration: Self.durationString(seconds: savedDuration)
            )
            appState.settings.playSelectedSound()
            Task { await appState.uploadIfNeeded(fileURL: savedURL) }
        } else {
            dismissCaptureBarAndReturnToIdle()
        }
        return !save || savedURL != nil
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
            let directory = outputURL.deletingLastPathComponent()
            let url = directory.appending(path: "manifest.json")
            try JSONEncoder().encode(manifest).write(to: url, options: .atomic)
            recoveryArtifact = RecordingRecoveryArtifact(
                manifestURL: url,
                manifest: manifest,
                mediaURL: outputURL,
                sessionDirectoryURL: directory
            )
        } catch { NSLog("Could not persist recording recovery manifest: \(error)") }
    }

    private func cleanRecovery() {
        if let recoveryArtifact {
            try? RecordingRecoveryStore(directoryURL: Self.recoveryDirectory).discard(recoveryArtifact)
        } else if let recoveryWorkspaceURL {
            try? FileManager.default.removeItem(at: recoveryWorkspaceURL)
        }
        recoveryArtifact = nil
        recoveryWorkspaceURL = nil
    }

    static var recoveryDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Aeroshot/RecordingRecovery", directoryHint: .isDirectory)
    }

    static func discoverRecoverableSessions(at date: Date = Date()) -> [RecordingRecoveryManifest] {
        RecordingRecoveryStore(directoryURL: recoveryDirectory).discover(at: date)
    }

    static func discoverRecoverableArtifacts(at date: Date = Date()) -> [RecordingRecoveryArtifact] {
        RecordingRecoveryStore(directoryURL: recoveryDirectory).discoverArtifacts(at: date)
    }

    private func prepareRecoveryWorkspace(
        for snapshot: RecordingSessionSnapshot,
        intendedURL: URL
    ) throws -> URL {
        let filename = try RecordingRelativePath(intendedURL.lastPathComponent)
        let directory = Self.recoveryDirectory.appending(
            path: snapshot.sessionID.uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        recoveryWorkspaceURL = directory
        return directory.appending(path: filename.value)
    }

    private static func availableSpace(in directory: URL) -> Int64 {
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    private static func availableSpace(forFileAt url: URL) -> Int64 {
        availableSpace(in: url.deletingLastPathComponent())
    }

    static func publishWorkspaceMedia(_ workspaceURL: URL, to publicationURL: URL) throws {
        let fileManager = FileManager.default
        let workspaceSidecarURL = RecordingEffectEventRecorder.sidecarURL(for: workspaceURL)
        let publicationSidecarURL = RecordingEffectEventRecorder.sidecarURL(for: publicationURL)
        try fileManager.copyItem(at: workspaceSidecarURL, to: publicationSidecarURL)
        do {
            try fileManager.moveItem(at: workspaceURL, to: publicationURL)
        } catch {
            try? fileManager.removeItem(at: publicationSidecarURL)
            throw error
        }
    }

    private func updateElapsed() {
        if let recordingTimeline {
            let elapsed = Int(recordingTimeline.mediaDuration()?.seconds ?? 0)
            captureBarModel?.elapsed = Self.durationString(seconds: elapsed)
            return
        }
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
            model = HUDToolbarModel(
                selected: selectedIntent,
                options: options,
                recordingFormat: appState.settings.recordingFormat
            )
            panel.show(model: model)
        }
        model.options = options
        model.selected = selectedIntent
        model.recordingFormat = appState.settings.recordingFormat
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
        let hadCaptureBar = captureBar != nil
        captureBar?.dismiss()
        captureBar = nil
        captureBarModel = nil
        guard hadCaptureBar else { return }
        let appState = appState
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak appState] in
            appState?.allInOneController.begin()
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
