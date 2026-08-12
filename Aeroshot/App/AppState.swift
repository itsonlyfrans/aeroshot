import Combine
import AppKit

@MainActor
struct CaptureWindowRestorationOwner: Equatable {
    fileprivate let id = UUID()
}

@MainActor
final class CaptureWindowRestoration {
    private let windows: [NSWindow]
    private let restoreWindow: (NSWindow) -> Void
    private var didRestore = false
    let owner = CaptureWindowRestorationOwner()

    init(
        windows: [NSWindow] = NSApp.windows,
        isVisible: (NSWindow) -> Bool = { $0.isVisible },
        restore: @escaping (NSWindow) -> Void = { $0.orderFront(nil) }
    ) {
        self.windows = windows.filter(isVisible)
        restoreWindow = restore
    }

    @discardableResult
    func restore(owner: CaptureWindowRestorationOwner) -> Bool {
        guard owner == self.owner else { return false }
        restore()
        return true
    }

    func restore() {
        guard !didRestore else { return }
        didRestore = true
        windows.forEach(restoreWindow)
    }
}

/// Shared app-wide services and state, owned by the AppDelegate.
@MainActor
final class AppState: ObservableObject {
    let settings = SettingsStore.shared
    let history = HistoryStore.shared
    let permissions = PermissionManager()
    lazy var captureController = CaptureController(appState: self)
    lazy var pinController = PinnedWindowController()
    lazy var thumbnailController = FloatingThumbnailController(appState: self)
    lazy var scrollingCaptureController = ScrollingCaptureController(appState: self)
    lazy var recordingController = RecordingController(appState: self)
    lazy var ocrCaptureController = OCRCaptureController(appState: self)
    lazy var allInOneController = AllInOneController(appState: self)

    @Published var isRecording = false

    private var historyWindowController: HistoryWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingController: OnboardingWindowController?
    private var captureWindowRestoration: CaptureWindowRestoration?
    private var recordingCaptureWindowOwner: CaptureWindowRestorationOwner?
    private let makeCaptureWindowRestoration: () -> CaptureWindowRestoration
    private let captureOverlaySettle: @Sendable () async -> Void

    init(
        captureWindowRestoration: CaptureWindowRestoration? = nil,
        captureWindowRestorationFactory: @escaping () -> CaptureWindowRestoration = { CaptureWindowRestoration() },
        captureOverlaySettle: @escaping @Sendable () async -> Void = {
            try? await Task.sleep(for: .milliseconds(100))
        }
    ) {
        self.captureWindowRestoration = captureWindowRestoration
        self.makeCaptureWindowRestoration = captureWindowRestorationFactory
        self.captureOverlaySettle = captureOverlaySettle
    }

    func showHistoryWindow() {
        if historyWindowController == nil {
            historyWindowController = HistoryWindowController(appState: self)
        }
        historyWindowController?.show()
    }

