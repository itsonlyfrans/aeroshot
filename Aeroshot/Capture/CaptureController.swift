import AppKit
import ScreenCaptureKit

/// Shared inputs for presenting a selection overlay.
struct OverlayInputs {
    let displays: [DisplayInfo]
    let windows: [WindowEnumerator.WindowInfo]
    let frozenImages: [CGDirectDisplayID: CGImage]
    let captureWindowOwner: CaptureWindowRestorationOwner?
}

/// Orchestrates capture flows: presents selection overlays, invokes
/// ScreenCaptureService, and hands results to AppState.
@MainActor
final class CaptureController {
    typealias Completion = @MainActor (CGImage?) -> Void

    private unowned let appState: AppState
    private var overlayController: SelectionOverlayController?
    private var isPreparingOverlay = false

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Full screen

    func captureFullScreen(captureWindowOwner: CaptureWindowRestorationOwner? = nil) {
        guard !appState.isRecording else {
            ToastController.shared.show("Stop the current recording first", symbol: "record.circle")
            return
        }
        guard !appState.allInOneController.isPresenting else {
            ToastController.shared.show("Finish All-in-One first", symbol: "rectangle.dashed")
            return
        }
        Task {
            var owner = captureWindowOwner
            defer { appState.restoreCaptureWindows(owner: owner) }
            guard await appState.permissions.ensurePermission() else { return }
            guard await CaptureDelay.wait(seconds: appState.settings.captureDelaySeconds) else { return }
            do {
                if captureWindowOwner == nil {
                    guard let preparedOwner = await appState.prepareForCaptureOverlay() else { return }
                    owner = preparedOwner
                }
                let displays = try await WindowEnumerator.shareableDisplays()
                let mouse = NSEvent.mouseLocation
                let target = displays.first { $0.cocoaFrame.contains(mouse) } ?? displays.first
                guard let target else { return }
                let image = try await ScreenCaptureService.captureDisplay(
                    target,
                    excludingWindows: await WindowEnumerator.ownWindows()
                )
                appState.handleCapturedImage(image)
            } catch {
                NSLog("Full screen capture failed: \(error)")
                ToastController.shared.show(
                    "Capture failed. Check Screen Recording permission and try again.",
                    symbol: "exclamationmark.triangle"
                )
            }
        }
    }

    // MARK: - Last region

    func captureLastRegion(onComplete: Completion? = nil) {
        guard !appState.allInOneController.isPresenting else {
            ToastController.shared.show("Finish All-in-One first", symbol: "rectangle.dashed")
            onComplete?(nil)
            return
        }
        Task {
            guard appState.settings.recallLastRegionEnabled else {
                ToastController.shared.show("Last region recall is off in Settings", symbol: "rectangle.dashed")
                onComplete?(nil)
                return
            }
            guard await appState.permissions.ensurePermission() else {
                onComplete?(nil)
                return
            }
            guard await CaptureDelay.wait(seconds: appState.settings.captureDelaySeconds) else {
                onComplete?(nil)
                return
            }
            do {
                let displays = try await WindowEnumerator.shareableDisplays()
                guard let region = appState.settings.lastCaptureRegion(matching: displays) else {
                    ToastController.shared.show("No previous region saved yet", symbol: "rectangle.dashed")
                    onComplete?(nil)
                    return
                }
                guard let captureWindowOwner = await appState.prepareForCaptureOverlay() else {
                    onComplete?(nil)
                    return
                }
                await completeSelection(
                    .area(cocoaRect: region.cocoaRect, display: region.display),
                    displays: displays,
                    captureWindowOwner: captureWindowOwner,
                    onComplete: onComplete
                )
            } catch {
                NSLog("Last region capture failed: \(error)")
                ToastController.shared.show(
                    "Last-region capture failed. Try selecting the region again.",
                    symbol: "exclamationmark.triangle"
                )
                onComplete?(nil)
            }
        }
    }

    // MARK: - Area (rubber-band selection)

    func beginAreaCapture(onComplete: Completion? = nil) {
        beginSelection(mode: .hybrid, onComplete: onComplete)
    }

    // MARK: - Window (hover-highlight selection)

    func beginWindowCapture(onComplete: Completion? = nil) {
        beginSelection(mode: .window, onComplete: onComplete)
    }

