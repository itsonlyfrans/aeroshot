import Combine
import AppKit
import ScreenCaptureKit
import SwiftUI

/// Orchestrates area/screen recording to MP4 or GIF with optional click highlighting.
@MainActor
final class RecordingController {

    private unowned let appState: AppState
    private var recorder: ScreenRecordingService?
    private var gifRecorder: GIFRecordingService?
    private var clickHighlights: ClickHighlightController?
    private var hudPanel: RecordingHUDPanel?
    private var hudModel: RecordingHUDModel?
    private var timer: Timer?
    private var startDate: Date?
    private var outputURL: URL?
    private var isRecording = false

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
        isRecording = true
        let settings = appState.settings

        let rawWidth = Int((rectInDisplayTopLeft.width * display.scale).rounded())
        let rawHeight = Int((rectInDisplayTopLeft.height * display.scale).rounded())
        let (pixelWidth, pixelHeight) = ScreenRecordingService.evenPixelSize(width: rawWidth, height: rawHeight)

        let config = SCStreamConfiguration()
        config.sourceRect = rectInDisplayTopLeft
        config.width = pixelWidth
        config.height = pixelHeight
        config.showsCursor = true
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 5
        config.captureResolution = .best

        let url = settings.newRecordingURL()
        outputURL = url
        showHUD()
        try? await Task.sleep(for: .milliseconds(80))

        if settings.highlightClicksDuringRecording {
            let highlights = ClickHighlightController()
            highlights.start()
            clickHighlights = highlights
        }

        do {
            let excluded = await WindowEnumerator.ownWindows()
            let filter = ScreenCaptureService.filter(for: display, excludingWindows: excluded)
            switch settings.recordingFormat {
            case .mp4:
                let service = ScreenRecordingService()
                recorder = service
                try await service.start(filter: filter,
                                      configuration: config,
                                      outputURL: url,
                                      includeSystemAudio: settings.recordSystemAudio)
            case .gif:
                let service = GIFRecordingService(maxFrames: settings.gifMaxFrames)
                gifRecorder = service
                try await service.start(filter: filter, configuration: config, fps: settings.gifFPS)
            }
            startDate = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.updateElapsed() }
            }
            hudModel?.statusMessage = "Recording…"
        } catch {
            NSLog("Recording failed to start: \(error)")
            hudModel?.statusMessage = "Failed to start recording."
            await stopRecording(save: false)
        }
    }

    private func stopRecording(save: Bool) async {
        timer?.invalidate()
        timer = nil
        clickHighlights?.stop()
        clickHighlights = nil

        var savedURL: URL?
        if save {
            do {
                if let recorder {
                    savedURL = try await recorder.stop()
                    self.recorder = nil
                } else if let gifRecorder, let url = outputURL {
                    savedURL = try await gifRecorder.stop(outputURL: url,
                                                          frameDelay: 1.0 / Double(appState.settings.gifFPS))
                    self.gifRecorder = nil
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
            if let recorder {
                await recorder.cancel()
                self.recorder = nil
            }
            gifRecorder = nil
            if let url = outputURL {
                try? FileManager.default.removeItem(at: url)
            }
        }

        isRecording = false
        outputURL = nil
        hudPanel?.orderOut(nil)
        hudPanel = nil
        hudModel = nil
        startDate = nil

        if let savedURL {
            NSWorkspace.shared.activateFileViewerSelecting([savedURL])
            if appState.settings.playCaptureSound {
                NSSound(named: "Pop")?.play()
            }
        }
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
        hudModel = model

        let hosting = NSHostingView(rootView: RecordingHUDView(model: model))
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
}

final class RecordingHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class RecordingHUDModel: ObservableObject {
    @Published var elapsed = "0:00"
    @Published var statusMessage = "Starting…"
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?
}

struct RecordingHUDView: View {
    @ObservedObject var model: RecordingHUDModel

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Circle().fill(.red).frame(width: 10, height: 10)
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
                Button("Discard", role: .cancel) { model.onCancel?() }
                Spacer()
                Button("Stop & Save") { model.onStop?() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .frame(width: 220, height: 88)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
