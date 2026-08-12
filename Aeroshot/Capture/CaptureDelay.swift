import AppKit
import Combine
import SwiftUI

/// Full-screen countdown shown before a timed capture starts.
@MainActor
enum CaptureDelay {
    static func wait(seconds: Int) async -> Bool {
        guard seconds > 0 else { return true }
        return await CountdownOverlayController.run(seconds: seconds)
    }
}

@MainActor
private final class CountdownModel: ObservableObject {
    @Published var seconds: Int

    init(seconds: Int) {
        self.seconds = seconds
    }
}

@MainActor
private final class CountdownOverlayController {
    private static let panelSize = NSSize(width: 280, height: 160)

    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timer: Timer?
    private let model: CountdownModel

    private init(seconds: Int) {
        model = CountdownModel(seconds: seconds)
    }

    static func run(seconds: Int) async -> Bool {
        let controller = CountdownOverlayController(seconds: seconds)
        let result = await withCheckedContinuation { continuation in
            controller.start(continuation: continuation)
        }
        withExtendedLifetime(controller) {}
        return result
    }

    private func start(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation

        let view = CountdownOverlayView(model: model) { [weak self] in
            self?.finish(cancelled: true)
        }
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize)

        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        let panel = NSPanel(
            contentRect: CGRect(
                x: frame.midX - Self.panelSize.width / 2,
                y: frame.midY - Self.panelSize.height / 2,
                width: Self.panelSize.width,
                height: Self.panelSize.height
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        panel.orderFrontRegardless()
        self.panel = panel

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.finish(cancelled: true)
                return nil
            }
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in self?.finish(cancelled: true) }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.seconds -= 1
                if self.model.seconds <= 0 {
                    self.finish(cancelled: false)
                }
            }
        }
    }

    private func finish(cancelled: Bool) {
        timer?.invalidate()
        timer = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
        globalKeyMonitor = nil
        panel?.orderOut(nil)
        panel = nil
        continuation?.resume(returning: !cancelled)
        continuation = nil
    }
}

private struct CountdownOverlayView: View {
    @ObservedObject var model: CountdownModel
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("\(model.seconds)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(model.seconds == 1 ? "Capturing in 1 second" : "Capturing in \(model.seconds) seconds")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Button("Cancel") { onCancel() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(28)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        }
    }
}
