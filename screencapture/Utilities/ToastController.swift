import AppKit
import SwiftUI
import Combine

@MainActor
final class ToastModel: ObservableObject {
    @Published var message: String = ""
    @Published var symbol: String = ""
}

/// Non-activating toast HUD for brief feedback (OCR copied, saved, etc.).
/// Reuses a single panel and observes a model to prevent constraint update loops.
@MainActor
final class ToastController {
    static let shared = ToastController()

    private var panel: NSPanel?
    private let model = ToastModel()
    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    func show(_ message: String, symbol: String = "checkmark.circle") {
        dismissWorkItem?.cancel()
        
        model.message = message
        model.symbol = symbol

        if panel == nil {
            let view = ToastView(model: model)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)

            let panel = NSPanel(contentRect: hosting.frame,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.level = .statusBar
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.ignoresMouseEvents = true
            panel.contentView = hosting
            self.panel = panel
        }

        guard let panel = self.panel else { return }

        // Update hosting view frame size to match the new dynamic content
        if let hosting = panel.contentView as? NSHostingView<ToastView> {
            hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
            panel.setContentSize(hosting.frame.size)
        }

        if let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSEvent.mouseLocation)
        }) ?? NSScreen.main {
            let vf = screen.visibleFrame
            let origin = NSPoint(x: vf.midX - panel.frame.width / 2,
                                 y: vf.minY + 48)
            panel.setFrameOrigin(origin)
        }
        
        panel.alphaValue = 1.0
        panel.orderFrontRegardless()

        let work = DispatchWorkItem {
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
            Image(systemName: model.symbol)
                .font(.body.weight(.semibold))
            Text(model.message)
                .font(.body.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
