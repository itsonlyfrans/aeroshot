import Combine
import AppKit
import ScreenCaptureKit
import SwiftUI

nonisolated enum ScrollingCapturePolicy {
    enum EndAction { case done, cancel, retake }

    struct Cadence: Equatable {
        let stepPixels: Int32
        let intervalMilliseconds: Int
    }

    static let previewWidth = 320
    static let previewHeight = 1_200
    static let identicalFramesAtEnd = 45
    static let missedFramesBeforePause = 5

    static func canStartAutoScroll(enabled: Bool, hasFirstFrame: Bool) -> Bool {
        enabled && hasFirstFrame
    }

    static func shouldPauseAtEnd(identicalFrames: Int, hasMatchedFrames: Bool, isAutoScrolling: Bool) -> Bool {
        hasMatchedFrames && isAutoScrolling && identicalFrames >= identicalFramesAtEnd
    }

    static func requestsFreshSelection(after action: EndAction) -> Bool {
        action == .retake
    }

    static func acceptsActiveWork(expectedRevision: Int, currentRevision: Int, isCapturing: Bool) -> Bool {
        expectedRevision == currentRevision && isCapturing
    }

    static func acceptsFinalDelivery(token: Int, pendingToken: Int?, isCapturing: Bool) -> Bool {
        token == pendingToken && !isCapturing
    }

    static func cadence(configuredPixels: Int) -> Cadence {
        Cadence(stepPixels: Int32(max(2, min(24, configuredPixels / 6))), intervalMilliseconds: 60)
    }
}

private struct ScrollingCaptureSnapshot: @unchecked Sendable {
    let strips: [CGImage]
    let footer: CGImage?
    let firstFrame: CGImage?
    let columnVotes: [Int]
    let matchCount: Int
    let preservedHeaderRows: Int
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
    private var currentFooter: CGImage?
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
    private var removedInitialFooterRows = 0
    private var preservedHeaderRows = 0
    /// Per-column count of matches whose scrolling band covered the column.
    /// Transient sidebar activity (tooltips, hover states, the cursor) only
    /// votes in a frame or two, so a majority threshold keeps static sidebars
    /// out of the final crop even when they occasionally change.
    private var columnVotes: [Int] = []
    private var matchCount = 0
    private var didPromptAccessibilityAccess = false
    private var autoScrollTask: Task<Void, Never>?
    private var autoScrollTarget: CGPoint?
    private var captureRevision = 0
    private var finalDeliveryToken: Int?
    private var previewRevision = 0
    private var previewRenderInFlight = false

    init(appState: AppState) {
        self.appState = appState
    }

    func begin() {
        resetIfStuck()
        guard !capturing else { return }
        captureRevision &+= 1
        finalDeliveryToken = nil
        let selectionRevision = captureRevision
        Task {
            guard let selection = await appState.captureController.selectArea(mode: .scrolling) else { return }
            guard selectionRevision == captureRevision, !capturing else { return }
            begin(with: selection.rect, on: selection.display)
        }
    }

