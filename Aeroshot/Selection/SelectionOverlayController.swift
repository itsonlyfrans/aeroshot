import AppKit
import os
import ScreenCaptureKit

enum SelectionMode: Equatable {
    case hybrid
    case area
    case window
    case screen
    case scrolling
}

enum SelectionSurfaceIntent: String, CaseIterable, Hashable {
    case area, window, screen, scroll, record, text

    init(mode: SelectionMode) {
        switch mode {
        case .window: self = .window
        case .screen: self = .screen
        case .scrolling: self = .scroll
        case .hybrid, .area: self = .area
        }
    }

    var title: String { rawValue.capitalized }

    var key: String {
        String((Self.allCases.firstIndex(of: self) ?? 0) + 1)
    }

    var selectionMode: SelectionMode {
        switch self {
        case .area: .hybrid
        case .window: .window
        case .screen: .screen
        case .scroll: .scrolling
        case .record, .text: .area
        }
    }

    var routedKeyCode: UInt16 {
        switch self {
        case .area: 18
        case .window: 19
        case .screen: 20
        case .scroll: 21
        case .record: 23
        case .text: 26
        }
    }

    var symbol: String {
        switch self {
        case .area: return "⌗"
        case .window: return "▣"
        case .screen: return "▤"
        case .scroll: return "↕"
        case .record: return "●"
        case .text: return "T"
        }
    }
}

enum SelectionSurfaceAction: Hashable {
    case copy, save, annotate, pin, shareSafe, grabText, record, dismiss

    var label: String {
        switch self {
        case .copy: "⧉  Copy  ⏎"
        case .save: "↓  Save"
        case .annotate: "✎  Annotate"
        case .pin: "⌖  Pin"
        case .shareSafe: "◍  ShareSafe"
        case .grabText: "⌶  Grab text"
        case .record: "●  Record"
        case .dismiss: "Esc"
        }
    }

    var requiresProtectedCaptureOutput: Bool { self == .copy }
}

enum SelectionResult {
    case area(cocoaRect: CGRect, display: DisplayInfo)
    case window(WindowEnumerator.WindowInfo)
    case screen(DisplayInfo)
}

enum SelectionOverlayCompletion {
    case selected(SelectionResult)
    case cancelled
    case continuesCapture

    var restoresCaptureWindowsImmediately: Bool {
        if case .cancelled = self { return true }
        return false
    }
}

/// Markup stays attached to its source display until the still image is made.
struct SelectionMarkupPayload {
    private(set) var annotationsByDisplay: [CGDirectDisplayID: [Annotation]] = [:]

    init(_ annotationsByDisplay: [CGDirectDisplayID: [Annotation]] = [:]) {
        self.annotationsByDisplay = annotationsByDisplay
    }

    func annotations(for display: DisplayInfo) -> [Annotation] {
        annotationsByDisplay[display.displayID] ?? []
    }
}

enum RetainedAreaMarkupCapturePolicy: Equatable {
    case frozenFullDisplay
    case liveFullDisplay
    case liveArea

    static func select(freezesScreen: Bool, hasFrozenDisplay: Bool, hasAnnotations: Bool) -> Self {
        if freezesScreen, hasFrozenDisplay { return .frozenFullDisplay }
        return hasAnnotations ? .liveFullDisplay : .liveArea
    }

    var requiresCompositorSettle: Bool { self != .frozenFullDisplay }
}

enum SelectionMarkupUndoRouting {
    static func target(activeDisplayID: CGDirectDisplayID?, availableDisplayIDs: [CGDirectDisplayID]) -> CGDirectDisplayID? {
        guard let activeDisplayID, availableDisplayIDs.contains(activeDisplayID) else { return nil }
        return activeDisplayID
    }
}

struct FrozenDisplayFragment {
    let frame: CGRect
    let image: CGImage
    let scale: CGFloat
}

