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
    private var frozenImages: [CGDirectDisplayID: CGImage] = [:]
    private var freezesScreen = false
    private var finished = false
    private var isPreparing = false
    private var pendingRecordingOptions: HUDRecordingOptions?
    private var selectedResult: SelectionResult?

    /// True while the All-in-One HUD or its selection overlay is visible.
    var isPresenting: Bool { overlayController != nil || isPreparing || toolbar.model != nil }

    init(appState: AppState) {
        self.appState = appState
    }

    func begin() {
        guard !isPresenting else {
            ToastController.shared.show("Finish the current capture first", symbol: "rectangle.dashed")
            return
        }

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
            guard self.overlayController == nil else {
                appState.restoreCaptureWindows()
                return
            }

            displays = inputs.displays
            frozenImages = inputs.frozenImages
            finished = false
            selectedResult = nil
            currentIntent = normalizedCaptureIntent(
                CaptureIntent.from(storageKey: appState.settings.lastCaptureIntentKey) ?? .area
            )
            if reviewsSelection, currentIntent == .scrolling || currentIntent == .ocr {
                currentIntent = .area
            }
            updateFrozenScreen(for: currentIntent)

            let initialMode = reviewsSelection
                ? Self.reviewSelectionMode(for: currentIntent)
                : currentIntent.selectionMode ?? .area
            let controller = SelectionOverlayController(
                displays: inputs.displays,
                windows: inputs.windows,
                frozenImages: inputs.frozenImages,
                mode: initialMode,
                aspectLock: appState.settings.selectionAspectLock,
                freezesScreen: freezesScreen,
                showsIntentRail: false,
                showsContextRail: false,
                keepsSelectionOpen: reviewsSelection,
                allowsMarkup: Self.allowsMarkup(for: currentIntent),
                markupCompletion: { result, markup in
                    self.handleOverlayResult(result, markup: markup)
                }
            )
            controller.extraKeyHandler = { event in
                self.handleKeyDown(event)
            }
            controller.onSelectionBegan = { [weak self] in
                guard self?.reviewsSelection == false else { return }
                guard self?.pendingRecordingOptions == nil else { return }
                self?.toolbar.dismiss()
            }
            controller.onSelectionChanged = { [weak self] result in
                self?.handleSelectionChanged(result)
            }
            controller.onWillFinish = { [weak self] in
                self?.toolbar.dismiss()
            }
            overlayController = controller
            controller.present()

            DispatchQueue.main.async { [weak self] in
                guard let self, self.overlayController != nil else { return }
                let model = HUDToolbarModel(
                    selected: self.currentIntent,
                    options: self.recordingOptions,
                    reviewSelection: self.reviewsSelection
                )
                model.onSelect = { [weak self] intent in self?.selectIntent(intent) }
                model.onRecord = { [weak self] intent, options in
                    self?.startRecording(intent: intent, options: options)
                }
                model.onRequestMicrophonePermission = {
                    await SettingsPermissions.requestMicrophone()
                }
                model.onRequestCameraPermission = {
                    await SettingsPermissions.requestCamera()
                }
                model.onOptionsChanged = { [weak self] options in
                    self?.persistRecordingOptions(options)
                }
                model.onCancel = { [weak self] in self?.finish(cancelled: true) }
                self.toolbar.show(model: model)
                if self.reviewsSelection, self.currentIntent == .fullScreen {
                    self.overlayController?.selectScreen()
                }
                self.overlayController?.focusActivePanel()
            }
        }
    }

    private func selectIntent(_ intent: CaptureIntent) {
        if reviewsSelection {
            selectReviewIntent(intent)
            return
        }
        let wasSelected = currentIntent == intent
        currentIntent = intent
        updateFrozenScreen(for: intent)
        overlayController?.setAllowsMarkup(Self.allowsMarkup(for: intent))
        appState.settings.lastCaptureIntentKey = intent.storageKey
        toolbar.setSelected(intent)
        if intent.isInstant, wasSelected {
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

    private func selectReviewIntent(_ intent: CaptureIntent) {
        updateFrozenScreen(for: intent)
        overlayController?.setAllowsMarkup(Self.allowsMarkup(for: intent))
        if intent == .scrolling || intent == .ocr {
            if case .area? = selectedResult {
                currentIntent = intent
                toolbar.setSelected(intent)
                overlayController?.commitSelection()
            } else if selectedResult != nil {
                toolbar.model?.blockingMessage = "Scroll and Text require an area selection."
                overlayController?.setAllowsMarkup(Self.allowsMarkup(for: currentIntent))
            } else {
                currentIntent = intent
                toolbar.setSelected(intent)
                overlayController?.setMode(intent.selectionMode ?? .area)
                overlayController?.focusActivePanel()
            }
            return
        }

        currentIntent = intent
        selectedResult = nil
        appState.settings.lastCaptureIntentKey = intent.storageKey
        toolbar.setSelected(intent)
        toolbar.model?.updateSelection(isReady: false)
        if intent == .fullScreen {
            overlayController?.selectScreen()
        } else if intent.selectionMode != nil {
            overlayController?.setMode(Self.reviewSelectionMode(for: intent))
            overlayController?.focusActivePanel()
        }
    }

    static func reviewSelectionMode(for intent: CaptureIntent) -> SelectionMode {
        intent == .fullScreen ? .screen : intent.selectionMode ?? .area
    }

    static func allowsMarkup(for intent: CaptureIntent) -> Bool {
        intent == .area
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if reviewsSelection, event.keyCode == 36 || event.keyCode == 76 {
            captureSelection()
            return selectedResult != nil
        }
        if let intent = CaptureIntent.forDigit(event.keyCode) {
            if intent == .recordArea || intent == .recordScreen {
                let source: CaptureIntent = intent == .recordScreen ? .fullScreen : .area
                startRecording(intent: source, options: toolbar.model?.options ?? recordingOptions)
                return true
            }
            selectIntent(intent)
            return true
        }
        return false
    }

    private func handleSelectionChanged(_ result: SelectionResult) {
        selectedResult = result
        let isArea: Bool
        if case .area = result { isArea = true } else { isArea = false }
        toolbar.model?.updateSelection(isReady: true, supportsAreaActions: isArea)
        if currentIntent == .scrolling || currentIntent == .ocr {
            overlayController?.commitSelection()
        }
    }

    private func captureSelection() {
        guard reviewsSelection, selectedResult != nil else { return }
        if currentIntent == .scrolling || currentIntent == .ocr {
            currentIntent = .area
        }
        overlayController?.commitSelection()
    }

    private func handleOverlayResult(_ result: SelectionResult?, markup: SelectionMarkupPayload) {
        guard !finished else { return }
        guard let result else {
            finish(cancelled: true)
            return
        }
        if let options = pendingRecordingOptions {
            pendingRecordingOptions = nil
            finish(cancelled: false, keepToolbar: true)
            dispatchRecordingSelection(result, options: options)
            return
        }
        let intent = currentIntent
        finish(cancelled: false)
        dispatchSelection(result, intent: intent, markup: markup)
    }

    private func finish(cancelled: Bool, keepToolbar: Bool = false) {
        guard !finished else { return }
        finished = true
        if !keepToolbar { toolbar.dismiss() }
        overlayController?.dismiss()
        overlayController = nil
        pendingRecordingOptions = nil
        selectedResult = nil
        if cancelled {
            appState.restoreCaptureWindows()
            displays = []
            frozenImages = [:]
            freezesScreen = false
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

    private func dispatchSelection(_ result: SelectionResult, intent: CaptureIntent, markup: SelectionMarkupPayload) {
        Task {
            switch intent {
            case .area:
                await completeStillSelection(result, markup: markup)
            case .window:
                await completeStillSelection(result, markup: markup)
            case .fullScreen:
                await completeStillSelection(result, markup: markup)
            case .scrolling:
                guard case .area(let rect, let display) = result else {
                    appState.restoreCaptureWindows()
                    return
                }
                appState.scrollingCaptureController.begin(with: rect, on: display)
            case .recordArea:
                guard case .area(let rect, let display) = result else {
                    appState.restoreCaptureWindows()
                    return
                }
                await appState.recordingController.beginAreaRecording(with: rect, on: display)
            case .ocr:
                guard case .area(let rect, let display) = result else {
                    appState.restoreCaptureWindows()
                    return
                }
                await appState.ocrCaptureController.process(cocoaRect: rect, display: display)
                appState.restoreCaptureWindows()
            case .recordScreen:
                appState.restoreCaptureWindows()
            }
        }
    }

    private func startRecording(intent: CaptureIntent, options: HUDRecordingOptions) {
        freezesScreen = false
        overlayController?.setFreezesScreen(false)
        overlayController?.setAllowsMarkup(false)
        persistRecordingOptions(options)
        if reviewsSelection {
            guard selectedResult != nil else {
                toolbar.model?.blockingMessage = "Select an area, window, or screen first."
                return
            }
            pendingRecordingOptions = options
            overlayController?.commitSelection()
            return
        }
        switch intent {
        case .fullScreen:
            finish(cancelled: false, keepToolbar: true)
            appState.recordingController.beginScreenRecording(options: options, captureBar: toolbar)
        case .area, .window:
            pendingRecordingOptions = options
            toolbar.model?.blockingMessage = intent == .window
                ? "Click a window to record."
                : "Drag an area to record."
            overlayController?.setMode(intent == .window ? .window : .area)
            overlayController?.focusActivePanel()
        case .scrolling, .ocr, .recordArea, .recordScreen:
            toolbar.model?.blockingMessage = "Choose Area, Window, or Screen to record."
        }
    }

    private func dispatchRecordingSelection(_ result: SelectionResult, options: HUDRecordingOptions) {
        Task {
            switch result {
            case .area(let rect, let display):
                await appState.recordingController.beginAreaRecording(
                    with: rect,
                    on: display,
                    options: options,
                    captureBar: toolbar
                )
            case .window(let window):
                let rect = window.cocoaFrame
                guard let display = displays.first(where: { $0.cocoaFrame.intersects(rect) }) else {
                    toolbar.model?.blockingMessage = "The selected window is not on an available display."
                    appState.restoreCaptureWindows()
                    return
                }
                await appState.recordingController.beginAreaRecording(
                    with: rect,
                    on: display,
                    options: options,
                    captureBar: toolbar
                )
            case .screen(let display):
                appState.recordingController.beginScreenRecording(
                    on: display,
                    options: options,
                    captureBar: toolbar
                )
            }
        }
    }

    private var recordingOptions: HUDRecordingOptions {
        let defaults = UserDefaults.standard
        let countdown = defaults.object(forKey: "recordingCountdownSeconds") == nil
            ? 3
            : defaults.integer(forKey: "recordingCountdownSeconds")
        return HUDRecordingOptions(
            microphoneEnabled: appState.settings.recordMicrophone,
            systemAudioEnabled: appState.settings.recordSystemAudio,
            cameraEnabled: appState.settings.showWebcamOverlay,
            countdownSeconds: countdown
        )
    }

    private func persistRecordingOptions(_ options: HUDRecordingOptions) {
        appState.settings.recordMicrophone = options.microphoneEnabled
        appState.settings.recordSystemAudio = options.systemAudioEnabled
        appState.settings.showWebcamOverlay = options.cameraEnabled
        UserDefaults.standard.set(options.countdownSeconds, forKey: "recordingCountdownSeconds")
    }

    private func normalizedCaptureIntent(_ intent: CaptureIntent) -> CaptureIntent {
        switch intent {
        case .recordArea: .area
        case .recordScreen: .fullScreen
        default: intent
        }
    }

    private func updateFrozenScreen(for intent: CaptureIntent) {
        freezesScreen = appState.settings.freezeScreenDuringCapture
            && (intent == .area || intent == .window || intent == .fullScreen)
        overlayController?.setFreezesScreen(freezesScreen)
    }

    private func completeStillSelection(_ result: SelectionResult, markup: SelectionMarkupPayload) async {
        await appState.captureController.completeSelection(
            result,
            displays: displays,
            frozenImages: freezesScreen ? frozenImages : [:],
            markup: markup
        )
    }

    private var reviewsSelection: Bool {
        !appState.settings.allInOneCaptureImmediately
    }
}
