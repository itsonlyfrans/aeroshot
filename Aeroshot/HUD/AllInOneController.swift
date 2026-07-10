import AppKit
import ScreenCaptureKit

/// CleanShot-style All-in-One overlay: selection + floating toolbar.
@MainActor
final class AllInOneController {
    private static let compositorSettleDelay: TimeInterval = 0.2
    private unowned let appState: AppState
    private var overlayController: SelectionOverlayController?
    private var toolbar = HUDToolbarPanel()
    private var currentIntent: CaptureIntent = .area
    private var displays: [DisplayInfo] = []
    private var finished = false
    private var isPreparing = false

    /// True while the All-in-One HUD or its selection overlay is visible.
    var isPresenting: Bool { overlayController != nil || isPreparing }

    init(appState: AppState) {
        self.appState = appState
    }

    func begin() {
        guard overlayController == nil, !isPreparing else { return }

        if appState.captureController.isPresentingOverlay {
            ToastController.shared.show("Finish the current capture first", symbol: "rectangle.dashed")
            return
        }

        isPreparing = true
        Task { [weak self] in
            defer { self?.isPreparing = false }
            guard let self else { return }
            guard let inputs = await appState.captureController.buildOverlayInputs() else {
                ToastController.shared.show("Couldn't start All-in-One overlay", symbol: "exclamationmark.triangle")
                return
            }
            guard self.overlayController == nil else { return }

            displays = inputs.displays
            finished = false
            currentIntent = CaptureIntent.from(storageKey: appState.settings.lastCaptureIntentKey) ?? .area

            let initialMode = currentIntent.selectionMode ?? .area
            let controller = SelectionOverlayController(
                displays: inputs.displays,
                windows: inputs.windows,
                frozenImages: inputs.frozenImages,
                mode: initialMode,
                aspectLock: appState.settings.selectionAspectLock
            ) { result in
                self.handleOverlayResult(result)
            }
            controller.extraKeyHandler = { event in
                self.handleKeyDown(event)
            }
            controller.onSelectionBegan = { [weak self] in
                self?.toolbar.dismiss()
            }
            overlayController = controller
            controller.present()

            DispatchQueue.main.async { [weak self] in
                guard let self, self.overlayController != nil else { return }
                self.toolbar.show(
                    selected: self.currentIntent,
                    onSelect: { intent in
                        self.selectIntent(intent)
                    },
                    onCancel: {
                        self.finish(cancelled: true)
                    }
                )
                self.overlayController?.focusActivePanel()
            }
        }
    }

    private func selectIntent(_ intent: CaptureIntent) {
        currentIntent = intent
        appState.settings.lastCaptureIntentKey = intent.storageKey
        toolbar.setSelected(intent)
        if intent.isInstant {
            finish(cancelled: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.compositorSettleDelay) { [weak self] in
                self?.dispatchInstant(intent)
            }
            return
        }
        if let mode = intent.selectionMode {
            overlayController?.setMode(mode)
            overlayController?.focusActivePanel()
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
