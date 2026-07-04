import Combine
import AppKit
import SwiftUI

/// Scrolling capture: user selects a region, scrolls the target content
/// manually, and we periodically recapture the same rect, stitching frames
/// vertically. A floating HUD shows a live composite preview and Done/Cancel.
@MainActor
final class ScrollingCaptureController {

    private unowned let appState: AppState
    private var timer: Timer?
    private var composite: CGImage?
    private var lastFrame: CGImage?
    private var captureRect: CGRect = .zero  // display-local top-left points
    private var display: DisplayInfo?
    private var hudPanel: NSPanel?
    private var hudModel: ScrollingHUDModel?
    private var capturing = false

    init(appState: AppState) {
        self.appState = appState
    }

    func begin() {
        guard !capturing else { return }
        Task {
            guard let selection = await appState.captureController.selectArea() else { return }
            let local = GeometryConversions.cocoaGlobalToDisplayLocalTopLeft(selection.rect, screen: selection.display.nsScreen)
            captureRect = local
            display = selection.display
            composite = nil
            lastFrame = nil
            capturing = true
            showHUD(near: selection.rect, on: selection.display)
            // First frame immediately, then poll.
            await captureFrame()
            timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.captureFrame() }
            }
        }
    }

    private func captureFrame() async {
        guard capturing, let display else { return }
        guard let frame = try? await ScreenCaptureService.captureArea(captureRect, on: display) else { return }

        if composite == nil {
            composite = frame
            lastFrame = frame
            updateHUD()
            return
        }
        guard let last = lastFrame, let current = composite else { return }

        guard let offset = ImageStitcher.verticalOffset(previous: last, next: frame) else {
            return  // no confident movement — user hasn't scrolled or frame is bad
        }
        // Ignore sticky headers: don't append rows that belong to a fixed band.
        let sticky = ImageStitcher.stickyHeaderHeight(previous: last, next: frame)
        let newContent = min(offset, frame.height - sticky)
        guard newContent > 4 else { return }

        if let stitched = ImageStitcher.append(composite: current, next: frame, newContentHeight: newContent) {
            composite = stitched
            lastFrame = frame
            updateHUD()
        }
    }

    private func finish(save: Bool) {
        timer?.invalidate()
        timer = nil
        capturing = false
        hudPanel?.orderOut(nil)
        hudPanel = nil
        hudModel = nil
        if save, let composite {
            appState.handleCapturedImage(composite)
        }
        composite = nil
        lastFrame = nil
    }

    // MARK: - HUD

    private func showHUD(near cocoaRect: CGRect, on display: DisplayInfo) {
        let model = ScrollingHUDModel()
        model.onDone = { [weak self] in self?.finish(save: true) }
        model.onCancel = { [weak self] in self?.finish(save: false) }
        hudModel = model

        let hosting = NSHostingView(rootView: ScrollingHUDView(model: model))
        hosting.frame = CGRect(x: 0, y: 0, width: 240, height: 320)

        let panel = NSPanel(contentRect: hosting.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.contentView = hosting

        // Place beside the selection, clamped to the screen.
        let vf = display.nsScreen.visibleFrame
        var x = cocoaRect.maxX + 16
        if x + 240 > vf.maxX { x = max(vf.minX, cocoaRect.minX - 256) }
        let y = min(max(cocoaRect.maxY - 320, vf.minY), vf.maxY - 320)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
        hudPanel = panel
    }

    private func updateHUD() {
        guard let composite else { return }
        hudModel?.preview = NSImage(cgImage: composite, size: NSSize(width: composite.width, height: composite.height))
        hudModel?.frameCount += 1
        hudModel?.pixelHeight = composite.height
    }
}

@MainActor
final class ScrollingHUDModel: ObservableObject {
    @Published var preview: NSImage?
    @Published var frameCount = 0
    @Published var pixelHeight = 0
    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?
}

struct ScrollingHUDView: View {
    @ObservedObject var model: ScrollingHUDModel

    var body: some View {
        VStack(spacing: 8) {
            Text("Scroll the content…")
                .font(.headline)
            Group {
                if let preview = model.preview {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Image(nsImage: preview)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .onChange(of: model.pixelHeight) {
                            proxy.scrollTo("bottom")
                        }
                    }
                } else {
                    Text("Waiting for first frame")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))

            Text("\(model.pixelHeight) px tall")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel", role: .cancel) { model.onCancel?() }
                Spacer()
                Button("Done") { model.onDone?() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .frame(width: 240, height: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
