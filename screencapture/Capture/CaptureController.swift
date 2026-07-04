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
            do {
                let displays = try await WindowEnumerator.shareableDisplays()
                let mouse = NSEvent.mouseLocation
                let target = displays.first { $0.cocoaFrame.contains(mouse) } ?? displays.first
                guard let target else { return }
                let image = try await ScreenCaptureService.captureDisplay(target)
                appState.handleCapturedImage(image)
            } catch {
                NSLog("Full screen capture failed: \(error)")
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
        Task { [weak self] in
            guard let self else { return }
            guard let inputs = await makeOverlayInputs() else { return }
            presentOverlay(inputs: inputs, mode: mode) { result in
                self.overlayController = nil
                guard let result else { return }
                Task { await self.completeSelection(result, displays: inputs.displays) }
            }
        }
    }

    /// Builds display/window/frozen-image inputs for a selection overlay.
    func makeOverlayInputs() async -> OverlayInputs? {
        guard await appState.permissions.ensurePermission() else { return nil }
        guard overlayController == nil else { return nil }
        guard let displays = try? await WindowEnumerator.shareableDisplays() else { return nil }
        let windows = (try? await WindowEnumerator.onScreenWindows()) ?? []
        var frozen: [CGDirectDisplayID: CGImage] = [:]
        for display in displays {
            frozen[display.displayID] = try? await ScreenCaptureService.captureDisplay(display)
        }
        return OverlayInputs(displays: displays, windows: windows, frozenImages: frozen)
    }

    private func presentOverlay(inputs: OverlayInputs,
                                mode: SelectionMode,
                                completion: @escaping (SelectionResult?) -> Void) {
        let controller = SelectionOverlayController(
            displays: inputs.displays,
            windows: inputs.windows,
            frozenImages: inputs.frozenImages,
            mode: mode,
            completion: completion
        )
        overlayController = controller
        controller.present()
    }

    func completeSelection(_ result: SelectionResult, displays: [DisplayInfo]) async {
        do {
            switch result {
            case .area(let cocoaRect, let display):
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
        }
    }

    // MARK: - Area selection for scrolling capture

    /// Runs the area selection UI and returns the chosen rect without capturing.
    func selectArea(mode: SelectionMode = .area) async -> (rect: CGRect, display: DisplayInfo)? {
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
