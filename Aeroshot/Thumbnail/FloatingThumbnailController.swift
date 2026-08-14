import AppKit
import os
import SwiftUI

private final class ThumbnailPanel: NSPanel {
    var onTwoFingerSwipe: ((ThumbnailSwipeDirection) -> Void)?

    private static let minimumSwipeDistance: CGFloat = 24
    private var accumulatedDelta = CGSize.zero

    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel,
           event.hasPreciseScrollingDeltas,
           event.momentumPhase.isEmpty {
            trackTwoFingerSwipe(event)
        }
        super.sendEvent(event)
    }

    private func trackTwoFingerSwipe(_ event: NSEvent) {
        if event.phase.contains(.began) {
            accumulatedDelta = .zero
        }

        let physicalDirection: CGFloat = event.isDirectionInvertedFromDevice ? -1 : 1
        accumulatedDelta.width += event.scrollingDeltaX * physicalDirection
        accumulatedDelta.height += event.scrollingDeltaY * physicalDirection

        if event.phase.contains(.ended) {
            if let direction = ThumbnailSwipeResolver.direction(
                for: accumulatedDelta,
                minimumDistance: Self.minimumSwipeDistance
            ) {
                onTwoFingerSwipe?(direction)
            }
            accumulatedDelta = .zero
        } else if event.phase.contains(.cancelled) {
            accumulatedDelta = .zero
        }
    }
}

private final class ThumbnailHostingView: NSHostingView<FloatingThumbnailView> {
    var onSwipe: ((ThumbnailSwipeFingerCount, ThumbnailSwipeDirection) -> Void)?
    var onReveal: (() -> Void)?

    private var startPositions: [ObjectIdentifier: CGPoint] = [:]
    private var currentPositions: [ObjectIdentifier: CGPoint] = [:]
    private var maximumTouchCount = 0