enum FrozenWindowCompositor {
    static func compose(
        windowFrame: CGRect,
        fragments: [FrozenDisplayFragment]
    ) -> (image: CGImage, sourceScale: CGFloat)? {
        guard !windowFrame.isEmpty else { return nil }
        let visible = fragments.compactMap { fragment -> (FrozenDisplayFragment, CGRect)? in
            let intersection = fragment.frame.intersection(windowFrame)
            return intersection.isEmpty ? nil : (fragment, intersection)
        }
        let coveredArea = visible.reduce(CGFloat.zero) { $0 + $1.1.width * $1.1.height }
        guard coveredArea >= windowFrame.width * windowFrame.height - 0.5 else { return nil }
        let sourceScale = visible.map(\.0.scale).filter { $0.isFinite && $0 > 0 }.max() ?? 1
        let width = Int((windowFrame.width * sourceScale).rounded())
        let height = Int((windowFrame.height * sourceScale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.interpolationQuality = .high
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        for (fragment, intersection) in visible {
            let local = CGRect(
                x: intersection.minX - fragment.frame.minX,
                y: fragment.frame.maxY - intersection.maxY,
                width: intersection.width,
                height: intersection.height
            )
            let pixelRect = GeometryConversions.imagePixelRect(
                for: local,
                displaySize: fragment.frame.size,
                imageSize: CGSize(width: fragment.image.width, height: fragment.image.height)
            )
            guard let cropped = fragment.image.cropping(to: pixelRect) else { return nil }
            let destination = CGRect(
                x: (intersection.minX - windowFrame.minX) * sourceScale,
                y: (windowFrame.maxY - intersection.maxY) * sourceScale,
                width: intersection.width * sourceScale,
                height: intersection.height * sourceScale
            )
            context.draw(cropped, in: destination)
        }
        return context.makeImage().map { ($0, sourceScale) }
    }
}

private struct RetainedCaptureRequest {
    let result: SelectionResult
    let displays: [DisplayInfo]
    let frozenImages: [CGDirectDisplayID: CGImage]
    let freezesScreen: Bool
    let markup: SelectionMarkupPayload

    var requiresCompositorSettle: Bool {
        switch result {
        case .area(_, let display):
            return RetainedAreaMarkupCapturePolicy.select(
                freezesScreen: freezesScreen,
                hasFrozenDisplay: frozenImages[display.displayID] != nil,
                hasAnnotations: !markup.annotations(for: display).isEmpty
            ).requiresCompositorSettle
        case .window(let window):
            let intersecting = displays.filter { $0.cocoaFrame.intersects(window.cocoaFrame) }
            return intersecting.isEmpty || intersecting.contains { frozenImages[$0.displayID] == nil }
        case .screen(let display):
            return frozenImages[display.displayID] == nil
        }
    }
}

/// Presents one borderless, non-activating panel per screen for area/window
/// selection. Calls completion exactly once (nil = cancelled).
@MainActor
final class SelectionOverlayController {
    private static let compositorSettleDelay: TimeInterval = 0.2

    private var panels: [SelectionPanel] = []
    private let displays: [DisplayInfo]
    private let windows: [WindowEnumerator.WindowInfo]
    private let frozenImages: [CGDirectDisplayID: CGImage]
    private(set) var mode: SelectionMode
    private(set) var aspectLock: SelectionAspectLock
    private(set) var freezesScreen: Bool
    private let captureWindowOwner: CaptureWindowRestorationOwner?
    private let showsIntentRail: Bool
    private let showsContextRail: Bool
    private let keepsSelectionOpen: Bool
    private var allowsMarkup: Bool
    private var selectedResult: SelectionResult?
    private var activeMarkupDisplayID: CGDirectDisplayID?
    private var finishedMarkup = SelectionMarkupPayload()
    private var completion: ((SelectionOverlayCompletion) -> Void)?
    private var markupCompletion: ((SelectionOverlayCompletion, SelectionMarkupPayload) -> Void)?
    private var keyMonitor: Any?
    /// Called before default Esc handling; return true to swallow the event.
    var extraKeyHandler: ((NSEvent) -> Bool)?
    /// Called when the user begins an area/scroll selection.
    var onSelectionBegan: (() -> Void)?
    /// Called when a retained All-in-One target changes.
    var onSelectionChanged: ((SelectionResult) -> Void)?
    /// Called before the compositor settle delay so companion UI can disappear too.
    var onWillFinish: (() -> Void)?
    /// Called once all overlay panels, input routing, and cursor state are ready.
    var onReady: (() -> Void)?
    /// Lets a specialized caller override a contextual rail action.
    var onContextAction: ((SelectionSurfaceAction, SelectionResult) -> Bool)?

    init(displays: [DisplayInfo],
         windows: [WindowEnumerator.WindowInfo],
         frozenImages: [CGDirectDisplayID: CGImage],
         mode: SelectionMode,
         aspectLock: SelectionAspectLock = .auto,
         freezesScreen: Bool = false,
         showsIntentRail: Bool = true,
         showsContextRail: Bool = true,
         keepsSelectionOpen: Bool = false,
         allowsMarkup: Bool = false,
         captureWindowOwner: CaptureWindowRestorationOwner? = nil,
         completion: @escaping (SelectionOverlayCompletion) -> Void) {
        self.displays = displays
        self.windows = windows
        self.frozenImages = frozenImages
        self.mode = mode
        self.aspectLock = aspectLock
        self.freezesScreen = freezesScreen
        self.captureWindowOwner = captureWindowOwner
        self.showsIntentRail = showsIntentRail
        self.showsContextRail = showsContextRail
        self.keepsSelectionOpen = keepsSelectionOpen
        self.allowsMarkup = allowsMarkup
        self.completion = completion
    }

    init(displays: [DisplayInfo],
         windows: [WindowEnumerator.WindowInfo],
         frozenImages: [CGDirectDisplayID: CGImage],
         mode: SelectionMode,
         aspectLock: SelectionAspectLock = .auto,
         freezesScreen: Bool = false,
         showsIntentRail: Bool = true,
         showsContextRail: Bool = true,
         keepsSelectionOpen: Bool = false,
         allowsMarkup: Bool = false,
         captureWindowOwner: CaptureWindowRestorationOwner? = nil,
         markupCompletion: @escaping (SelectionOverlayCompletion, SelectionMarkupPayload) -> Void) {
        self.displays = displays
        self.windows = windows
        self.frozenImages = frozenImages
        self.mode = mode
        self.aspectLock = aspectLock
        self.freezesScreen = freezesScreen
        self.captureWindowOwner = captureWindowOwner
        self.showsIntentRail = showsIntentRail
        self.showsContextRail = showsContextRail
        self.keepsSelectionOpen = keepsSelectionOpen
        self.allowsMarkup = allowsMarkup
        self.completion = { _ in }
        self.markupCompletion = markupCompletion
    }

    func present() {
        for display in displays {
            let panel = SelectionPanel(contentRect: display.nsScreen.frame,
                                       styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.acceptsMouseMovedEvents = true

            let displayWindows = WindowEnumerator.windows(on: display, in: windows)
            let view = SelectionOverlayView(display: display,
                                            windows: displayWindows,
                                            frozenImage: frozenImages[display.displayID],
                                            freezesScreen: freezesScreen,
                                            mode: mode,
                                            aspectLock: aspectLock,
                                            availableSurfaceIntents: showsIntentRail ? availableSurfaceIntents : [],
                                            showsContextRail: showsContextRail,
                                            allowsMarkup: allowsMarkup)
            view.onCommit = { [weak self] result in self?.handleSelection(result) }
            view.onCancel = { [weak self] in self?.finish(with: nil) }
            view.onSelectionBegan = { [weak self] in self?.onSelectionBegan?() }
            view.onIntentSelected = { [weak self] intent in self?.selectSurfaceIntent(intent) }
            view.onAspectLockSelected = { [weak self] lock in self?.setAspectLock(lock) }
            view.onContextAction = { [weak self] action in self?.performContextAction(action) }
            view.onSelectionMoved = { [weak self] result in self?.updateRetainedSelection(result) }
            view.onMarkupInteraction = { [weak self, display] in
                self?.activeMarkupDisplayID = display.displayID
            }
            panel.contentView = view
            panel.setFrame(display.nsScreen.frame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        focusActivePanel()
        // Global Esc handling even if no panel is key.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.extraKeyHandler?(event) == true { return nil }
            if event.modifierFlags.contains(.command), event.keyCode == 6 {
                if let panel = self.panels.first(where: { $0.windowNumber == event.windowNumber }),
                   let view = panel.contentView as? SelectionOverlayView {
                    self.activeMarkupDisplayID = view.displayID
                }
                let redo = event.modifierFlags.contains(.shift)
                if self.performMarkupUndo(redo: redo) { return nil }
            }
            if event.keyCode == 53 { // Esc
                if self.cancelInProgressMarkup() { return nil }
                self.finish(with: nil)
                return nil
            }
            return event
        }
        let ready = onReady
        onReady = nil
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                ready?()
                return
            }
            for panel in self.panels {
                guard let view = panel.contentView as? SelectionOverlayView else { continue }
                view.displayIfNeeded()
                view.activateSelectionCursor()
            }
            ready?()
        }
    }

    /// Key the overlay panel under the cursor so the first click starts selection immediately.
    func focusActivePanel() {
        let mouse = NSEvent.mouseLocation
        let panel = panels.first { $0.frame.contains(mouse) } ?? panels.first
        guard let panel, let view = panel.contentView else { return }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
        let overlay = view as? SelectionOverlayView
        activeMarkupDisplayID = overlay?.displayID
        overlay?.primePointer(at: mouse)
        overlay?.activateSelectionCursor()
    }

    func activateSelectionCursor() {
        let mouse = NSEvent.mouseLocation
        let panel = panels.first { $0.frame.contains(mouse) } ?? panels.first
        (panel?.contentView as? SelectionOverlayView)?.activateSelectionCursor()
    }

    func setAspectLock(_ lock: SelectionAspectLock) {
        aspectLock = lock
        for panel in panels {
            (panel.contentView as? SelectionOverlayView)?.setAspectLock(lock)
        }
    }

    func setFreezesScreen(_ enabled: Bool) {
        freezesScreen = enabled
        for panel in panels {
            (panel.contentView as? SelectionOverlayView)?.setFreezesScreen(enabled)
        }
    }

    func setMode(_ newMode: SelectionMode) {
        mode = newMode
        selectedResult = nil
        for panel in panels {
            (panel.contentView as? SelectionOverlayView)?.setMode(newMode)
        }
    }

    func setAllowsMarkup(_ enabled: Bool) {
        allowsMarkup = enabled
        for panel in panels {
            (panel.contentView as? SelectionOverlayView)?.setAllowsMarkup(enabled)
        }
    }

    private func selectSurfaceIntent(_ intent: SelectionSurfaceIntent) {
        guard availableSurfaceIntents.contains(intent) else { return }
        let routed = makeKeyEvent(keyCode: intent.routedKeyCode).map { extraKeyHandler?($0) == true } ?? false
        if !routed {
            // Record/Text are only meaningful when a caller owns their route
            // (for example All-in-One). Never silently turn either into an
            // ordinary still-area capture.
            guard intent != .record, intent != .text else { return }
            setMode(intent.selectionMode)
        }
        for panel in panels {
            (panel.contentView as? SelectionOverlayView)?.setSurfaceIntent(intent)
        }
        focusActivePanel()
    }

    private var availableSurfaceIntents: [SelectionSurfaceIntent] {
        guard extraKeyHandler != nil else {
            return SelectionSurfaceIntent.allCases.filter { $0 != .record && $0 != .text }
        }
        return SelectionSurfaceIntent.allCases
    }

    private func makeKeyEvent(keyCode: UInt16) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )
    }