    func begin(with cocoaRect: CGRect, on display: DisplayInfo) {
        resetIfStuck()
        guard !capturing else { return }
        let local = GeometryConversions.cocoaGlobalToDisplayLocalTopLeft(cocoaRect, screen: display.nsScreen)
        captureRect = local
        self.display = display
        captureRevision &+= 1
        finalDeliveryToken = nil
        let session = captureRevision
        strips = []
        currentFooter = nil
        stitchedHeight = 0
        firstFrame = nil
        lastFrame = nil
        autoScrollTarget = GeometryConversions.cocoaPointToCG(NSPoint(x: cocoaRect.midX, y: cocoaRect.midY))
        missedFrames = 0
        identicalFrames = 0
        removedInitialFooterRows = 0
        preservedHeaderRows = 0
        columnVotes = []
        matchCount = 0
        capturing = true
        showHUD(near: cocoaRect, on: display)

        Task { [weak self] in
            // Selection completion runs after its compositor delay. Fetch our
            // windows after the HUD exists so the stream excludes all chrome.
            try? await Task.sleep(for: .milliseconds(150))
            guard let self,
                  ScrollingCapturePolicy.acceptsActiveWork(
                    expectedRevision: session,
                    currentRevision: self.captureRevision,
                    isCapturing: self.capturing
                  )
            else { return }
            let windows = await WindowEnumerator.ownWindows()
            guard ScrollingCapturePolicy.acceptsActiveWork(
                expectedRevision: session,
                currentRevision: captureRevision,
                isCapturing: capturing
            ) else { return }
            excludedWindows = windows
            startStreaming(for: session)
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
        captureRevision &+= 1
        finalDeliveryToken = nil
        strips = []
        currentFooter = nil
        stitchedHeight = 0
        firstFrame = nil
        lastFrame = nil
        autoScrollTarget = nil
        excludedWindows = []
        missedFrames = 0
        identicalFrames = 0
        removedInitialFooterRows = 0
        preservedHeaderRows = 0
        columnVotes = []
        matchCount = 0
    }

    private func startStreaming(for session: Int) {
        guard ScrollingCapturePolicy.acceptsActiveWork(
            expectedRevision: session,
            currentRevision: captureRevision,
            isCapturing: capturing
        ) else { return }
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            guard let display else { return }
            let streamer = RegionFrameStream()
            let frames: AsyncStream<CGImage>
            do {
                frames = try await streamer.start(rect: captureRect, display: display,
                                                  excludingWindows: excludedWindows)
            } catch {
                NSLog("Scrolling capture stream failed: \(error)")
                hudModel?.statusMessage = "Capture failed. Check Screen Recording permission."
                return
            }
            guard ScrollingCapturePolicy.acceptsActiveWork(
                expectedRevision: session,
                currentRevision: captureRevision,
                isCapturing: capturing
            ) else {
                streamer.stop()
                return
            }
            frameStream = streamer
            for await frame in frames {
                guard !Task.isCancelled,
                      ScrollingCapturePolicy.acceptsActiveWork(
                        expectedRevision: session,
                        currentRevision: captureRevision,
                        isCapturing: capturing
                      )
                else { break }
                await processFrame(frame, session: session)
            }
        }
    }

