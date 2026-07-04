import AppKit
import ScreenCaptureKit

/// CleanShot-style All-in-One overlay: selection + floating toolbar.
@MainActor
final class AllInOneController {
    private unowned let appState: AppState
    private var overlayController: SelectionOverlayController?
    private var toolbar = HUDToolbarPanel()
    private var currentIntent: CaptureIntent = .area
    private var displays: [DisplayInfo] = []
    private var finished = false

    init(appState: AppState) {
        self.appState = appState
    }

    func begin() {
        guard overlayController == nil, !finished else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let inputs = await appState.captureController.makeOverlayInputs() else { return }
            displays = inputs.displays
            finished = false
            currentIntent = CaptureIntent.from(storageKey: appState.settings.lastCaptureIntentKey) ?? .area

            let initialMode = currentIntent.selectionMode ?? .area
            let controller = SelectionOverlayController(
                displays: inputs.displays,
                windows: inputs.windows,
                frozenImages: inputs.frozenImages,
                mode: initialMode
            ) { result in
                self.handleOverlayResult(result)
            }
            controller.extraKeyHandler = { event in
                self.handleKeyDown(event)
            }
            overlayController = controller
            controller.present()

            toolbar.show(selected: currentIntent,
                         onSelect: { intent in
                             self.selectIntent(intent)
                         },
                         onCancel: {
                             self.finish(cancelled: true)
                         })
        }
    }

    private func selectIntent(_ intent: CaptureIntent) {
        currentIntent = intent
        appState.settings.lastCaptureIntentKey = intent.storageKey
        toolbar.setSelected(intent)
        if intent.isInstant {
            finish(cancelled: false)
            dispatchInstant(intent)
            return
        }
        if let mode = intent.selectionMode {
            overlayController?.setMode(mode)
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if let intent = CaptureIntent.forDigit(event.keyCode) {
            selectIntent(intent)
            return true
        }
        return false
    }

    private func handleOverlayResult(_ result: SelectionResult?) {
        guard !finished else { return }
        guard let result else {
            finish(cancelled: true)
            return
        }
        let intent = currentIntent
        finish(cancelled: false)
        dispatchSelection(result, intent: intent)
    }

    private func finish(cancelled: Bool) {
        guard !finished else { return }
        finished = true
        toolbar.dismiss()
        overlayController?.dismiss()
        overlayController = nil
        if cancelled {
            displays = []
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.finished = false
        }
    }

    private func dispatchInstant(_ intent: CaptureIntent) {
        switch intent {
        case .fullScreen:
            appState.captureController.captureFullScreen()
        case .recordScreen:
            appState.recordingController.beginScreenRecording()
        default:
            break
        }
    }

    private func dispatchSelection(_ result: SelectionResult, intent: CaptureIntent) {
        Task {
            switch intent {
            case .area:
                await appState.captureController.completeSelection(result, displays: displays)
            case .window:
                await appState.captureController.completeSelection(result, displays: displays)
            case .scrolling:
                if case .area(let rect, let display) = result {
                    appState.scrollingCaptureController.begin(with: rect, on: display)
                }
            case .recordArea:
                if case .area(let rect, let display) = result {
                    await appState.recordingController.beginAreaRecording(with: rect, on: display)
                }
            case .ocr:
                if case .area(let rect, let display) = result {
                    await appState.ocrCaptureController.process(cocoaRect: rect, display: display)
                }
            case .fullScreen, .recordScreen:
                break
            }
        }
    }
}