    func selectScreen(at point: NSPoint = NSEvent.mouseLocation) {
        setMode(.screen)
        guard let display = displays.first(where: { $0.cocoaFrame.contains(point) }) ?? displays.first else { return }
        handleSelection(.screen(display))
    }

    func commitSelection() {
        guard let selectedResult else { return }
        finish(with: selectedResult)
    }

    func dismiss() {
        guard completion != nil else { return }
        finish(with: nil)
    }

    func finishForCaptureContinuation() {
        guard completion != nil else { return }
        finish(with: nil, outcome: .continuesCapture)
    }

    private func handleSelection(_ result: SelectionResult) {
        let state = PerformanceInstrumentation.signposter.beginInterval("SelectionCommit")
        defer {
            PerformanceInstrumentation.signposter.endInterval("SelectionCommit", state)
        }
        guard keepsSelectionOpen else {
            finish(with: result)
            return
        }
        selectedResult = result
        for panel in panels {
            (panel.contentView as? SelectionOverlayView)?.retainSelection(result)
        }
        onSelectionChanged?(result)
    }

    private func updateRetainedSelection(_ result: SelectionResult) {
        guard keepsSelectionOpen else { return }
        selectedResult = result
        onSelectionChanged?(result)
    }

    private func performContextAction(_ action: SelectionSurfaceAction) {
        guard let selectedResult else { return }
        if action == .dismiss {
            finish(with: nil)
            return
        }
        if onContextAction?(action, selectedResult) == true { return }

        let request = RetainedCaptureRequest(
            result: selectedResult,
            displays: displays,
            frozenImages: frozenImages,
            freezesScreen: freezesScreen,
            markup: markupPayload()
        )
        let captureAndApply: () -> Void = {
            Task {
                guard let capture = try? await Self.captureImage(for: request) else {
                    (NSApp.delegate as? AppDelegate)?.appState.restoreCaptureWindows(owner: self.captureWindowOwner)
                    ToastController.shared.show("Capture failed", symbol: "exclamationmark.triangle")
                    return
                }
                (NSApp.delegate as? AppDelegate)?.appState.restoreCaptureWindows(owner: self.captureWindowOwner)
                await Self.apply(action, to: capture.image, sourceScale: capture.sourceScale)
            }
            return
        }
        finish(
            with: nil,
            outcome: .continuesCapture,
            afterCleanup: request.requiresCompositorSettle ? nil : captureAndApply,
            afterSettled: request.requiresCompositorSettle ? captureAndApply : nil
        )
    }

