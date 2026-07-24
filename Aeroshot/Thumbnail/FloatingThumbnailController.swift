import AppKit
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
/// corner after each capture, with copy/save/edit/pin/OCR actions.
@MainActor
final class FloatingThumbnailController {
    private unowned let appState: AppState
    private var panel: NSPanel?
    private var dismissTimer: Timer?
    private var untuckedOrigin: NSPoint?

    init(appState: AppState) {
        self.appState = appState
    }

    func show(
        image: CGImage,
        fileURL: URL?,
        privacyScanPending: Bool = false,
        unavailableActions: Set<ThumbnailAction> = []
    ) {
        dismiss()

        let model = ThumbnailModel(
            image: image,
            fileURL: fileURL,
            isPrivacyScanPending: privacyScanPending
        )
        model.availableActions = ThumbnailAction.allCases.filter { !unavailableActions.contains($0) }
        model.visibleActions = appState.settings.thumbnailVisibleActions.filter { !unavailableActions.contains($0) }
        model.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .copy:
            if PasteboardWriter.copy(image: image, fileURL: fileURL) {
                ToastController.shared.show("Copied to clipboard", symbol: "doc.on.doc")
            } else {
                ToastController.shared.show("Copy failed", symbol: "exclamationmark.triangle")
            }
            self.dismiss()
            case .save:
            let url = self.appState.settings.newFileURL()
            do {
                try ImageExporter.write(image, to: url, format: self.appState.settings.imageFormat)
                ToastController.shared.show("Saved", symbol: "square.and.arrow.down")
                NSWorkspace.shared.activateFileViewerSelecting([url])
                self.dismiss()
            } catch {
                ToastController.shared.show(
                    "Couldn’t save screenshot. Check the save folder and available space.",
                    symbol: "exclamationmark.triangle"
                )
            }
            case .edit:
            self.appState.openEditor(with: image)
            self.dismiss()
            case .pin:
            self.appState.pinController.pin(image: image)
            self.dismiss()
            case .ocr:
            Task { [weak self] in
                if let text = try? await OCRService.recognizeText(in: image) {
                    PasteboardWriter.copy(text: text)
                }
                self?.dismiss()
            }
            case .share:
            guard let view = self.panel?.contentView else { return }
            ShareService.shareImage(image, fileURL: fileURL, from: view)
            case .shareSafe:
            guard let view = self.panel?.contentView else { return }
            Task {
                await ShareSafeService.shareSafe(
                    image: image,
                    fileURL: fileURL,
                    from: view,
                    style: self.appState.settings.shareSafeRedactionStyle,
                    useSmartScan: self.appState.settings.shareSafeSmartScan,
                    usePrivacyFilter: self.appState.settings.shareSafePrivacyFilter,
                    redactBeforeSharing: self.appState.settings.shareSafeRedactBeforeSharing
                )
            }
            }
        }
        model.onClose = { [weak self] in self?.dismiss() }
        model.onHoverChanged = { [weak self] hovering in
            if hovering {
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
                self.appState.pinController.pinThumbnailInCorner(image: image)
                ToastController.shared.show("Kept in corner", symbol: "pin.fill")
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
        panel.onTwoFingerSwipe = { direction in hosting.onSwipe?(.two, direction) }
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let screen {
            let vf = screen.visibleFrame
            var origin = NSPoint(x: vf.minX + 20, y: vf.minY + 20)
            // Keep the full panel inside the visible frame when action buttons are shown.
            origin.x = min(origin.x, vf.maxX - contentSize.width - 8)
            origin.y = min(origin.y, vf.maxY - contentSize.height - 8)
            panel.setFrameOrigin(origin)
            untuckedOrigin = origin
        }
        panel.orderFrontRegardless()
        self.panel = panel
        scheduleDismiss()
    }

    private func scheduleDismiss() {
        dismissTimer?.invalidate()
        let duration = appState.settings.thumbnailDuration
        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismiss()
            }
        }
    }

    private func tuckThumbnail() {
        guard let panel, let visibleFrame = panel.screen?.visibleFrame, untuckedOrigin != nil else { return }
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

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        (panel?.contentView as? ThumbnailHostingView)?.onSwipe = nil
        (panel?.contentView as? ThumbnailHostingView)?.onReveal = nil
        (panel as? ThumbnailPanel)?.onTwoFingerSwipe = nil
        panel?.orderOut(nil)
        panel = nil
        untuckedOrigin = nil
    }
}
