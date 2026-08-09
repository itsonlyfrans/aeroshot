import Combine
import AppKit
import ScreenCaptureKit
import SwiftUI

nonisolated enum ScrollingCapturePolicy {
    struct Cadence: Equatable {
        let stepPixels: Int32
        let intervalMilliseconds: Int
    }

    static func canStartAutoScroll(enabled: Bool, hasFirstFrame: Bool) -> Bool {
        enabled && hasFirstFrame
    }

    static func cadence(configuredPixels: Int) -> Cadence {
        Cadence(stepPixels: Int32(max(2, min(24, configuredPixels / 6))),
                intervalMilliseconds: 60)
    }

    static let previewHeight = 1_200
    static let identicalFramesAtEnd = 10
    static let missedFramesBeforePause = 5
}

/// Scrolling capture: user selects a region, scrolls the target content
/// manually, and an SCStream delivers ~30fps frames of the same rect that are
/// stitched vertically as they arrive. A floating HUD shows the live
/// composite preview and Done/Cancel.
@MainActor
final class ScrollingCaptureController {

    private unowned let appState: AppState
    private var pollTask: Task<Void, Never>?
    private var frameStream: RegionFrameStream?
    private var strips: [CGImage] = []
    private var previewComposite: CGImage?
    private var stitchedHeight = 0
    private var firstFrame: CGImage?
    private var lastFrame: CGImage?
    private var captureRect: CGRect = .zero  // display-local top-left points
    private var display: DisplayInfo?
    private var hudPanel: ScrollingHUDPanel?
    private var hudModel: ScrollingHUDModel?
    private var capturing = false
    private var excludedWindows: [SCWindow] = []
    private var missedFrames = 0
    private var identicalFrames = 0
    private var lastFooterRows = 0
    private var preservedHeaderRows = 0
    private var removedInitialFooterRows = 0
    /// Per-column count of matches whose scrolling band covered the column.
    /// Transient sidebar activity (tooltips, hover states, the cursor) only
    /// votes in a frame or two, so a majority threshold keeps static sidebars
    /// out of the final crop even when they occasionally change.
    private var columnVotes: [Int] = []
    private var matchCount = 0
    private var didPromptAccessibilityAccess = false
    private var autoScrollTask: Task<Void, Never>?
    private var autoScrollTarget: CGPoint?

    init(appState: AppState) {
        self.appState = appState
    }

    func begin() {
        resetIfStuck()
        guard !capturing else { return }
        Task {
            guard let selection = await appState.captureController.selectArea(mode: .scrolling) else { return }
            begin(with: selection.rect, on: selection.display)
        }
    }