    private static func captureImage(
        for request: RetainedCaptureRequest
    ) async throws -> (image: CGImage, sourceScale: CGFloat) {
        switch request.result {
        case .area(let cocoaRect, let display):
            let local = GeometryConversions.cocoaGlobalToDisplayLocalTopLeft(cocoaRect, screen: display.nsScreen)
            let annotations = request.markup.annotations(for: display)
            switch RetainedAreaMarkupCapturePolicy.select(
                freezesScreen: request.freezesScreen,
                hasFrozenDisplay: request.frozenImages[display.displayID] != nil,
                hasAnnotations: !annotations.isEmpty
            ) {
            case .frozenFullDisplay:
                let frozen = request.frozenImages[display.displayID]!
                let image = AnnotationRenderer.render(annotations, over: frozen) ?? frozen
                return (try crop(image, to: local, on: display), display.scale)
            case .liveFullDisplay:
                let fullDisplay = try await ScreenCaptureService.captureDisplay(display)
                let image = AnnotationRenderer.render(annotations, over: fullDisplay) ?? fullDisplay
                return (try crop(image, to: local, on: display), display.scale)
            case .liveArea:
                return (try await ScreenCaptureService.captureArea(local, on: display), display.scale)
            }
        case .window(let window):
            let intersecting = request.displays.filter { $0.cocoaFrame.intersects(window.cocoaFrame) }
            guard let display = intersecting.first ?? request.displays.first else {
                throw ScreenCaptureService.CaptureError.captureFailed
            }
            let fragments = intersecting.compactMap { candidate -> FrozenDisplayFragment? in
                guard let image = request.frozenImages[candidate.displayID] else { return nil }
                return FrozenDisplayFragment(frame: candidate.cocoaFrame, image: image, scale: candidate.scale)
            }
            if fragments.count == intersecting.count,
               let composite = FrozenWindowCompositor.compose(
                windowFrame: window.cocoaFrame,
                fragments: fragments
               ) {
                return composite
            }
            guard let resolved = try await WindowEnumerator.resolve(window) else {
                throw ScreenCaptureService.CaptureError.captureFailed
            }
            return (try await ScreenCaptureService.captureWindow(resolved, on: display), display.scale)
        case .screen(let display):
            if let frozen = request.frozenImages[display.displayID] { return (frozen, display.scale) }
            return (try await ScreenCaptureService.captureDisplay(display), display.scale)
        }
    }

