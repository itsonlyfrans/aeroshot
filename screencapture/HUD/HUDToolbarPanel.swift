import AppKit
import SwiftUI

/// Floating toolbar for the All-in-One capture HUD.
@MainActor
final class HUDToolbarPanel {
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
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)

        let panel = HUDPanel(contentRect: hosting.frame,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.contentView = hosting

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let screen {
            let vf = screen.visibleFrame
            let origin = NSPoint(x: vf.midX - hosting.frame.width / 2,
                                 y: vf.maxY - hosting.frame.height - 48)
            panel.setFrameOrigin(origin)
        }
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func setSelected(_ intent: CaptureIntent) {
        model?.selected = intent
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }
}

final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
