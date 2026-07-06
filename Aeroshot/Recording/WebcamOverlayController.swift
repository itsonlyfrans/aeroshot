import AppKit
@preconcurrency import AVFoundation

private nonisolated struct WebcamCaptureSessionStarter: @unchecked Sendable {
    let session: AVCaptureSession

    nonisolated func start() {
        guard !session.isRunning else { return }
        session.startRunning()
    }

    nonisolated func stop() {
        guard session.isRunning else { return }
        session.stopRunning()
    }
}

/// Draggable webcam bubble captured into screen recordings (same overlay pattern as click highlights).
@MainActor
final class WebcamOverlayController {
    private var panel: NSPanel?
    private var captureSession: AVCaptureSession?
    private let sessionQueue = DispatchQueue(label: "com.aeroshot.webcam.session")

    func start() {
        stop()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            presentOverlay()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                MainActor.assumeIsolated {
                    guard granted else { return }
                    self?.presentOverlay()
                }
            }
        default:
            ToastController.shared.show("Camera access required for webcam overlay", symbol: "video.slash")
        }
    }

    func stop() {
        let session = captureSession
        captureSession = nil
        panel?.orderOut(nil)
        panel = nil
        if let session {
            sessionQueue.async {
                WebcamCaptureSessionStarter(session: session).stop()
            }
        }
    }

    private func presentOverlay() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        let session = AVCaptureSession()
        session.sessionPreset = .medium
        guard session.canAddInput(input) else { return }
        session.addInput(input)
        captureSession = session

        let preview = NSView(frame: NSRect(x: 0, y: 0, width: 160, height: 160))
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = preview.bounds
        layer.cornerRadius = 80
        layer.masksToBounds = true
        preview.layer = layer
        preview.wantsLayer = true

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 168, height: 168),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false

        let container = NSView(frame: panel.contentView!.bounds)
        preview.frame = NSRect(x: 4, y: 4, width: 160, height: 160)
        container.addSubview(preview)
        panel.contentView = container

        if let vf = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: vf.maxX - 188, y: vf.minY + 24))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        sessionQueue.async {
            WebcamCaptureSessionStarter(session: session).start()
        }
    }
}
