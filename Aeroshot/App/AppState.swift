import Combine
import AppKit

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
    private var atlasWorkbenchController: AtlasWorkbenchWindowController?

    func showHistoryWindow() {
        if historyWindowController == nil {
            historyWindowController = HistoryWindowController(appState: self)
        }
        historyWindowController?.show()
    }

    func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(appState: self)
        }
        settingsWindowController?.show()
    }

    func showAtlasWorkbench(surface: AtlasWorkbenchSurface = .app) {
        if let atlasWorkbenchController {
            atlasWorkbenchController.show(surface: surface)
            return
        }
        let controller = AtlasWorkbenchWindowController(appState: self, initialSurface: surface)
        atlasWorkbenchController = controller
        controller.show(surface: surface)
    }

    func dismissAtlasWorkbench(_ controller: AtlasWorkbenchWindowController) {
        if atlasWorkbenchController === controller {
            atlasWorkbenchController = nil
        }
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
            onboardingController = OnboardingWindowController(appState: self, startStep: startStep) { [weak self] in
                self?.onboardingController?.close()
                self?.onboardingController = nil
            }
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
    func prepareForCaptureOverlay() async {
        settingsWindowController?.window?.orderOut(nil)
        historyWindowController?.window?.orderOut(nil)
        onboardingController?.window?.orderOut(nil)
        EditorWindowController.hideAllForCapture()
        thumbnailController.dismiss(animated: false)
        if settings.shareSafeSmartScan,
           settings.shareSafeAutoRedactAfterCapture || settings.shareSafeRedactBeforeSharing {
            ShareSafeSmartScanSupport.prewarm()
        }
        try? await Task.sleep(for: .milliseconds(100))
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
                    let result = try await ShareSafeService.process(
                        image: image,
                        style: settings.shareSafeRedactionStyle,
                        useSmartScan: settings.shareSafeSmartScan,
                        usePrivacyFilter: settings.shareSafePrivacyFilter
                    )
                    redactionRects = result.redactionRects
                    if result.matchCount > 0 {
                        output = result.image
                        ToastController.shared.show(
                            "Redacted \(result.matchCount) sensitive item\(result.matchCount == 1 ? "" : "s")",
                            symbol: "checkmark.shield"
                        )
                    }
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
            if settings.copyToClipboardAfterCapture {
                if !PasteboardWriter.copy(image: output, fileURL: savedURL) {
                    ToastController.shared.show("Copy failed", symbol: "exclamationmark.triangle")
                }
            }
            let item = history.add(image: output)
            let itemID = item.id
            Task {
                guard let text = try? await OCRService.recognizeText(in: output), !text.isEmpty else { return }
                history.setOCRText(text, for: itemID)
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
