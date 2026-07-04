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

    private var historyWindowController: HistoryWindowController?
    private var settingsWindowController: SettingsWindowController?

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

    func openEditor(with image: CGImage) {
        EditorWindowController.open(image: image, appState: self)
    }

    /// Route a finished capture through save/copy/thumbnail/history.
    func handleCapturedImage(_ image: CGImage) {
        let settings = settings
        var savedURL: URL?
        if settings.saveToDiskAfterCapture {
            let url = settings.newFileURL()
            let screen = NSScreen.main
            try? ImageExporter.write(image, to: url,
                                     format: settings.imageFormat,
                                     jpegQuality: settings.jpegQuality,
                                     scale: screen?.backingScaleFactor ?? 2,
                                     downscaleToPoints: settings.downscaleRetina)
            savedURL = url
        }
        if settings.copyToClipboardAfterCapture {
            PasteboardWriter.copy(image: image)
            ToastController.shared.show("Copied to clipboard", symbol: "doc.on.clipboard")
        }
        if settings.saveToDiskAfterCapture, let savedURL {
            ToastController.shared.show("Saved", symbol: "square.and.arrow.down")
        }
        if settings.playCaptureSound {
            NSSound(named: "Pop")?.play()
        }
        let item = history.add(image: image)
        // Index OCR text in the background for history search.
        Task.detached { [weak self] in
            guard let text = try? await OCRService.recognizeText(in: image), !text.isEmpty else { return }
            await MainActor.run { self?.history.setOCRText(text, for: item.id) }
        }
        if settings.showThumbnailAfterCapture {
            thumbnailController.show(image: image, fileURL: savedURL)
        }
    }
}
