import AppKit
import Combine
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

@MainActor
final class HUDToolbarModel: ObservableObject {
    @Published var selected: CaptureIntent
    var onSelect: ((CaptureIntent) -> Void)?
    var onCancel: (() -> Void)?

    init(selected: CaptureIntent) {
        self.selected = selected
    }
}

struct HUDToolbarView: View {
    @ObservedObject var model: HUDToolbarModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CaptureIntent.allCases) { intent in
                Button {
                    model.onSelect?(intent)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: intent.symbol)
                            .font(.system(size: 14, weight: .medium))
                        Text(intent.title)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .frame(width: 56, height: 40)
                    .background(
                        model.selected == intent
                            ? AnyShapeStyle(Color.accentColor.opacity(0.85))
                            : AnyShapeStyle(Color.clear),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .foregroundStyle(model.selected == intent ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .help(intent.title)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .onContinuousHover { phase in
            switch phase {
            case .active:
                hovering = true
                NSCursor.arrow.set()
            case .ended:
                hovering = false
                NSCursor.crosshair.set()
            }
        }
    }
}