    private func beginSelection(mode: SelectionMode, onComplete: Completion? = nil) {
        guard overlayController == nil, !isPreparingOverlay else {
            onComplete?(nil)
            return
        }
        guard !appState.allInOneController.isPresenting else {
            ToastController.shared.show("Finish All-in-One first", symbol: "rectangle.dashed")
            onComplete?(nil)
            return
        }
        isPreparingOverlay = true
        Task { [weak self] in
            defer { self?.isPreparingOverlay = false }
            guard let self else {
                onComplete?(nil)
                return
            }
            guard await CaptureDelay.wait(seconds: appState.settings.captureDelaySeconds) else {
                onComplete?(nil)
                return
            }
            guard let inputs = await makeOverlayInputs(
                includeFrozenImages: appState.settings.freezeScreenDuringCapture
            ) else {
                ToastController.shared.show("Couldn't start capture overlay", symbol: "exclamationmark.triangle")
                onComplete?(nil)
                return
            }
            let freezesScreen = appState.settings.freezeScreenDuringCapture
            presentOverlay(inputs: inputs,
                          mode: mode,
                          freezesScreen: freezesScreen,
                          keepsSelectionOpen: true,
                          allowsMarkup: mode == .hybrid,
                          markupCompletion: { completion, markup in
                self.overlayController = nil
                guard case .selected(let result) = completion else {
                    if completion.restoresCaptureWindowsImmediately {
                        self.appState.restoreCaptureWindows(owner: inputs.captureWindowOwner)
                    }
                    onComplete?(nil)
                    return
                }
                Task {
                    await self.completeSelection(
                        result,
                        displays: inputs.displays,
                        frozenImages: freezesScreen ? inputs.frozenImages : [:],
                        markup: markup,
                        captureWindowOwner: inputs.captureWindowOwner,
                        onComplete: onComplete
                    )
                }
            })
        }
    }

    /// True while a selection overlay from this controller is on screen or preparing.
    var isPresentingOverlay: Bool { overlayController != nil || isPreparingOverlay }

    /// Builds display/window/frozen-image inputs for a selection overlay.
    func makeOverlayInputs(includeFrozenImages: Bool) async -> OverlayInputs? {
        guard overlayController == nil else { return nil }
        guard !appState.allInOneController.isPresenting else { return nil }
        return await buildOverlayInputs(includeFrozenImages: includeFrozenImages)
    }

    /// Shared overlay prep used by area/window capture and All-in-One.
    func buildOverlayInputs(includeFrozenImages: Bool) async -> OverlayInputs? {
        guard !appState.isRecording else { return nil }
        guard await appState.permissions.ensurePermission() else { return nil }
        guard let captureWindowOwner = await appState.prepareForCaptureOverlay() else { return nil }
        guard let content = try? await WindowEnumerator.overlayContent(), !content.displays.isEmpty else {
            appState.restoreCaptureWindows(owner: captureWindowOwner)
            return nil
        }
        let displays = content.displays
        var windows = content.windows
        var frozenImages: [CGDirectDisplayID: CGImage] = [:]
        if includeFrozenImages {
            for display in displays {
                frozenImages[display.displayID] = try? await ScreenCaptureService.captureDisplay(display)
            }
        }
        windows = await refineCompositedWindowFrames(
            windows,
            displays: displays,
            frozenImages: frozenImages
        )
        return OverlayInputs(
            displays: displays,
            windows: windows,
            frozenImages: frozenImages,
            captureWindowOwner: captureWindowOwner
        )
    }

    private func refineCompositedWindowFrames(
        _ windows: [WindowEnumerator.WindowInfo],
        displays: [DisplayInfo],
        frozenImages: [CGDirectDisplayID: CGImage]
    ) async -> [WindowEnumerator.WindowInfo] {
        var refined = windows
        for index in refined.indices where refined[index].isDock {
            let window = refined[index]
            guard let display = displays.first(where: { $0.scDisplay.frame.intersects(window.scFrame) }) else {
                continue
            }
            let local = GeometryConversions.scFrameToDisplayLocalTopLeft(window.scFrame, display: display)
            let included: CGImage
            if let frozenImage = frozenImages[display.displayID],
               let cropped = try? crop(frozenImage, to: local, on: display) {
                included = cropped
            } else if let captured = try? await ScreenCaptureService.captureArea(local, on: display) {
                included = captured
            } else {
                continue
            }
            guard let excluded = try? await ScreenCaptureService.captureArea(
                    local,
                    on: display,
                    excludingWindows: [window.scWindow]
                  ),
                  let pixels = Self.pixelDifferenceBounds(included: included, excluded: excluded)
            else { continue }
            let pointScaleX = local.width / CGFloat(included.width)
            let pointScaleY = local.height / CGFloat(included.height)
            let displayFrame = display.scDisplay.frame
            let frame = CGRect(
                x: displayFrame.minX + local.minX + pixels.minX * pointScaleX,
                y: displayFrame.minY + local.minY + pixels.minY * pointScaleY,
                width: pixels.width * pointScaleX,
                height: pixels.height * pointScaleY
            )
            refined[index] = WindowEnumerator.WindowInfo(
                scWindow: window.scWindow,
                scFrame: frame,
                title: window.title,
                appName: window.appName
            )
        }
        return refined
    }

