import Combine
import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI

/// Orchestrates area/screen recording to MP4 or GIF with optional click highlighting.
@MainActor
final class RecordingController {

    private unowned let appState: AppState
    private var recorder: (any RecordingServicing)?
    private var gifRecorder: GIFRecordingService?
    private var clickHighlights: ClickHighlightController?
    private var webcamOverlay: WebcamOverlayController?
    private var hudPanel: RecordingHUDPanel?
    private var hudModel: RecordingHUDModel?
    private var timer: Timer?
    private var startDate: Date?
    private var outputURL: URL?
    private var session = RecordingSessionController()
    private var activeSnapshot: RecordingSessionSnapshot?
    private var recoveryManifestURL: URL?
    private var postCaptureController: RecordingPostCaptureWindowController?

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
        Task {
            guard await appState.permissions.ensurePermission() else { return }
            guard let selection = await appState.captureController.selectArea(mode: .area) else { return }
            await beginAreaRecording(with: selection.rect, on: selection.display)
        }
    }

    func beginAreaRecording(with cocoaRect: CGRect, on display: DisplayInfo) async {
        guard !isRecording else { return }
        guard await appState.permissions.ensurePermission() else { return }
        let local = GeometryConversions.cocoaGlobalToDisplayLocalTopLeft(cocoaRect, screen: display.nsScreen)
        await startRecording(display: display, rectInDisplayTopLeft: local)
    }

    func beginScreenRecording() {
        guard !isRecording else { return }
        Task {
            guard await appState.permissions.ensurePermission() else { return }
            do {
                let displays = try await WindowEnumerator.shareableDisplays()
                let mouse = NSEvent.mouseLocation
                let target = displays.first { $0.cocoaFrame.contains(mouse) } ?? displays.first
                guard let target else { return }
                let rect = CGRect(x: 0, y: 0,
                                  width: target.scDisplay.width,
                                  height: target.scDisplay.height)
                await startRecording(display: target, rectInDisplayTopLeft: rect)
            } catch {
                NSLog("Screen recording setup failed: \(error)")
            }
        }
    }

    private func startRecording(display: DisplayInfo, rectInDisplayTopLeft: CGRect) async {
        let settings = appState.settings

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
                audio: RecordingAudioConfiguration(capturesSystemAudio: settings.recordSystemAudio,
                                                   microphoneDeviceID: settings.recordMicrophone ? "default" : nil),
                webcam: settings.showWebcamOverlay ? RecordingWebcamConfiguration(deviceID: "default") : nil,
                countdown: RecordingCountdown(seconds: 0),
                events: RecordingEventConfiguration(capturesClicks: settings.highlightClicksDuringRecording),
                requiredSpaceEstimateBytes: 512 * 1_024 * 1_024
            )
            _ = try session.handle(.beginPreflight(configuration: configuration, sessionID: UUID(), at: Date()))
            let readiness = RecordingPreflightReadiness(
                permissionStatuses: [.screenRecording: .granted, .microphone: .granted, .camera: .granted],
                availableSpaceBytes: availableSpace
            )
            let preflight = RecordingPreflightModel(configuration: configuration, readiness: readiness)
            guard preflight.isReady else {
                _ = try session.handle(.resolvePreflight(readiness))
                ToastController.shared.show(preflight.blockingMessage ?? "Recording preflight failed", symbol: "externaldrive.badge.exclamationmark")
                return
            }
            guard try session.handle(.resolvePreflight(readiness)) == .beginCapture else { return }
            if case .recording(let snapshot) = session.state { activeSnapshot = snapshot }
        } catch {
            NSLog("Recording preflight failed: \(error)")
            return
        }
        appState.isRecording = true

        let config = SCStreamConfiguration()
        config.sourceRect = rectInDisplayTopLeft
        config.width = pixelWidth
        config.height = pixelHeight
        config.showsCursor = true
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 5
        config.captureResolution = .best

        outputURL = url
        persistRecovery(lifecycle: .recording)
        showHUD()
        try? await Task.sleep(for: .milliseconds(80))

        if settings.highlightClicksDuringRecording {
            let highlights = ClickHighlightController()
            highlights.start()
            clickHighlights = highlights
        }

        if settings.showWebcamOverlay {
            let webcam = WebcamOverlayController()
            webcam.start()
            webcamOverlay = webcam
        }

        do {
            var includeMicrophone = settings.recordMicrophone && settings.recordingFormat == .mp4
            if includeMicrophone {
                let granted = await Self.requestMicrophoneAccess()
                if !granted {
                    ToastController.shared.show("Microphone access is required", symbol: "mic.slash")
                    includeMicrophone = false
                }
            }
            let excluded = await WindowEnumerator.ownWindows()
            let filter = ScreenCaptureService.filter(for: display, excludingWindows: excluded)
            switch settings.recordingFormat {
            case .mp4:
                let service: any RecordingServicing = ScreenRecordingService()
                recorder = service
                try await service.start(filter: filter,
                                      configuration: config,
                                      outputURL: url,
                                      includeSystemAudio: settings.recordSystemAudio,
                                      includeMicrophone: includeMicrophone)
            case .gif:
                let service = GIFRecordingService(maxFrames: settings.gifMaxFrames)
                gifRecorder = service
                try await service.start(filter: filter, configuration: config, fps: settings.gifFPS)
            }
            startDate = Date()
            startElapsedTimer()
            hudModel?.statusMessage = "Recording…"
            ToastController.shared.show("Recording started", symbol: "record.circle")
        } catch {
            NSLog("Recording failed to start: \(error)")
            hudModel?.statusMessage = "Failed to start recording."
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
                hudModel?.isPaused = true
                hudModel?.statusMessage = "Paused"
                persistRecovery(lifecycle: .paused)
            case .paused:
                guard recorder?.resume() == true else { return }
                _ = try session.handle(.resume)
                startElapsedTimer()
                hudModel?.isPaused = false
                hudModel?.statusMessage = "Recording…"
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
                hudModel?.statusMessage = error.localizedDescription
                // Keep HUD visible briefly so the user sees the error.
                try? await Task.sleep(for: .seconds(2))
            }
        } else {
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
        hudPanel?.orderOut(nil)
        hudPanel = nil
        hudModel = nil
        startDate = nil

        if let savedURL {
            if appState.settings.addRecordingsToHistory {
                _ = appState.history.add(recordingFrom: savedURL, durationSeconds: max(savedDuration, 1))
            }
            await appState.uploadIfNeeded(fileURL: savedURL)
            ToastController.shared.show("Recording saved", symbol: "square.and.arrow.down")
            let postCapture = RecordingPostCaptureWindowController(outputURL: savedURL)
            postCapture.showWindow(nil)
            postCapture.window?.center()
            postCaptureController = postCapture
            appState.settings.playSelectedSound()
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
        let mins = elapsed / 60
        let secs = elapsed % 60
        hudModel?.elapsed = String(format: "%d:%02d", mins, secs)
    }

    // MARK: - HUD

    private func showHUD() {
        let model = RecordingHUDModel()
        model.onStop = { [weak self] in Task { await self?.stopRecording(save: true) } }
        model.onCancel = { [weak self] in Task { await self?.stopRecording(save: false) } }
        model.onPauseResume = { [weak self] in self?.togglePause() }
        hudModel = model

        let hosting = NSHostingView(rootView: RecordingHUDView(model: model))
        hosting.sizingOptions = []
        hosting.frame = CGRect(x: 0, y: 0, width: 220, height: 88)

        let panel = RecordingHUDPanel(contentRect: hosting.frame,
                                      styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered,
                                      defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.contentView = hosting

        let vf = NSScreen.main?.visibleFrame ?? .zero
        panel.setFrameOrigin(NSPoint(x: vf.maxX - 236, y: vf.maxY - 104))
        panel.makeKeyAndOrderFront(nil)
        hudPanel = panel
    }

    private static func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

final class RecordingHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class RecordingHUDModel: ObservableObject {
    @Published var elapsed = "0:00"
    @Published var statusMessage = "Starting…"
    @Published var isPaused = false
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?
    var onPauseResume: (() -> Void)?
}

struct RecordingHUDView: View {
    @ObservedObject var model: RecordingHUDModel

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 11, weight: .semibold))
                Text("Recording")
                    .font(.headline)
                Spacer()
                Text(model.elapsed)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button("Cancel", role: .cancel) { model.onCancel?() }
                Spacer()
                Button(model.isPaused ? "Resume" : "Pause") { model.onPauseResume?() }
                Button("Stop & Save") { model.onStop?() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .frame(width: 220, height: 88)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