    required init(rootView: FloatingThumbnailView) {
        super.init(rootView: rootView)
        allowedTouchTypes = [.indirect]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(with event: NSEvent) {
        updateTouchingPositions(from: event, resetStartWhenCountGrows: true)
        super.touchesBegan(with: event)
    }

    override func touchesMoved(with event: NSEvent) {
        updateTouchingPositions(from: event, resetStartWhenCountGrows: true)
        super.touchesMoved(with: event)
    }

    override func touchesEnded(with event: NSEvent) {
        merge(event.touches(matching: .ended, in: self))
        let remaining = activeTouches(in: event)
        merge(remaining)
        if remaining.isEmpty {
            finishGesture()
        }
        super.touchesEnded(with: event)
    }

    override func touchesCancelled(with event: NSEvent) {
        resetGesture()
        super.touchesCancelled(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        onReveal?()
        super.mouseDown(with: event)
    }

    private func updateTouchingPositions(from event: NSEvent, resetStartWhenCountGrows: Bool) {
        let touches = activeTouches(in: event)
        merge(touches)
        guard resetStartWhenCountGrows, touches.count > maximumTouchCount else { return }
        maximumTouchCount = touches.count
        startPositions = currentPositions.filter { key, _ in
            touches.contains { ObjectIdentifier($0.identity as AnyObject) == key }
        }
    }

    private func activeTouches(in event: NSEvent) -> Set<NSTouch> {
        Set(event.touches(matching: .touching, in: self).filter { !$0.isResting })
    }

    private func merge(_ touches: Set<NSTouch>) {
        for touch in touches where !touch.isResting {
            currentPositions[ObjectIdentifier(touch.identity as AnyObject)] = touch.normalizedPosition
        }
    }

    private func finishGesture() {
        defer { resetGesture() }
        guard maximumTouchCount == ThumbnailSwipeFingerCount.three.rawValue else { return }
        let identities = Set(startPositions.keys).intersection(currentPositions.keys)
        guard !identities.isEmpty else { return }

        let divisor = CGFloat(identities.count)
        let start = identities.reduce(CGPoint.zero) { result, identity in
            let point = startPositions[identity] ?? .zero
            return CGPoint(x: result.x + point.x, y: result.y + point.y)
        }
        let current = identities.reduce(CGPoint.zero) { result, identity in
            let point = currentPositions[identity] ?? .zero
            return CGPoint(x: result.x + point.x, y: result.y + point.y)
        }
        let translation = CGSize(
            width: (current.x - start.x) / divisor,
            height: (current.y - start.y) / divisor
        )
        guard let direction = ThumbnailSwipeResolver.direction(for: translation) else { return }
        onSwipe?(.three, direction)
    }

    private func resetGesture() {
        startPositions.removeAll(keepingCapacity: true)
        currentPositions.removeAll(keepingCapacity: true)
        maximumTouchCount = 0
    }
}

/// Shows the Quick Access Overlay: a floating thumbnail in the bottom-left
/// corner after each capture, with configurable quick actions.
@MainActor
final class FloatingThumbnailController {
    private unowned let appState: AppState
    private var panel: NSPanel?
    private var dismissTimer: Timer?
    private var shareSafeTask: Task<Void, Never>?
    private var untuckedOrigin: NSPoint?
    private weak var currentModel: ThumbnailModel?

    init(appState: AppState) {
        self.appState = appState
    }

    func show(
        image: CGImage,
        fileURL: URL?,
        captureKind: ThumbnailCaptureKind = .area,
        sourceScale: CGFloat = 1,
        privacyScanPending: Bool = false,
        uploadPending: Bool = false,
        unavailableActions: Set<ThumbnailAction> = []
    ) {
        dismiss(animated: false)
        let visibleState = PerformanceInstrumentation.signposter.beginInterval("ThumbnailVisible")

        let model = ThumbnailModel(
            image: image,
            fileURL: fileURL,
            captureKind: captureKind,
            isPrivacyScanPending: privacyScanPending,
            uploadState: uploadPending ? .uploading : .idle
        )
        currentModel = model
        let unavailable = unavailableActions.union(fileURL == nil ? [.reveal] : [])
        model.availableActions = ThumbnailAction.allCases.filter { !unavailable.contains($0) }
        model.visibleActions = appState.settings.thumbnailVisibleActions.filter { !unavailable.contains($0) }
        model.onAction = { [weak self, weak model] action in
            guard let self else { return }
            switch action {
            case .copy:
            guard let model else { return }
            self.performProtectedAction(image: image, fileURL: fileURL, model: model) { [weak self] output, outputURL in
                if !PasteboardWriter.copy(image: output, fileURL: outputURL, sourceScale: sourceScale) {
                    ToastController.shared.show("Copy failed", symbol: "exclamationmark.triangle")
                }
                self?.dismiss()
            }
            case .save:
            let url = self.appState.settings.newFileURL()
            do {
                let settings = self.appState.settings
                try ImageExporter.write(
                    image,
                    to: url,
                    format: settings.imageFormat,
                    jpegQuality: settings.jpegQuality,
                    scale: sourceScale,
                    downscaleToPoints: settings.downscaleRetina
                )
                NSWorkspace.shared.activateFileViewerSelecting([url])
                self.dismiss()
            } catch {
                ToastController.shared.show(
                    "Couldn’t save screenshot. Check the save folder and available space.",
                    symbol: "exclamationmark.triangle"
                )
            }
            case .edit:
            self.appState.openEditor(with: image, sourceScale: sourceScale)
            self.dismiss()
            case .pin:
            self.appState.pinController.pin(image: image, sourceScale: sourceScale)
            self.dismiss()
            case .ocr:
            Task { [weak self] in
                if let text = try? await OCRService.recognizeText(in: image) {
                    PasteboardWriter.copy(text: text)
                }
                self?.dismiss()
            }
            case .share:
            guard let model, let view = self.panel?.contentView else { return }
            self.performProtectedAction(image: image, fileURL: fileURL, model: model) { output, outputURL in
                ShareService.shareImage(output, fileURL: outputURL, from: view)
            }
            case .reveal:
            guard let fileURL else { return }
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            self.dismiss()
            case .shareSafe:
            guard let model, let view = self.panel?.contentView else { return }
            self.dismissTimer?.invalidate()
            self.dismissTimer = nil
            model.isPrivacyScanPending = true
            self.shareSafeTask?.cancel()
            self.shareSafeTask = Task { [weak self, weak model] in
                guard let self, let model else { return }
                await ShareSafeService.shareSafe(
                    image: image,
                    fileURL: fileURL,
                    from: view,
                    style: appState.settings.shareSafeRedactionStyle,
                    useSmartScan: appState.settings.shareSafeSmartScan,
                    usePrivacyFilter: appState.settings.shareSafePrivacyFilter,
                    redactBeforeSharing: appState.settings.shareSafeRedactBeforeSharing
                )
                guard currentModel === model else { return }
                model.isPrivacyScanPending = false
                shareSafeTask = nil
                self.scheduleDismiss()
            }
            }
        }
        model.onClose = { [weak self] in self?.dismiss() }
        model.onHoverChanged = { [weak self] hovering in
            if hovering || model.isPrivacyScanPending || model.uploadState == .uploading {
                self?.dismissTimer?.invalidate()
            } else {
                self?.scheduleDismiss()
            }
        }

        let view = FloatingThumbnailView(
            model: model,
            showActionsAlways: appState.settings.showThumbnailActionsAlways
        )
        let hosting = ThumbnailHostingView(rootView: view)
        hosting.onSwipe = { [weak self, weak model] fingers, direction in
            guard let self, let model else { return }
            if self.isThumbnailTucked {
                if direction == .up { self.restoreThumbnailIfTucked() }
                return
            }
            let gestureAction = self.appState.settings.thumbnailSwipeBindings.action(
                for: fingers,
                direction: direction
            )
            switch gestureAction {
            case .none:
                return
            case .dismiss:
                self.dismiss()
            case .tuck:
                self.tuckThumbnail()
            case .keep:
                guard !model.isPrivacyScanPending else { return }
                self.appState.pinController.pinThumbnailInCorner(image: image, sourceScale: sourceScale)
                self.dismiss()
            default:
                guard !model.isPrivacyScanPending,
                      let action = gestureAction.thumbnailAction,
                      model.availableActions.contains(action)
                else { return }
                model.onAction?(action)
            }
        }
        hosting.onReveal = { [weak self] in self?.restoreThumbnailIfTucked() }
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.layoutSubtreeIfNeeded()
        var contentSize = hosting.intrinsicContentSize
        if contentSize.width < 40 || contentSize.height < 40 {
            contentSize = CGSize(width: 296, height: 248)
        }
        hosting.frame = CGRect(origin: .zero, size: contentSize)

        let panel = ThumbnailPanel(contentRect: hosting.frame,
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        panel.title = "\(captureKind.label) Quick Access"
        panel.onTwoFingerSwipe = { direction in hosting.onSwipe?(.two, direction) }
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting

        var origin = panel.frame.origin
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let screen {
            let vf = screen.visibleFrame
            origin = NSPoint(x: vf.minX + 20, y: vf.minY + 20)
            // Keep the full panel inside the visible frame when action buttons are shown.
            origin.x = min(origin.x, vf.maxX - contentSize.width - 8)
            origin.y = min(origin.y, vf.maxY - contentSize.height - 8)
        }
        panel.setFrameOrigin(origin)
        untuckedOrigin = origin

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !reduceMotion {
            panel.alphaValue = 0
            panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y - AeroTokens.Spacing.medium))
        }
        panel.orderFrontRegardless()
        panel.contentView?.displayIfNeeded()
        PerformanceInstrumentation.signposter.endInterval("ThumbnailVisible", visibleState)
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = AeroTokens.Motion.standardDuration
                panel.animator().alphaValue = 1
                panel.animator().setFrameOrigin(origin)
            }
        }
        self.panel = panel
        if !model.isPrivacyScanPending, model.uploadState != .uploading {
            scheduleDismiss()
        }
    }

    private func performProtectedAction(
        image: CGImage,
        fileURL: URL?,
        model: ThumbnailModel,
        action: @escaping @MainActor (CGImage, URL?) -> Void
    ) {
        dismissTimer?.invalidate()
        dismissTimer = nil
        model.isPrivacyScanPending = true
        shareSafeTask?.cancel()
        shareSafeTask = Task { [weak self, weak model] in
            guard let self, let model else { return }
            do {
                let result = try await appState.prepareCaptureOutput(image)
                try Task.checkCancellation()
                action(result.image, result.matchCount == 0 ? fileURL : nil)
            } catch is CancellationError {
                return
            } catch {
                ToastController.shared.show(
                    "Sensitive-data scan failed. Nothing was copied or shared.",
                    symbol: "exclamationmark.triangle"
                )
            }
            model.isPrivacyScanPending = false
            shareSafeTask = nil
            if currentModel === model { scheduleDismiss() }
        }
    }

    private func scheduleDismiss() {
        dismissTimer?.invalidate()
        guard !NSWorkspace.shared.isVoiceOverEnabled else { return }
        let duration = appState.settings.thumbnailDuration
        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismiss()
            }
        }
    }

    private func tuckThumbnail() {
        guard let panel, let visibleFrame = panel.screen?.visibleFrame, untuckedOrigin != nil else { return }
        dismissTimer?.invalidate()
        dismissTimer = nil
        let tuckedOrigin = NSPoint(x: panel.frame.minX, y: visibleFrame.minY - panel.frame.height + 18)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().setFrameOrigin(tuckedOrigin)
        }
    }

    private func restoreThumbnailIfTucked() {
        guard let panel, let untuckedOrigin, panel.frame.origin != untuckedOrigin else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().setFrameOrigin(untuckedOrigin)
        }
    }

    private var isThumbnailTucked: Bool {
        guard let panel, let untuckedOrigin else { return false }
        return panel.frame.origin != untuckedOrigin
    }

    func dismiss(animated: Bool = true) {
        dismissTimer?.invalidate()
        dismissTimer = nil
        shareSafeTask?.cancel()
        shareSafeTask = nil
        currentModel = nil
        guard let panel else {
            untuckedOrigin = nil
            return
        }
        (panel.contentView as? ThumbnailHostingView)?.onSwipe = nil
        (panel.contentView as? ThumbnailHostingView)?.onReveal = nil
        (panel as? ThumbnailPanel)?.onTwoFingerSwipe = nil
        untuckedOrigin = nil

        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            self.panel = nil
            return
        }
        let destination = NSPoint(
            x: panel.frame.minX,
            y: panel.frame.minY - AeroTokens.Spacing.small
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = AeroTokens.Motion.standardDuration
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(destination)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                panel.orderOut(nil)
                guard let self, self.panel === panel else { return }
                self.panel = nil
            }
        }
    }

    func markUploadCompleted(for fileURL: URL) {
        guard currentModel?.fileURL == fileURL else { return }
        currentModel?.uploadState = .uploaded
        scheduleDismiss()
    }

    func markUploadFailed(for fileURL: URL) {
        guard currentModel?.fileURL == fileURL else { return }
        currentModel?.uploadState = .idle
        scheduleDismiss()
    }
}
