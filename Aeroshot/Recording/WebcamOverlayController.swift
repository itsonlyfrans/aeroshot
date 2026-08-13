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

@MainActor
final class WebcamOverlayController: NSObject {
    private enum BubbleSize: String {
        case small = "S"
        case medium = "M"
        case large = "L"

        var points: CGFloat {
            switch self {
            case .small: 76
            case .medium: 104
            case .large: 140
            }
        }
    }

    private var panel: NSPanel?
    private var controlsPanel: NSPanel?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var captureSession: AVCaptureSession?
    private var hideControlsTask: Task<Void, Never>?
    private let sessionQueue = DispatchQueue(label: "com.aeroshot.webcam.session")
    private var bubbleSize = BubbleSize(
        rawValue: UserDefaults.standard.string(forKey: "webcamBubbleSize") ?? ""
    ) ?? .medium

    var windowID: CGWindowID? {
        panel.map { CGWindowID($0.windowNumber) }
    }

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
        hideControlsTask?.cancel()
        hideControlsTask = nil
        controlsPanel?.orderOut(nil)
        controlsPanel = nil
        let session = captureSession
        captureSession = nil
        previewLayer = nil
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

        let size = bubbleSize.points
        let hoverView = WebcamHoverView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        hoverView.wantsLayer = true
        hoverView.layer?.cornerRadius = size / 2
        hoverView.layer?.masksToBounds = true
        hoverView.layer?.borderWidth = 2
        hoverView.layer?.borderColor = NSColor(red: 1, green: 0.541, blue: 0.420, alpha: 0.6).cgColor
        hoverView.onHover = { [weak self] hovering in
            hovering ? self?.showSizeControls() : self?.scheduleControlsDismiss()
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = hoverView.bounds
        previewLayer.cornerRadius = size / 2
        hoverView.layer?.insertSublayer(previewLayer, at: 0)
        self.previewLayer = previewLayer

        let panel = NSPanel(
            contentRect: hoverView.bounds,
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
        panel.contentView = hoverView
        self.panel = panel
        updateBubbleFrame(animated: false)
        panel.orderFrontRegardless()

        sessionQueue.async {
            WebcamCaptureSessionStarter(session: session).start()
        }
    }

    private func showSizeControls() {
        hideControlsTask?.cancel()
        hideControlsTask = nil
        if let controlsPanel {
            positionControls(controlsPanel)
            controlsPanel.orderFrontRegardless()
            return
        }

        let effect = WebcamHoverVisualEffectView(frame: NSRect(x: 0, y: 0, width: 106, height: 30))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 9
        effect.onHover = { [weak self] hovering in
            hovering ? self?.hideControlsTask?.cancel() : self?.scheduleControlsDismiss()
        }

        let control = NSSegmentedControl(labels: ["S", "M", "L"], trackingMode: .selectOne, target: self, action: #selector(sizeChanged(_:)))
        control.segmentStyle = .rounded
        control.selectedSegment = [BubbleSize.small, .medium, .large].firstIndex(of: bubbleSize) ?? 1
        control.frame = NSRect(x: 4, y: 3, width: 98, height: 24)
        control.setAccessibilityLabel("Camera size")
        effect.addSubview(control)

        let panel = NSPanel(
            contentRect: effect.bounds,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = effect
        controlsPanel = panel
        positionControls(panel)
        panel.orderFrontRegardless()
    }

    private func scheduleControlsDismiss() {
        hideControlsTask?.cancel()
        hideControlsTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.controlsPanel?.orderOut(nil)
        }
    }

    @objc private func sizeChanged(_ sender: NSSegmentedControl) {
        let sizes: [BubbleSize] = [.small, .medium, .large]
        guard sizes.indices.contains(sender.selectedSegment) else { return }
        bubbleSize = sizes[sender.selectedSegment]
        UserDefaults.standard.set(bubbleSize.rawValue, forKey: "webcamBubbleSize")
        updateBubbleFrame(animated: true)
    }

    private func updateBubbleFrame(animated: Bool) {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let points = bubbleSize.points
        let frame = NSRect(
            x: screen.visibleFrame.minX + 26,
            y: screen.visibleFrame.minY + 104,
            width: points,
            height: points
        )
        let updates: @MainActor @Sendable () -> Void = { [weak self, weak panel] in
            guard let self, let panel else { return }
            panel.setFrame(frame, display: true)
            panel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
            panel.contentView?.layer?.cornerRadius = points / 2
            self.previewLayer?.frame = NSRect(origin: .zero, size: frame.size)
            self.previewLayer?.cornerRadius = points / 2
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().setFrame(frame, display: true)
            } completionHandler: {
                Task { @MainActor in updates() }
            }
        } else {
            updates()
        }
        if let controlsPanel { positionControls(controlsPanel) }
    }

    private func positionControls(_ controls: NSPanel) {
        guard let panel else { return }
        controls.setFrameOrigin(NSPoint(
            x: panel.frame.midX - controls.frame.width / 2,
            y: panel.frame.maxY + 8
        ))
    }
}

private class WebcamHoverView: NSView {
    var onHover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }
}

private final class WebcamHoverVisualEffectView: NSVisualEffectView {
    var onHover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }
}
