import Combine
import AppKit
import ScreenCaptureKit
import SwiftUI

/// Scrolling capture: user selects a region, scrolls the target content
/// manually, and an SCStream delivers ~30fps frames of the same rect that are
/// stitched vertically as they arrive. A floating HUD shows the live
/// composite preview and Done/Cancel.
@MainActor
final class ScrollingCaptureController {

    private unowned let appState: AppState
    private var pollTask: Task<Void, Never>?
    private var frameStream: RegionFrameStream?
    private var composite: CGImage?
    private var firstFrame: CGImage?
    private var lastFrame: CGImage?
    private var captureRect: CGRect = .zero  // display-local top-left points
    private var display: DisplayInfo?
    private var hudPanel: ScrollingHUDPanel?
    private var hudModel: ScrollingHUDModel?
    private var capturing = false
    private var excludedWindows: [SCWindow] = []
    private var missedFrames = 0
    private var lastFooterRows = 0
    /// Per-column count of matches whose scrolling band covered the column.
    /// Transient sidebar activity (tooltips, hover states, the cursor) only
    /// votes in a frame or two, so a majority threshold keeps static sidebars
    /// out of the final crop even when they occasionally change.
    private var columnVotes: [Int] = []
    private var matchCount = 0

    init(appState: AppState) {
        self.appState = appState
    }

    func begin() {
        resetIfStuck()
        guard !capturing else { return }
        Task {
            guard let selection = await appState.captureController.selectArea(mode: .scrolling) else { return }
            let local = GeometryConversions.cocoaGlobalToDisplayLocalTopLeft(selection.rect, screen: selection.display.nsScreen)
            captureRect = local
            display = selection.display
            composite = nil
            firstFrame = nil
            lastFrame = nil
            missedFrames = 0
            lastFooterRows = 0
            columnVotes = []
            matchCount = 0
            capturing = true
            showHUD(near: selection.rect, on: selection.display)

            // Let the selection overlay finish disappearing and the HUD get
            // registered with the window server before the first grab; fetch
            // our own windows once — refetching per frame is far too slow to
            // keep consecutive frames overlapping during a scroll.
            try? await Task.sleep(for: .milliseconds(150))
            excludedWindows = await WindowEnumerator.ownWindows()
            startStreaming()
        }
    }

    private func resetIfStuck() {
        guard capturing, hudPanel == nil else { return }
        pollTask?.cancel()
        pollTask = nil
        frameStream?.stop()
        frameStream = nil
        capturing = false
        composite = nil
        firstFrame = nil
        lastFrame = nil
        excludedWindows = []
        missedFrames = 0
        lastFooterRows = 0
        columnVotes = []
        matchCount = 0
    }