    static func pixelDifferenceBounds(included: CGImage, excluded: CGImage) -> CGRect? {
        guard included.width == excluded.width,
              included.height == excluded.height,
              let includedBytes = rgbaBytes(included),
              let excludedBytes = rgbaBytes(excluded)
        else { return nil }

        var minX = included.width
        var minY = included.height
        var maxX = -1
        var maxY = -1
        for y in 0..<included.height {
            for x in 0..<included.width {
                let offset = (y * included.width + x) * 4
                let changed = (0..<3).contains {
                    abs(Int(includedBytes[offset + $0]) - Int(excludedBytes[offset + $0])) > 2
                }
                guard changed else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(
            x: minX,
            y: included.height - maxY - 1,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }

    private static func rgbaBytes(_ image: CGImage) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return rendered ? bytes : nil
    }

    private func presentOverlay(inputs: OverlayInputs,
                                mode: SelectionMode,
                                freezesScreen: Bool,
                                keepsSelectionOpen: Bool = false,
                                allowsMarkup: Bool = false,
                                completion: @escaping (SelectionOverlayCompletion) -> Void) {
        let controller = SelectionOverlayController(
            displays: inputs.displays,
            windows: inputs.windows,
            frozenImages: inputs.frozenImages,
            mode: mode,
            aspectLock: appState.settings.selectionAspectLock,
            freezesScreen: freezesScreen,
            keepsSelectionOpen: keepsSelectionOpen,
            allowsMarkup: allowsMarkup,
            captureWindowOwner: inputs.captureWindowOwner,
            completion: completion
        )
        overlayController = controller
        controller.onContextAction = { [weak self] action, result in
            guard action == .record, let self else { return false }
            self.overlayController?.finishForCaptureContinuation()
            self.startRecordingSelection(result, captureWindowOwner: inputs.captureWindowOwner)
            return true
        }
        controller.present()
    }

    private func presentOverlay(inputs: OverlayInputs,
                                mode: SelectionMode,
                                freezesScreen: Bool,
                                keepsSelectionOpen: Bool = false,
                                allowsMarkup: Bool = false,
                                markupCompletion: @escaping (SelectionOverlayCompletion, SelectionMarkupPayload) -> Void) {
        let controller = SelectionOverlayController(
            displays: inputs.displays,
            windows: inputs.windows,
            frozenImages: inputs.frozenImages,
            mode: mode,
            aspectLock: appState.settings.selectionAspectLock,
            freezesScreen: freezesScreen,
            keepsSelectionOpen: keepsSelectionOpen,
            allowsMarkup: allowsMarkup,
            captureWindowOwner: inputs.captureWindowOwner,
            markupCompletion: markupCompletion
        )
        overlayController = controller
        controller.onContextAction = { [weak self] action, result in
            guard action == .record, let self else { return false }
            self.overlayController?.finishForCaptureContinuation()
            self.startRecordingSelection(result, captureWindowOwner: inputs.captureWindowOwner)
            return true
        }
        controller.present()
    }

    private func startRecordingSelection(
        _ result: SelectionResult,
        captureWindowOwner: CaptureWindowRestorationOwner?
    ) {
        switch result {
        case .area(let rect, let display):
            Task {
                await appState.recordingController.beginAreaRecording(
                    with: rect,
                    on: display,
                    captureWindowOwner: captureWindowOwner
                )
            }
        case .screen(let display):
            appState.recordingController.beginScreenRecording(
                on: display,
                captureWindowOwner: captureWindowOwner
            )
        case .window(let window):
            Task { [weak self] in
                guard let self,
                      let displays = try? await WindowEnumerator.shareableDisplays(),
                      let display = displays.first(where: { $0.cocoaFrame.intersects(window.cocoaFrame) })
                else {
                    self?.appState.restoreCaptureWindows(owner: captureWindowOwner)
                    return
                }
                await self.appState.recordingController.beginAreaRecording(
                    with: window.cocoaFrame,
                    on: display,
                    captureWindowOwner: captureWindowOwner
                )
            }
        }
    }

    func completeSelection(
        _ result: SelectionResult,
        displays: [DisplayInfo],
        frozenImages: [CGDirectDisplayID: CGImage] = [:],
        markup: SelectionMarkupPayload = SelectionMarkupPayload(),
        captureWindowOwner: CaptureWindowRestorationOwner? = nil,
        onComplete: Completion? = nil
    ) async {
        defer { appState.restoreCaptureWindows(owner: captureWindowOwner) }
        do {
            switch result {
            case .area(let cocoaRect, let display):
                appState.settings.saveLastCaptureRegion(cocoaRect: cocoaRect, displayID: display.displayID)
                let local = GeometryConversions.cocoaGlobalToDisplayLocalTopLeft(cocoaRect, screen: display.nsScreen)
                let annotations = markup.annotations(for: display)
                let image: CGImage
                if let frozenImage = frozenImages[display.displayID] {
                    let annotated = AnnotationRenderer.render(annotations, over: frozenImage) ?? frozenImage
                    image = try crop(annotated, to: local, on: display)
                } else if !annotations.isEmpty {
                    let fullDisplay = try await ScreenCaptureService.captureDisplay(display)
                    let annotated = AnnotationRenderer.render(annotations, over: fullDisplay) ?? fullDisplay
                    image = try crop(annotated, to: local, on: display)
                } else {
                    image = try await ScreenCaptureService.captureArea(local, on: display)
                }
                appState.handleCapturedImage(image)
                onComplete?(image)
            case .window(let windowInfo):
                let screen = GeometryConversions.screen(containing:
                    NSPoint(x: windowInfo.cocoaFrame.midX, y: windowInfo.cocoaFrame.midY))
                guard let display = displays.first(where: { $0.nsScreen == screen }) ?? displays.first else {
                    onComplete?(nil)
                    return
                }
                if windowInfo.isDock {
                    let local = GeometryConversions.scFrameToDisplayLocalTopLeft(
                        windowInfo.scFrame,
                        display: display
                    )
                    let image = if let frozenImage = frozenImages[display.displayID] {
                        try crop(frozenImage, to: local, on: display)
                    } else {
                        try await ScreenCaptureService.captureArea(local, on: display)
                    }
                    appState.handleCapturedImage(image)
                    onComplete?(image)
                    return
                }
                if display.cocoaFrame.contains(windowInfo.cocoaFrame),
                   let frozenImage = frozenImages[display.displayID] {
                    let local = GeometryConversions.cocoaGlobalToDisplayLocalTopLeft(
                        windowInfo.cocoaFrame,
                        screen: display.nsScreen
                    )
                    let image = try crop(frozenImage, to: local, on: display)
                    appState.handleCapturedImage(image)
                    onComplete?(image)
                    return
                }
                guard let resolved = try await WindowEnumerator.resolve(windowInfo) else {
                    onComplete?(nil)
                    return
                }
                let image = try await ScreenCaptureService.captureWindow(resolved.scWindow, on: display)
                appState.handleCapturedImage(image)
                onComplete?(image)
            case .screen(let display):
                let image: CGImage
                if let frozenImage = frozenImages[display.displayID] {
                    image = frozenImage
                } else {
                    image = try await ScreenCaptureService.captureDisplay(display)
                }
                appState.handleCapturedImage(image)
                onComplete?(image)
            }
        } catch {
            NSLog("Capture failed: \(error)")
            ToastController.shared.show(
                "Capture failed. Check Screen Recording permission and try again.",
                symbol: "exclamationmark.triangle"
            )
            onComplete?(nil)
        }
    }

    // MARK: - Area selection for scrolling capture

    /// Runs the area selection UI and returns the chosen rect without capturing.
    func selectArea(
        mode: SelectionMode = .area
    ) async -> (rect: CGRect, display: DisplayInfo, captureWindowOwner: CaptureWindowRestorationOwner?)? {
        guard overlayController == nil, !isPreparingOverlay,
              !appState.allInOneController.isPresenting else { return nil }
        isPreparingOverlay = true
        defer { isPreparingOverlay = false }
        guard await CaptureDelay.wait(seconds: appState.settings.captureDelaySeconds) else { return nil }
        guard let inputs = await makeOverlayInputs(includeFrozenImages: false) else { return nil }
        return await withCheckedContinuation { continuation in
            presentOverlay(inputs: inputs, mode: mode, freezesScreen: false) { [weak self] completion in
                self?.overlayController = nil
                if case .selected(.area(let rect, let display)) = completion {
                    continuation.resume(returning: (rect, display, inputs.captureWindowOwner))
                } else {
                    self?.appState.restoreCaptureWindows(owner: inputs.captureWindowOwner)
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func crop(_ image: CGImage, to rect: CGRect, on display: DisplayInfo) throws -> CGImage {
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
}