    private static func crop(_ image: CGImage, to rect: CGRect, on display: DisplayInfo) throws -> CGImage {
        let pixelRect = GeometryConversions.imagePixelRect(
            for: rect,
            displaySize: display.cocoaFrame.size,
            imageSize: CGSize(width: image.width, height: image.height)
        )
        guard !pixelRect.isNull, !pixelRect.isEmpty,
              let cropped = image.cropping(to: pixelRect) else {
            throw ScreenCaptureService.CaptureError.captureFailed
        }
        return cropped
    }

    private static func apply(
        _ action: SelectionSurfaceAction,
        to image: CGImage,
        sourceScale: CGFloat
    ) async {
        guard let appState = (NSApp.delegate as? AppDelegate)?.appState else { return }
        let output: CGImage
        if action.requiresProtectedCaptureOutput {
            do {
                output = try await appState.prepareCaptureOutput(image).image
            } catch {
                appState.openEditor(with: image, sourceScale: sourceScale)
                ToastController.shared.show(
                    "Sensitive-data scan failed — capture opened for review. Nothing was saved or copied.",
                    symbol: "exclamationmark.triangle"
                )
                return
            }
        } else {
            output = image
        }
        switch action {
        case .copy:
            if PasteboardWriter.copy(image: output, fileURL: nil, sourceScale: sourceScale) {
                ToastController.shared.show("Copied to clipboard", symbol: "doc.on.doc")
                if appState.settings.openEditorAfterCapture {
                    appState.openEditor(with: output, sourceScale: sourceScale)
                }
            }
        case .save:
            let settings = appState.settings
            let url = settings.newFileURL()
            do {
                try ImageExporter.write(
                    output,
                    to: url,
                    format: settings.imageFormat,
                    jpegQuality: settings.jpegQuality,
                    scale: sourceScale,
                    downscaleToPoints: settings.downscaleRetina
                )
                ToastController.shared.show("Saved to \(url.deletingLastPathComponent().lastPathComponent)", symbol: "square.and.arrow.down")
            } catch {
                ToastController.shared.show("Couldn’t save screenshot", symbol: "exclamationmark.triangle")
            }
        case .annotate:
            appState.openEditor(with: image, sourceScale: sourceScale)
        case .pin:
            appState.pinController.pin(image: image, sourceScale: sourceScale)
        case .shareSafe:
            let settings = appState.settings
            await ShareSafeService.shareSafe(
                image: image,
                fileURL: nil,
                from: nil,
                style: settings.shareSafeRedactionStyle,
                useSmartScan: settings.shareSafeSmartScan,
                usePrivacyFilter: settings.shareSafePrivacyFilter,
                redactBeforeSharing: settings.shareSafeRedactBeforeSharing
            )
        case .grabText:
            let text = (try? await OCRService.recognizeText(in: image)) ?? ""
            guard !text.isEmpty else {
                ToastController.shared.show("No text found", symbol: "text.viewfinder")
                return
            }
            PasteboardWriter.copy(text: text)
            ToastController.shared.show("Text copied", symbol: "text.viewfinder")
        case .record, .dismiss:
            break
        }
    }

