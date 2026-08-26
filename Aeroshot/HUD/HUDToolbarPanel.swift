import AppKit
import Combine
import SwiftUI

@MainActor
final class HUDToolbarPanel {
    private var panel: NSPanel?
    private(set) var model: HUDToolbarModel?
    private var keyMonitor: Any?
    private var stageObservation: AnyCancellable?
    private weak var targetScreen: NSScreen?
    var onCursorExit: (() -> Void)?

    func show(model: HUDToolbarModel) {
        dismiss()
        self.model = model

        let panelSize = size(for: model.stage)
        let hosting = HUDToolbarHostingView(rootView: HUDToolbarView(model: model))
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: panelSize)

        let panel = HUDPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.contentView = hosting
        self.panel = panel

        let mouse = NSEvent.mouseLocation
        targetScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        installEventMonitor()
        model.onShare = { [weak panel] url in
            guard let view = panel?.contentView else { return }
            NSSharingServicePicker(items: [url]).show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        }
        stageObservation = model.$stage
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] stage in
                self?.movePanel(for: stage, animated: true)
            }

        movePanel(for: model.stage, animated: false)
        panel.orderFrontRegardless()
        refreshCursor(after: panel)
    }

    func setSelected(_ intent: CaptureIntent) {
        withAnimation(.easeOut(duration: 0.14)) {
            model?.selected = intent
        }
    }

    func dismiss() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        stageObservation = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
        onCursorExit?()
    }

    private func movePanel(for stage: HUDCaptureBarStage, animated: Bool) {
        guard let panel, let screen = targetScreen ?? NSScreen.main else { return }
        let size = size(for: stage)
        let visible = screen.visibleFrame
        let origin: NSPoint
        switch stage {
        case .thumbnail, .flying:
            origin = NSPoint(x: visible.maxX - size.width - 24, y: visible.minY + 24)
        default:
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 30)
        }
        let frame = NSRect(origin: origin, size: size)

        guard animated else {
            panel.setFrame(frame, display: true)
            panel.contentView?.frame = NSRect(origin: .zero, size: size)
            refreshCursor(after: panel)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = stage == .flying ? 0.55 : 0.38
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.9, 0.35, 1)
            panel.animator().setFrame(frame, display: true)
            panel.contentView?.animator().setFrameSize(size)
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor [weak self, weak panel] in
                guard let self, let panel else { return }
                self.refreshCursor(after: panel)
            }
        }
    }

    private func size(for stage: HUDCaptureBarStage) -> NSSize {
        switch stage {
        case .idle: NSSize(width: model?.reviewSelection == true ? 710 : 660, height: 64)
        case .countdown: NSSize(width: 214, height: 48)
        case .recording: NSSize(width: 282, height: 48)
        case .saved, .flying: NSSize(width: 508, height: 54)
        case .thumbnail: NSSize(width: 220, height: 154)
        }
    }

    private func installEventMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let model = self?.model else { return event }
            switch event.keyCode {
            case 53:
                model.cancelOrDismiss()
                return nil
            default:
                break
            }
            return event
        }
    }

    private func refreshCursor(after panel: NSPanel) {
        if CursorWindowOwnership.ownsCursor(panel) {
            NSCursor.arrow.set()
        } else {
            onCursorExit?()
        }
    }
}

private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class HUDToolbarHostingView: NSHostingView<HUDToolbarView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        if CursorWindowOwnership.ownsCursor(window) {
            NSCursor.arrow.set()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }
}