    func begin(with cocoaRect: CGRect, on display: DisplayInfo) {
        resetIfStuck()
        guard !capturing else { return }
        Task {
            let local = GeometryConversions.cocoaGlobalToDisplayLocalTopLeft(cocoaRect, screen: display.nsScreen)
            captureRect = local
            self.display = display
            autoScrollTarget = GeometryConversions.cocoaPointToCG(
                NSPoint(x: cocoaRect.midX, y: cocoaRect.midY)
            )
            strips = []
            previewComposite = nil
            stitchedHeight = 0
            firstFrame = nil
            lastFrame = nil
            missedFrames = 0
            identicalFrames = 0
            lastFooterRows = 0
            preservedHeaderRows = 0
            removedInitialFooterRows = 0
            columnVotes = []
            matchCount = 0
            capturing = true
            showHUD(near: cocoaRect, on: display)

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
        stopAutoScroll()
        pollTask?.cancel()
        pollTask = nil
        frameStream?.stop()
        frameStream = nil
        capturing = false
        strips = []
        previewComposite = nil
        stitchedHeight = 0
        firstFrame = nil
        lastFrame = nil
        autoScrollTarget = nil
        excludedWindows = []
        missedFrames = 0
        identicalFrames = 0
        lastFooterRows = 0
        preservedHeaderRows = 0
        removedInitialFooterRows = 0
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
        if strips.isEmpty {
            strips = [frame]
            previewComposite = frame
            stitchedHeight = frame.height
            firstFrame = frame
            lastFrame = frame
            hudModel?.statusMessage = "Scroll the content, then click Done."
            updateHUD()
            if ScrollingCapturePolicy.canStartAutoScroll(
                enabled: appState.settings.scrollingAutoScroll,
                hasFirstFrame: true
            ) {
                startAutoScroll()
            }
            return
        }
        guard let last = lastFrame else { return }

        // Matching is CPU-bound; run it off the main actor so the HUD stays
        // responsive. The frame stream buffers latest-wins, so frames arriving
        // while we match are dropped, not queued.
        let result = await Task.detached(priority: .userInitiated) {
            ImageStitcher.match(previous: last, next: frame)
        }.value

        switch result {
        case .identical:
            identicalFrames += 1
            guard matchCount > 0,
                  autoScrollTask != nil,
                  identicalFrames >= ScrollingCapturePolicy.identicalFramesAtEnd
            else { return }
            stopAutoScroll()
            hudModel?.statusMessage = "Reached the end. Review the preview, then click Done."
            return
        case nil:
            identicalFrames = 0
            missedFrames += 1
            if missedFrames >= ScrollingCapturePolicy.missedFramesBeforePause {
                pauseAutoScroll(message: "Auto-scroll paused. Scroll back slightly, then try again.")
            }
            return
        case .matched(let m):
            identicalFrames = 0
            missedFrames = 0
            preservedHeaderRows = max(preservedHeaderRows, m.headerRows)
            let additionalFooterRows = m.footerRows - removedInitialFooterRows
            if additionalFooterRows > 0,
               let trimmed = ImageStitcher.removingBottomRows(from: strips[0], count: additionalFooterRows) {
                stitchedHeight -= strips[0].height - trimmed.height
                strips[0] = trimmed
                if let rebuilt = ImageStitcher.compose(strips: strips) {
                    previewComposite = ImageStitcher.previewTail(
                        of: rebuilt,
                        maxHeight: ScrollingCapturePolicy.previewHeight
                    )
                }
                removedInitialFooterRows = m.footerRows
            }
            guard let strip = ImageStitcher.newContentStrip(from: frame,
                                                            newContentHeight: m.offset,
                                                            footerRows: m.footerRows)
            else { return }
            strips.append(strip)
            stitchedHeight += strip.height
            if let previewComposite,
               let appended = ImageStitcher.appendStrip(composite: previewComposite, strip: strip) {
                self.previewComposite = ImageStitcher.previewTail(
                    of: appended,
                    maxHeight: ScrollingCapturePolicy.previewHeight
                )
            } else {
                previewComposite = strip
            }
            lastFrame = frame
            lastFooterRows = max(lastFooterRows, m.footerRows)
            if columnVotes.count != frame.width {
                columnVotes = [Int](repeating: 0, count: frame.width)
            }
            matchCount += 1
            let hi = min(m.contentColumns.upperBound, frame.width - 1)
            for x in m.contentColumns.lowerBound...hi { columnVotes[x] += 1 }
            hudModel?.statusMessage = autoScrollTask == nil
                ? "Scroll the content, then click Done."
                : "Capturing while the page scrolls…"
            updateHUD()
        }
    }

    private func finish(save: Bool) {
        stopAutoScroll()
        pollTask?.cancel()
        pollTask = nil
        frameStream?.stop()
        frameStream = nil
        capturing = false
        hudPanel?.orderOut(nil)
        hudPanel = nil
        hudModel = nil
        if save, var result = ImageStitcher.compose(strips: strips) {
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
                                                                  scrollingBand: lo...hi,
                                                                  preservedHeaderRows: preservedHeaderRows) {
                    result = frozen
                }
            }
            appState.handleCapturedImage(result)
        }
        strips = []
        previewComposite = nil
        stitchedHeight = 0
        firstFrame = nil
        lastFrame = nil
        autoScrollTarget = nil
        excludedWindows = []
        missedFrames = 0
        identicalFrames = 0
        lastFooterRows = 0
        preservedHeaderRows = 0
        removedInitialFooterRows = 0
        columnVotes = []
        matchCount = 0
    }

    // MARK: - Auto-scroll

    private func startAutoScroll() {
        stopAutoScroll()
        guard ScrollEventPoster.hasAccessibilityAccess else {
            if !didPromptAccessibilityAccess {
                didPromptAccessibilityAccess = true
                ScrollEventPoster.requestAccessibilityAccess()
            }
            pauseAutoScroll(message: "Grant Accessibility access, then turn Auto-scroll on.")
            return
        }
        guard lastFrame != nil else {
            hudModel?.statusMessage = "Waiting for the first frame before auto-scroll starts."
            return
        }
        guard let autoScrollTarget else {
            hudModel?.statusMessage = "Auto-scroll could not find the selected content."
            return
        }
        let cadence = ScrollingCapturePolicy.cadence(
            configuredPixels: appState.settings.scrollingAutoScrollPixels
        )
        hudModel?.statusMessage = "Capturing while the page scrolls…"
        autoScrollTask = Task { @MainActor in
            while !Task.isCancelled, capturing {
                guard ScrollEventPoster.scrollDown(pixels: cadence.stepPixels, at: autoScrollTarget) else {
                    pauseAutoScroll(message: "Auto-scroll failed. Check Accessibility permission.")
                    return
                }
                try? await Task.sleep(for: .milliseconds(cadence.intervalMilliseconds))
            }
        }
    }

    private func stopAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }

    private func pauseAutoScroll(message: String) {
        stopAutoScroll()
        appState.settings.scrollingAutoScroll = false
        hudModel?.autoScrollEnabled = false
        hudModel?.statusMessage = message
    }

    func setAutoScrollEnabled(_ enabled: Bool) {
        appState.settings.scrollingAutoScroll = enabled
        if enabled, capturing {
            if ScrollingCapturePolicy.canStartAutoScroll(enabled: enabled, hasFirstFrame: lastFrame != nil) {
                startAutoScroll()
            } else {
                hudModel?.statusMessage = "Waiting for the first frame before auto-scroll starts."
            }
        } else {
            stopAutoScroll()
            if capturing {
                hudModel?.statusMessage = "Scroll the content, then click Done."
            }
        }
    }

    // MARK: - HUD

    private func showHUD(near cocoaRect: CGRect, on display: DisplayInfo) {
        let model = ScrollingHUDModel()
        model.autoScrollEnabled = appState.settings.scrollingAutoScroll
        model.onAutoScrollToggle = { [weak self] enabled in self?.setAutoScrollEnabled(enabled) }
        model.onDone = { [weak self] in self?.finish(save: true) }
        model.onCancel = { [weak self] in self?.finish(save: false) }
        hudModel = model

        let hosting = NSHostingView(rootView: ScrollingHUDView(model: model))
        hosting.sizingOptions = []
        hosting.frame = CGRect(x: 0, y: 0, width: 260, height: 380)

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
        let panelHeight: CGFloat = 380
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
        guard let previewComposite else { return }
        hudModel?.preview = NSImage(
            cgImage: previewComposite,
            size: NSSize(width: previewComposite.width, height: previewComposite.height)
        )
        hudModel?.frameCount += 1
        hudModel?.pixelHeight = stitchedHeight
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
    @Published var autoScrollEnabled = false
    var onAutoScrollToggle: ((Bool) -> Void)?
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
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .clipped()
                        .animation(.linear(duration: 0.12), value: model.frameCount)
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

            Toggle("Auto-scroll", isOn: Binding(
                get: { model.autoScrollEnabled },
                set: { model.autoScrollEnabled = $0; model.onAutoScrollToggle?($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            HStack {
                Button("Cancel", role: .cancel) { model.onCancel?() }
                Spacer()
                Button("Done") { model.onDone?() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.preview == nil)
            }
        }
        .padding(12)
        .frame(width: 260, height: 380)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