    private func startStreaming() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            guard let display else { return }
            let streamer = RegionFrameStream()
            frameStream = streamer
            let frames: AsyncStream<CGImage>
            do {
                frames = try await streamer.start(rect: captureRect, display: display,
                                                  excludingWindows: excludedWindows)
            } catch {
                NSLog("Scrolling capture stream failed: \(error)")
                hudModel?.statusMessage = "Capture failed. Check Screen Recording permission."
                return
            }
            for await frame in frames {
                guard !Task.isCancelled, capturing else { break }
                await processFrame(frame)
            }
        }
    }

    private func processFrame(_ frame: CGImage) async {
        guard capturing else { return }
        if composite == nil {
            composite = frame
            firstFrame = frame
            lastFrame = frame
            hudModel?.statusMessage = "Scroll the content, then click Done."
            updateHUD()
            return
        }
        guard let last = lastFrame, let current = composite else { return }

        // Matching is CPU-bound; run it off the main actor so the HUD stays
        // responsive. The frame stream buffers latest-wins, so frames arriving
        // while we match are dropped, not queued.
        let result = await Task.detached(priority: .userInitiated) {
            ImageStitcher.match(previous: last, next: frame)
        }.value

        switch result {
        case .identical:
            return
        case nil:
            missedFrames += 1
            if missedFrames > 8 {
                hudModel?.statusMessage = "Lost track — scroll back a little, in smaller steps."
            }
            return
        case .matched(let m):
            missedFrames = 0
            if let stitched = ImageStitcher.append(composite: current, next: frame,
                                                   newContentHeight: m.offset,
                                                   footerRows: m.footerRows) {
                composite = stitched
                lastFrame = frame
                lastFooterRows = m.footerRows
                if columnVotes.count != frame.width {
                    columnVotes = [Int](repeating: 0, count: frame.width)
                }
                matchCount += 1
                let hi = min(m.contentColumns.upperBound, frame.width - 1)
                for x in m.contentColumns.lowerBound...hi { columnVotes[x] += 1 }
                hudModel?.statusMessage = "Scroll the content, then click Done."
                updateHUD()
            }
        }
    }

    private func finish(save: Bool) {
        pollTask?.cancel()
        pollTask = nil
        frameStream?.stop()
        frameStream = nil
        capturing = false
        hudPanel?.orderOut(nil)
        hudPanel = nil
        hudModel = nil
        if save, var result = composite {
            // Sticky footer rows were skipped during appends; restore them once
            // at the very bottom from the final frame.
            if lastFooterRows > 0, let last = lastFrame,
               let footer = last.cropping(to: CGRect(x: 0, y: last.height - lastFooterRows,
                                                     width: last.width, height: lastFooterRows)),
               let withFooter = ImageStitcher.appendStrip(composite: result, strip: footer) {
                result = withFooter
            }
            // Static sidebars would repeat in every appended strip, so repaint
            // them: the first frame's sidebar drawn once at the top, the rest
            // of the column flooded with its background color. A column counts
            // as scrolling only when a majority of matched frame pairs saw it
            // change — one-off tooltips and cursor hovers over the sidebar
            // can't widen the band.
            let threshold = max(1, (matchCount + 1) / 2)
            if matchCount > 0, let firstFrame,
               let first = columnVotes.firstIndex(where: { $0 >= threshold }),
               let last = columnVotes.lastIndex(where: { $0 >= threshold }) {
                let margin = 8
                let lo = max(0, first - margin)
                let hi = min(result.width - 1, last + margin)
                if hi - lo < (result.width * 9) / 10,
                   let frozen = ImageStitcher.freezeStaticColumns(composite: result,
                                                                  firstFrame: firstFrame,
                                                                  scrollingBand: lo...hi) {
                    result = frozen
                }
            }
            appState.handleCapturedImage(result)
        }
        composite = nil
        firstFrame = nil
        lastFrame = nil
        excludedWindows = []
        missedFrames = 0
        lastFooterRows = 0
        columnVotes = []
        matchCount = 0
    }

    // MARK: - HUD

    private func showHUD(near cocoaRect: CGRect, on display: DisplayInfo) {
        let model = ScrollingHUDModel()
        model.onDone = { [weak self] in self?.finish(save: true) }
        model.onCancel = { [weak self] in self?.finish(save: false) }
        hudModel = model

        let hosting = NSHostingView(rootView: ScrollingHUDView(model: model))
        hosting.frame = CGRect(x: 0, y: 0, width: 260, height: 340)

        let panel = ScrollingHUDPanel(contentRect: hosting.frame,
                                      styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.contentView = hosting

        let vf = display.nsScreen.visibleFrame
        let panelWidth: CGFloat = 260
        let panelHeight: CGFloat = 340
        var origin = NSPoint(x: cocoaRect.maxX + 16, y: cocoaRect.maxY - panelHeight)

        // Keep the HUD outside the capture region.
        let captureFrame = NSRect(x: cocoaRect.origin.x, y: cocoaRect.origin.y,
                                  width: cocoaRect.width, height: cocoaRect.height)
        var panelFrame = NSRect(x: origin.x, y: origin.y, width: panelWidth, height: panelHeight)
        if panelFrame.intersects(captureFrame) {
            origin = NSPoint(x: cocoaRect.maxX + 16, y: cocoaRect.minY - panelHeight - 16)
            panelFrame.origin = origin
        }
        if panelFrame.intersects(captureFrame) {
            origin = NSPoint(x: cocoaRect.minX - panelWidth - 16, y: cocoaRect.maxY - panelHeight)
            panelFrame.origin = origin
        }
        if panelFrame.maxX > vf.maxX { origin.x = max(vf.minX, vf.maxX - panelWidth - 16) }
        if panelFrame.minX < vf.minX { origin.x = vf.minX + 16 }
        if panelFrame.minY < vf.minY { origin.y = vf.minY + 16 }
        if panelFrame.maxY > vf.maxY { origin.y = vf.maxY - panelHeight - 16 }

        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        hudPanel = panel
    }

    private func updateHUD() {
        guard let composite else { return }
        hudModel?.preview = NSImage(cgImage: composite, size: NSSize(width: composite.width, height: composite.height))
        hudModel?.frameCount += 1
        hudModel?.pixelHeight = composite.height
    }
}

/// Keyable panel so Done/Cancel buttons receive clicks.
final class ScrollingHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ScrollingHUDModel: ObservableObject {
    @Published var preview: NSImage?
    @Published var frameCount = 0
    @Published var pixelHeight = 0
    @Published var statusMessage = "Waiting for first frame…"
    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?
}

struct ScrollingHUDView: View {
    @ObservedObject var model: ScrollingHUDModel

    var body: some View {
        VStack(spacing: 8) {
            Text("Scrolling Capture")
                .font(.headline)
            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))

            Text("\(model.pixelHeight) px tall · \(model.frameCount) frame\(model.frameCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel", role: .cancel) { model.onCancel?() }
                Spacer()
                Button("Done") { model.onDone?() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.preview == nil)
            }
        }
        .padding(12)
        .frame(width: 260, height: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
