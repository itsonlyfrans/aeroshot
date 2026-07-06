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
    private var permissionWizardController: PermissionWizardWindowController?

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

    func showPermissionWizardIfNeeded() {
        guard !settings.hasCompletedOnboarding else { return }
        if SettingsPermissions.screenRecordingGranted && SettingsPermissions.accessibilityGranted {
            settings.hasCompletedOnboarding = true
            return
        }
        presentPermissionWizard()
    }

    func showPermissionWizard() {
        presentPermissionWizard()
    }

    private func presentPermissionWizard() {
        if permissionWizardController == nil {
            permissionWizardController = PermissionWizardWindowController(appState: self) { [weak self] in
                self?.permissionWizardController?.close()
                self?.permissionWizardController = nil
            }
        }
        permissionWizardController?.show()
    }

    func openEditor(with image: CGImage) {
        EditorWindowController.open(image: image, appState: self)
    }

    /// Hide SwiftUI windows before ScreenCaptureKit snapshots so we do not capture
    /// or relayout our own chrome during the selection overlay.
    func prepareForCaptureOverlay() async {
        settingsWindowController?.window?.orderOut(nil)
        historyWindowController?.window?.orderOut(nil)
        permissionWizardController?.window?.orderOut(nil)
        EditorWindowController.hideAllForCapture()
        thumbnailController.dismiss()
        try? await Task.sleep(for: .milliseconds(100))
    }

    /// Route a finished capture through save/copy/thumbnail/history.
    func handleCapturedImage(_ image: CGImage) {
        Task { @MainActor in
            let settings = settings
            var output = image

            let shouldAutoRedact = settings.shareSafeAutoRedactAfterCapture
                || settings.shareSafeRedactBeforeSharing
            if shouldAutoRedact {
                if let result = try? await ShareSafeService.process(
                    image: image,
                    style: settings.shareSafeRedactionStyle,
                    useSmartScan: settings.shareSafeSmartScan,
                    usePrivacyFilter: settings.shareSafePrivacyFilter
                ), result.matchCount > 0 {
                    output = result.image
                    ToastController.shared.show(
                        "Redacted \(result.matchCount) sensitive item\(result.matchCount == 1 ? "" : "s")",
                        symbol: "checkmark.shield"
                    )
                }
            }

            var savedURL: URL?
            if settings.saveToDiskAfterCapture {
                let url = settings.newFileURL()
                let screen = NSScreen.main
                try? ImageExporter.write(output, to: url,
                                         format: settings.imageFormat,
                                         jpegQuality: settings.jpegQuality,
                                         scale: screen?.backingScaleFactor ?? 2,
                                         downscaleToPoints: settings.downscaleRetina)
                savedURL = url
            }
            if settings.copyToClipboardAfterCapture {
                if PasteboardWriter.copy(image: output, fileURL: savedURL) {
                    ToastController.shared.show("Copied to clipboard", symbol: "doc.on.clipboard")
                } else {
                    ToastController.shared.show("Copy failed", symbol: "exclamationmark.triangle")
                }
            }
            if settings.saveToDiskAfterCapture, savedURL != nil {
                ToastController.shared.show("Saved", symbol: "square.and.arrow.down")
            }
            settings.playSelectedSound()
            let item = history.add(image: output)
            let itemID = item.id
            Task {
                guard let text = try? await OCRService.recognizeText(in: output), !text.isEmpty else { return }
                history.setOCRText(text, for: itemID)
            }
            if settings.showThumbnailAfterCapture {
                thumbnailController.show(image: output, fileURL: savedURL)
            }
            if settings.openEditorAfterCapture {
                openEditor(with: output)
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
            ToastController.shared.show(
                settings.copyLinkAfterUpload ? "Upload link copied" : "Upload complete",
                symbol: "link"
            )
        } catch {
            ToastController.shared.show(error.localizedDescription, symbol: "exclamationmark.triangle")
        }
    }
}
