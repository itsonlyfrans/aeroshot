import AppKit
import SwiftUI

/// Floating toolbar for the All-in-One capture HUD.
@MainActor
final class HUDToolbarPanel {
    private static let panelSize = NSSize(width: 500, height: 58)

    private var panel: NSPanel?
    private var model: HUDToolbarModel?

    func show(selected: CaptureIntent,
              onSelect: @escaping (CaptureIntent) -> Void,
              onCancel: @escaping () -> Void) {
        dismiss()

        let model = HUDToolbarModel(selected: selected)
        model.onSelect = onSelect
        model.onCancel = onCancel
        self.model = model

        let hosting = NSHostingView(rootView: HUDToolbarView(model: model))
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize)

        let panel = HUDPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.contentView = hosting
        self.panel = panel

        DispatchQueue.main.async { [weak self] in
            self?.positionAndShowPanel()
        }
    }

    private func positionAndShowPanel() {
        guard let panel else { return }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let screen {
            let vf = screen.visibleFrame
            let origin = NSPoint(
                x: vf.midX - Self.panelSize.width / 2,
                y: vf.maxY - Self.panelSize.height - 48
            )
            panel.setFrameOrigin(origin)
        }
        panel.orderFrontRegardless()
    }

    func setSelected(_ intent: CaptureIntent) {
        DispatchQueue.main.async { [weak self] in
            self?.model?.selected = intent
        }
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }
}

final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