    private func processFrame(_ frame: CGImage, session: Int) async {
        guard ScrollingCapturePolicy.acceptsActiveWork(
            expectedRevision: session,
            currentRevision: captureRevision,
            isCapturing: capturing
        ) else { return }
        if strips.isEmpty {
            strips = [frame]
            stitchedHeight = frame.height
            firstFrame = frame
            lastFrame = frame
            hudModel?.statusMessage = "Scroll the content, then click Done."
            updateHUDProgress()
            requestPreview()
            if ScrollingCapturePolicy.canStartAutoScroll(enabled: appState.settings.scrollingAutoScroll,
                                                         hasFirstFrame: true) {
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

        guard !Task.isCancelled,
              ScrollingCapturePolicy.acceptsActiveWork(
                expectedRevision: session,
                currentRevision: captureRevision,
                isCapturing: capturing
              ),
              !strips.isEmpty,
              lastFrame === last
        else { return }

        switch result {
        case .identical:
            identicalFrames += 1
            if ScrollingCapturePolicy.shouldPauseAtEnd(
                identicalFrames: identicalFrames,
                hasMatchedFrames: matchCount > 0,
                isAutoScrolling: autoScrollTask != nil
            ) {
                pauseAutoScroll(message: "No new content yet. Auto-scroll paused; click Done when ready.")
            }
            return
        case nil:
            identicalFrames = 0
            missedFrames += 1
            if missedFrames >= ScrollingCapturePolicy.missedFramesBeforePause {
                pauseAutoScroll(message: "Auto-scroll paused. Scroll back slightly, then try again.")
            }
            return
        case .matched(let m):
            missedFrames = 0
            identicalFrames = 0
            preservedHeaderRows = max(preservedHeaderRows, m.headerRows)
            let additionalFooterRows = m.footerRows - removedInitialFooterRows
            if additionalFooterRows > 0,
               let firstStrip = strips.first,
               let trimmed = ImageStitcher.removingBottomRows(from: firstStrip, count: additionalFooterRows) {
                stitchedHeight -= firstStrip.height - trimmed.height
                strips.replaceSubrange(0...0, with: [trimmed])
                removedInitialFooterRows = m.footerRows
            }
            guard let strip = ImageStitcher.newContentStrip(from: frame,
                                                            newContentHeight: m.offset,
                                                            footerRows: m.footerRows)
            else { return }
            strips.append(strip)
            stitchedHeight += strip.height
            lastFrame = frame
            currentFooter = ImageStitcher.footer(from: frame, rows: m.footerRows)
            if columnVotes.count != frame.width {
                columnVotes = [Int](repeating: 0, count: frame.width)
            }
            matchCount += 1
            let hi = min(m.contentColumns.upperBound, frame.width - 1)
            for x in m.contentColumns.lowerBound...hi { columnVotes[x] += 1 }
            hudModel?.statusMessage = autoScrollTask == nil
                ? "Scroll the content, then click Done."
                : "Capturing while the page scrolls…"
            updateHUDProgress()
            requestPreview()
        }
    }

    private func finish(save: Bool) {
        let session = captureRevision
        let snapshot = ScrollingCaptureSnapshot(
            strips: strips,
            footer: currentFooter,
            firstFrame: firstFrame,
            columnVotes: columnVotes,
            matchCount: matchCount,
            preservedHeaderRows: preservedHeaderRows
        )
        stopAutoScroll()
        pollTask?.cancel()
        pollTask = nil
        frameStream?.stop()
        frameStream = nil
        capturing = false
        captureRevision &+= 1
        finalDeliveryToken = save ? session : nil
        hudPanel?.orderOut(nil)
        hudPanel = nil
        hudModel = nil
        strips = []
        currentFooter = nil
        stitchedHeight = 0
        firstFrame = nil
        lastFrame = nil
        autoScrollTarget = nil
        excludedWindows = []
        missedFrames = 0
        identicalFrames = 0
        removedInitialFooterRows = 0
        preservedHeaderRows = 0
        columnVotes = []
        matchCount = 0

        guard save, !snapshot.strips.isEmpty else { return }
        Task.detached(priority: .userInitiated) { [weak self, snapshot] in
            guard let image = Self.makeFinalImage(snapshot) else { return }
            await self?.deliverFinalImage(image, for: session)
        }
    }

    private func retake() {
        finish(save: false)
        guard ScrollingCapturePolicy.requestsFreshSelection(after: .retake) else { return }
        begin()
    }

    nonisolated private static func makeFinalImage(_ snapshot: ScrollingCaptureSnapshot) -> CGImage? {
        guard var result = ImageStitcher.compose(strips: snapshot.strips) else { return nil }
        if let footer = snapshot.footer,
           let withFooter = ImageStitcher.appendStrip(composite: result, strip: footer) {
            result = withFooter
        }
        let threshold = max(1, (snapshot.matchCount + 1) / 2)
        if snapshot.matchCount > 0,
           let firstFrame = snapshot.firstFrame,
           let first = snapshot.columnVotes.firstIndex(where: { $0 >= threshold }),
           let last = snapshot.columnVotes.lastIndex(where: { $0 >= threshold }) {
            let margin = 8
            let lo = max(0, first - margin)
            let hi = min(result.width - 1, last + margin)
            if hi - lo < (result.width * 9) / 10,
               let frozen = ImageStitcher.freezeStaticColumns(
                composite: result,
                firstFrame: firstFrame,
                scrollingBand: lo...hi,
                preservedHeaderRows: snapshot.preservedHeaderRows
               ) {
                result = frozen
            }
        }
        return result
    }

    private func deliverFinalImage(_ image: CGImage, for session: Int) {
        guard ScrollingCapturePolicy.acceptsFinalDelivery(
            token: session,
            pendingToken: finalDeliveryToken,
            isCapturing: capturing
        ) else { return }
        finalDeliveryToken = nil
        appState.handleCapturedImage(image)
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
        hudModel?.needsAccessibilityAccess = false
        let cadence = ScrollingCapturePolicy.cadence(configuredPixels: appState.settings.scrollingAutoScrollPixels)
        let session = captureRevision
        autoScrollTask = Task { @MainActor in
            while !Task.isCancelled,
                  ScrollingCapturePolicy.acceptsActiveWork(
                    expectedRevision: session,
                    currentRevision: captureRevision,
                    isCapturing: capturing
                  ) {
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
        hudModel?.needsAccessibilityAccess = !ScrollEventPoster.hasAccessibilityAccess
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
        model.onPauseAutoScroll = { [weak self] in
            self?.pauseAutoScroll(message: "Auto-scroll paused. Scroll manually or resume when ready.")
        }
        model.onDone = { [weak self] in self?.finish(save: true) }
        model.onCancel = { [weak self] in self?.finish(save: false) }
        model.onRetake = { [weak self] in self?.retake() }
        model.onOpenAccessibilitySettings = { ScrollEventPoster.openAccessibilitySettings() }
        hudModel = model

        let hosting = NSHostingView(rootView: ScrollingHUDView(model: model))
        hosting.sizingOptions = []
        hosting.frame = CGRect(x: 0, y: 0, width: 260, height: 420)

        let panel = ScrollingHUDPanel(contentRect: hosting.frame,
                                      styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.onCancel = { [weak self] in self?.finish(save: false) }
        panel.contentView = hosting

        let vf = display.nsScreen.visibleFrame
        let panelWidth: CGFloat = 260
        let panelHeight: CGFloat = 420
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

    private func updateHUDProgress() {
        hudModel?.frameCount += 1
        hudModel?.pixelHeight = stitchedHeight
    }

    private func requestPreview() {
        previewRevision &+= 1
        guard !previewRenderInFlight else { return }
        renderLatestPreview()
    }

    private func renderLatestPreview() {
        guard capturing else { return }
        previewRenderInFlight = true
        let session = captureRevision
        let revision = previewRevision
        var previewStrips = strips
        if let currentFooter { previewStrips.append(currentFooter) }
        let snapshot = ScrollingCaptureSnapshot(
            strips: previewStrips,
            footer: nil,
            firstFrame: nil,
            columnVotes: [],
            matchCount: 0,
            preservedHeaderRows: 0
        )
        Task.detached(priority: .utility) { [weak self, snapshot] in
            let image = ImageStitcher.overview(
                strips: snapshot.strips,
                maxWidth: ScrollingCapturePolicy.previewWidth,
                maxHeight: ScrollingCapturePolicy.previewHeight
            )
            await self?.applyPreview(image, session: session, revision: revision)
        }
    }

    private func applyPreview(_ image: CGImage?, session: Int, revision: Int) {
        previewRenderInFlight = false
        let isCurrent = ScrollingCapturePolicy.acceptsActiveWork(
            expectedRevision: session,
            currentRevision: captureRevision,
            isCapturing: capturing
        )
        if isCurrent, revision == previewRevision, let image {
            hudModel?.preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
        if isCurrent, revision < previewRevision {
            renderLatestPreview()
        }
    }
}

/// Keyable panel so Done/Cancel buttons receive clicks.
final class ScrollingHUDPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
final class ScrollingHUDModel: ObservableObject {
    @Published var preview: NSImage?
    @Published var frameCount = 0
    @Published var pixelHeight = 0
    @Published var statusMessage = "Waiting for first frame…"
    @Published var autoScrollEnabled = false
    @Published var needsAccessibilityAccess = false
    var onAutoScrollToggle: ((Bool) -> Void)?
    var onPauseAutoScroll: (() -> Void)?
    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?
    var onRetake: (() -> Void)?
    var onOpenAccessibilitySettings: (() -> Void)?
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
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Toggle("Auto-scroll", isOn: Binding(
                    get: { model.autoScrollEnabled },
                    set: { model.autoScrollEnabled = $0; model.onAutoScrollToggle?($0) }
                ))
                .toggleStyle(.switch)
                Button("Pause") { model.onPauseAutoScroll?() }
                    .disabled(!model.autoScrollEnabled)
            }
            .controlSize(.regular)

            if model.needsAccessibilityAccess {
                Button("Open Accessibility Settings") { model.onOpenAccessibilitySettings?() }
                    .controlSize(.regular)
            }

            HStack {
                Button("Cancel", role: .cancel) { model.onCancel?() }
                Spacer()
                Button("Retake") { model.onRetake?() }
                Button("Done") { model.onDone?() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.preview == nil)
            }
        }
        .padding(12)
        .frame(width: 260, height: 420)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
