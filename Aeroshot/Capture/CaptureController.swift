import AppKit
import ScreenCaptureKit

/// Shared inputs for presenting a selection overlay.
struct OverlayInputs {
    let displays: [DisplayInfo]
    let windows: [WindowEnumerator.WindowInfo]
    let frozenImages: [CGDirectDisplayID: CGImage]
}

/// Orchestrates capture flows: presents selection overlays, invokes
/// ScreenCaptureService, and hands results to AppState.
@MainActor
final class CaptureController {
    private unowned let appState: AppState
    private var overlayController: SelectionOverlayController?

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Full screen

    func captureFullScreen() {
        Task {
            guard await appState.permissions.ensurePermission() else { return }
            guard await CaptureDelay.wait(seconds: appState.settings.captureDelaySeconds) else { return }
            do {
                let displays = try await WindowEnumerator.shareableDisplays()
                let mouse = NSEvent.mouseLocation
                let target = displays.first { $0.cocoaFrame.contains(mouse) } ?? displays.first
                guard let target else { return }
                let image = try await ScreenCaptureService.captureDisplay(target)
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

    func captureLastRegion() {
        Task {
            guard appState.settings.recallLastRegionEnabled else {
                ToastController.shared.show("Last region recall is off in Settings", symbol: "rectangle.dashed")
                return
            }
            guard await appState.permissions.ensurePermission() else { return }
            guard await CaptureDelay.wait(seconds: appState.settings.captureDelaySeconds) else { return }
            do {
                let displays = try await WindowEnumerator.shareableDisplays()
                guard let region = appState.settings.lastCaptureRegion(matching: displays) else {
                    ToastController.shared.show("No previous region saved yet", symbol: "rectangle.dashed")
                    return
                }
                await completeSelection(.area(cocoaRect: region.cocoaRect, display: region.display), displays: displays)
            } catch {
                NSLog("Last region capture failed: \(error)")
                ToastController.shared.show(
                    "Last-region capture failed. Try selecting the region again.",
                    symbol: "exclamationmark.triangle"
                )
            }
        }
    }

    // MARK: - Area (rubber-band selection)

    func beginAreaCapture() {
        beginSelection(mode: .area)
    }

    // MARK: - Window (hover-highlight selection)

    func beginWindowCapture() {
        beginSelection(mode: .window)
    }

    private func beginSelection(mode: SelectionMode) {
        guard overlayController == nil else { return }
        guard !appState.allInOneController.isPresenting else {
            ToastController.shared.show("Finish All-in-One first", symbol: "rectangle.dashed")
            return
        }
        Task { [weak self] in
            guard let self else { return }
            guard await CaptureDelay.wait(seconds: appState.settings.captureDelaySeconds) else { return }
            guard let inputs = await makeOverlayInputs() else {
                ToastController.shared.show("Couldn't start capture overlay", symbol: "exclamationmark.triangle")
                return
            }
            presentOverlay(inputs: inputs, mode: mode) { result in
                self.overlayController = nil
                guard let result else { return }
                Task { await self.completeSelection(result, displays: inputs.displays) }
            }
        }
    }

    /// True while a selection overlay from this controller is on screen.
    var isPresentingOverlay: Bool { overlayController != nil }

    /// Builds display/window/frozen-image inputs for a selection overlay.
    func makeOverlayInputs() async -> OverlayInputs? {
        guard overlayController == nil else { return nil }
        guard !appState.allInOneController.isPresenting else { return nil }
        return await buildOverlayInputs()
    }

    /// Shared overlay prep used by area/window capture and All-in-One.
    func buildOverlayInputs() async -> OverlayInputs? {
        guard await appState.permissions.ensurePermission() else { return nil }
        await appState.prepareForCaptureOverlay()
        guard let displays = try? await WindowEnumerator.shareableDisplays(), !displays.isEmpty else {
            return nil
        }
        let windows = (try? await WindowEnumerator.onScreenWindows()) ?? []
        var frozenImages: [CGDirectDisplayID: CGImage] = [:]
        for display in displays {
            frozenImages[display.displayID] = try? await ScreenCaptureService.captureDisplay(display)
        }
        return OverlayInputs(displays: displays, windows: windows, frozenImages: frozenImages)
    }

    private func presentOverlay(inputs: OverlayInputs,
                                mode: SelectionMode,
                                completion: @escaping (SelectionResult?) -> Void) {
        let controller = SelectionOverlayController(
            displays: inputs.displays,
            windows: inputs.windows,
            frozenImages: inputs.frozenImages,
            mode: mode,
            aspectLock: appState.settings.selectionAspectLock,
            completion: completion
        )
        overlayController = controller
        controller.present()
    }

    func completeSelection(_ result: SelectionResult, displays: [DisplayInfo]) async {
        do {
            switch result {
            case .area(let cocoaRect, let display):
                appState.settings.saveLastCaptureRegion(cocoaRect: cocoaRect, displayID: display.displayID)
                let local = GeometryConversions.cocoaGlobalToDisplayLocalTopLeft(cocoaRect, screen: display.nsScreen)
                let image = try await ScreenCaptureService.captureArea(local, on: display)
                appState.handleCapturedImage(image)
            case .window(let windowInfo):
                let screen = GeometryConversions.screen(containing:
                    NSPoint(x: windowInfo.cocoaFrame.midX, y: windowInfo.cocoaFrame.midY))
                guard let display = displays.first(where: { $0.nsScreen == screen }) ?? displays.first else { return }
                guard let resolved = try await WindowEnumerator.resolve(windowInfo) else { return }
                let image = try await ScreenCaptureService.captureWindow(resolved.scWindow, on: display)
                appState.handleCapturedImage(image)
            }
        } catch {
            NSLog("Capture failed: \(error)")
            ToastController.shared.show(
                "Capture failed. Check Screen Recording permission and try again.",
                symbol: "exclamationmark.triangle"
            )
        }
    }

    // MARK: - Area selection for scrolling capture

    /// Runs the area selection UI and returns the chosen rect without capturing.
    func selectArea(mode: SelectionMode = .area) async -> (rect: CGRect, display: DisplayInfo)? {
        guard await CaptureDelay.wait(seconds: appState.settings.captureDelaySeconds) else { return nil }
        guard let inputs = await makeOverlayInputs() else { return nil }
        return await withCheckedContinuation { continuation in
            presentOverlay(inputs: inputs, mode: mode) { [weak self] result in
                self?.overlayController = nil
                if case .area(let rect, let display) = result {
                    continuation.resume(returning: (rect, display))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