    private func finish(
        with result: SelectionResult?,
        outcome: SelectionOverlayCompletion? = nil,
        afterCleanup: (() -> Void)? = nil,
        afterSettled: (() -> Void)? = nil
    ) {
        guard let completion else { return }
        self.completion = nil
        let markupCompletion = self.markupCompletion
        self.markupCompletion = nil
        let markup = markupPayload()
        finishedMarkup = markup
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        for panel in panels {
            panel.ignoresMouseEvents = true
            panel.orderOut(nil)
        }
        panels.removeAll()
        onWillFinish?()
        onWillFinish = nil
        afterCleanup?()
        let outcome = outcome ?? result.map(SelectionOverlayCompletion.selected) ?? .cancelled
        guard result != nil || afterSettled != nil else {
            completion(outcome)
            markupCompletion?(outcome, markup)
            return
        }
        // Let ScreenCaptureKit observe a compositor frame without AeroShot UI.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.compositorSettleDelay) {
            completion(outcome)
            markupCompletion?(outcome, markup)
            afterSettled?()
        }
    }

    private func markupPayload() -> SelectionMarkupPayload {
        SelectionMarkupPayload(Dictionary(uniqueKeysWithValues: panels.compactMap { panel in
            guard let view = panel.contentView as? SelectionOverlayView else { return nil }
            return (view.displayID, view.markupAnnotations)
        }.filter { !$0.1.isEmpty }))
    }

    private func cancelInProgressMarkup() -> Bool {
        panels.contains { ($0.contentView as? SelectionOverlayView)?.cancelInProgressMarkup() == true }
    }

    private func performMarkupUndo(redo: Bool) -> Bool {
        guard let displayID = SelectionMarkupUndoRouting.target(
            activeDisplayID: activeMarkupDisplayID,
            availableDisplayIDs: panels.compactMap { ($0.contentView as? SelectionOverlayView)?.displayID }
        ), let view = panels.first(where: { ($0.contentView as? SelectionOverlayView)?.displayID == displayID })?.contentView as? SelectionOverlayView
        else { return false }
        return view.performMarkupUndo(redo: redo)
    }
}

/// Panel subclass that can become key so Esc and arrow nudges work
/// without activating the app.
final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
