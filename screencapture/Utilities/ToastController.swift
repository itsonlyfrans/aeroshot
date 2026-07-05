import AppKit
import SwiftUI
import Combine

@MainActor
final class ToastModel: ObservableObject {
    @Published var message: String = ""
    @Published var symbol: String = "checkmark.circle"
}

/// Non-activating toast HUD for brief feedback (OCR copied, saved, etc.).
/// Uses a fixed panel size and deferred presentation to avoid SwiftUI constraint loops.
@MainActor
final class ToastController {
    static let shared = ToastController()

    private static let panelSize = NSSize(width: 320, height: 44)

    private var panel: NSPanel?
    private let model = ToastModel()
    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    func show(_ message: String, symbol: String = "checkmark.circle") {
        dismissWorkItem?.cancel()

        let resolvedSymbol = symbol.isEmpty ? "checkmark.circle" : symbol
        model.message = message
        model.symbol = resolvedSymbol
        ensurePanel()

        DispatchQueue.main.async { [weak self] in
            self?.presentPanel()
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }

        let hosting = NSHostingView(rootView: ToastView(model: model))
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.contentView = hosting
        self.panel = panel
    }

    private func presentPanel() {
        guard let panel else { return }

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let vf = screen.visibleFrame
            let origin = NSPoint(
                x: vf.midX - panel.frame.width / 2,
                y: vf.minY + 48
            )
            panel.setFrameOrigin(origin)
        }

        panel.alphaValue = 1
        panel.orderFrontRegardless()

        let work = DispatchWorkItem { [weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                panel.animator().alphaValue = 0
            } completionHandler: {
                Task { @MainActor in
                    panel.orderOut(nil)
                }
            }
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }
}

private struct ToastView: View {
    @ObservedObject var model: ToastModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: model.symbol.isEmpty ? "checkmark.circle" : model.symbol)
                .font(.body.weight(.semibold))
            Text(model.message)
                .font(.body.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