    func toggleHistoryWindow() {
        guard let window = historyWindowController?.window else {
            showHistoryWindow()
            return
        }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            showHistoryWindow()
        }
    }

    func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(appState: self)
        }
        settingsWindowController?.show()
    }

    func showPermissionWizardIfNeeded() {
        guard !settings.hasCompletedOnboarding else { return }
        presentOnboarding(startStep: .welcome)
    }

    /// Re-run setup from Settings, jumping straight to the first permission.
    func showPermissionWizard() {
        presentOnboarding(startStep: .screenRecording)
    }

    private func presentOnboarding(startStep: OnboardingStep) {
        if onboardingController == nil {
            onboardingController = OnboardingWindowController(
                appState: self,
                startStep: startStep,
                onComplete: { [weak self] in
                    self?.onboardingController?.close()
                    self?.onboardingController = nil
                },
                onTestCaptureFinished: { [weak self] in
                    self?.onboardingController?.show()
                }
            )
        }
        onboardingController?.show()
    }

    @discardableResult
    func openEditor(
        with image: CGImage,
        privacyScanPending: Bool = false
    ) -> EditorWindowController {
        EditorWindowController.open(
            image: image,
            appState: self,
            privacyScanPending: privacyScanPending
        )
    }

    /// Hide SwiftUI windows before ScreenCaptureKit snapshots so we do not capture
    /// or relayout our own chrome during the selection overlay.
    func prepareForCaptureOverlay() async -> CaptureWindowRestorationOwner? {
        guard !isRecording, captureWindowRestoration == nil else { return nil }
        let restoration = makeCaptureWindowRestoration()
        captureWindowRestoration = restoration
        let owner = restoration.owner
        // Keep this list-independent: Settings, tray, editor, media and any
        // future surface all belong to Aeroshot and must never be part of a
        // capture. Ordering out every visible app window also covers the
        // status popover and windows created by project routers.
        for window in NSApp.windows where window.isVisible {
            window.orderOut(nil)
        }
        settingsWindowController?.window?.orderOut(nil)
        historyWindowController?.window?.orderOut(nil)
        onboardingController?.window?.orderOut(nil)
        EditorWindowController.hideAllForCapture()
        thumbnailController.dismiss(animated: false)
        if settings.shareSafeSmartScan,
           settings.shareSafeAutoRedactAfterCapture || settings.shareSafeRedactBeforeSharing {
            ShareSafeSmartScanSupport.prewarm()
        }
        await captureOverlaySettle()
        guard !isRecording else {
            restoreCaptureWindows(owner: owner)
            return nil
        }
        return owner
    }

    func restoreCaptureWindows(owner: CaptureWindowRestorationOwner?) {
        guard let owner,
              captureWindowRestoration?.restore(owner: owner) == true
        else { return }
        if recordingCaptureWindowOwner == owner {
            recordingCaptureWindowOwner = nil
        }
        captureWindowRestoration = nil
    }

    func beginRecordingCaptureWindowOwnership(_ owner: CaptureWindowRestorationOwner?) {
        guard let owner, captureWindowRestoration?.owner == owner else { return }
        recordingCaptureWindowOwner = owner
    }

    func restoreCaptureWindows() {
        guard recordingCaptureWindowOwner == nil else { return }
        captureWindowRestoration?.restore()
        captureWindowRestoration = nil
    }

    func prepareCaptureOutput(_ image: CGImage) async throws -> ShareSafeResult {
        let settings = settings
        guard settings.shareSafeAutoRedactAfterCapture || settings.shareSafeRedactBeforeSharing else {
            return ShareSafeResult(image: image, matchCount: 0, redactionRects: [])
        }
        let result = try await ShareSafeService.process(
            image: image,
            style: settings.shareSafeRedactionStyle,
            useSmartScan: settings.shareSafeSmartScan,
            usePrivacyFilter: settings.shareSafePrivacyFilter
        )
        if result.matchCount > 0 {
            ToastController.shared.show(
                "Redacted \(result.matchCount) sensitive item\(result.matchCount == 1 ? "" : "s")",
                symbol: "checkmark.shield"
            )
        }
        return result
    }

    /// Route a finished capture through save/copy/thumbnail/history.
    func handleCapturedImage(_ image: CGImage) {
        Task { @MainActor in
            let settings = settings
            var output = image

            let shouldAutoRedact = settings.shareSafeAutoRedactAfterCapture
                || settings.shareSafeRedactBeforeSharing
            settings.playSelectedSound()
            let editorController = settings.openEditorAfterCapture
                ? openEditor(with: image, privacyScanPending: shouldAutoRedact)
                : nil
            if shouldAutoRedact, settings.showThumbnailAfterCapture {
                thumbnailController.show(
                    image: image,
                    fileURL: nil,
                    privacyScanPending: true,
                    unavailableActions: editorController == nil ? [] : [.edit]
                )
            }
            var redactionRects: [CGRect] = []
            if shouldAutoRedact {
                do {
                    let result = try await prepareCaptureOutput(image)
                    redactionRects = result.redactionRects
                    output = result.image
                } catch {
                    editorController?.finishPrivacyScan(
                        redactionRects: [],
                        style: settings.shareSafeRedactionStyle
                    )
                    thumbnailController.dismiss()
                    if editorController == nil {
                        openEditor(with: image)
                    }
                    ToastController.shared.show(
                        "Sensitive-data scan failed — capture opened for review. Nothing was saved or copied.",
                        symbol: "exclamationmark.triangle"
                    )
                    return
                }
            }
            editorController?.finishPrivacyScan(
                redactionRects: redactionRects,
                style: settings.shareSafeRedactionStyle
            )

            var savedURL: URL?
            if settings.saveToDiskAfterCapture {
                let url = settings.newFileURL()
                let screen = NSScreen.main
                do {
                    try ImageExporter.write(output, to: url,
                                            format: settings.imageFormat,
                                            jpegQuality: settings.jpegQuality,
                                            scale: screen?.backingScaleFactor ?? 2,
                                            downscaleToPoints: settings.downscaleRetina)
                    savedURL = url
                } catch {
                    ToastController.shared.show(
                        "Couldn’t save screenshot. Check the save folder and available space.",
                        symbol: "exclamationmark.triangle"
                    )
                }
            }
            var copied = false
            if settings.copyToClipboardAfterCapture {
                copied = PasteboardWriter.copy(image: output, fileURL: savedURL)
                if !copied {
                    ToastController.shared.show("Copy failed", symbol: "exclamationmark.triangle")
                }
            }
            if let item = history.add(image: output) {
                let itemID = item.id
                Task {
                    guard let text = try? await OCRService.recognizeText(in: output), !text.isEmpty else { return }
                    history.setOCRText(text, for: itemID)
                }
            } else {
                if savedURL == nil, !copied, editorController == nil {
                    openEditor(with: output)
                }
                ToastController.shared.show(
                    "Couldn’t add capture to History.",
                    symbol: "exclamationmark.triangle"
                )
            }
            if settings.showThumbnailAfterCapture {
                let uploadPending = savedURL != nil
                    && settings.uploadAfterCapture
                    && !settings.uploadWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                thumbnailController.show(
                    image: output,
                    fileURL: savedURL,
                    uploadPending: uploadPending,
                    unavailableActions: editorController == nil ? [] : [.edit]
                )
            }
            if let savedURL {
                Task { await uploadIfNeeded(fileURL: savedURL) }
            }
        }
    }

    func uploadIfNeeded(fileURL: URL) async {
        let settings = settings
        guard settings.uploadAfterCapture,
              !settings.uploadWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let link = try await UploadService.upload(fileURL: fileURL, webhookURL: settings.uploadWebhookURL)
            if settings.copyLinkAfterUpload {
                PasteboardWriter.copy(text: link.absoluteString)
            }
            thumbnailController.markUploadCompleted(for: fileURL)
        } catch {
            thumbnailController.markUploadFailed(for: fileURL)
            ToastController.shared.show(error.localizedDescription, symbol: "exclamationmark.triangle")
        }
    }
}
