import Combine
import AppKit
import os

nonisolated struct CaptureImageArtifacts: Sendable {
    let historyPNG: Data?
    let savedData: Data?
    let pixelWidth: Int
    let pixelHeight: Int
}

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

    func showSettingsWindow(category: SettingsAtlasCategoryID? = nil) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(appState: self)
        }
        settingsWindowController?.show()
        if let category {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .settingsAtlasOpenCategory, object: category)
            }
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
        sourceScale: CGFloat = 1,
        privacyScanPending: Bool = false
    ) -> EditorWindowController {
        let state = PerformanceInstrumentation.signposter.beginInterval("EditorVisible")
        let controller = EditorWindowController.open(
            image: image,
            sourceScale: sourceScale,
            appState: self,
            privacyScanPending: privacyScanPending
        )
        controller.window?.contentView?.displayIfNeeded()
        PerformanceInstrumentation.signposter.endInterval("EditorVisible", state)
        return controller
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

    nonisolated static func captureOutputNeedsRedaction(
        autoRedact: Bool,
        redactBeforeSharing: Bool,
        isSharing: Bool
    ) -> Bool {
        autoRedact || (redactBeforeSharing && isSharing)
    }

    nonisolated static func encodeCaptureArtifacts(
        image: CGImage,
        sourceScale: CGFloat,
        savedFormat: ImageFormat?,
        jpegQuality: Double,
        downscaleToPoints: Bool
    ) -> CaptureImageArtifacts {
        let historyPNG: Data?
        do {
            historyPNG = try ImageExporter.encodedData(for: image, format: .png, scale: sourceScale)
        } catch {
            historyPNG = nil
        }

        guard let savedFormat else {
            return CaptureImageArtifacts(
                historyPNG: historyPNG,
                savedData: nil,
                pixelWidth: image.width,
                pixelHeight: image.height
            )
        }
        if savedFormat == .png, !downscaleToPoints {
            return CaptureImageArtifacts(
                historyPNG: historyPNG,
                savedData: historyPNG,
                pixelWidth: image.width,
                pixelHeight: image.height
            )
        }
        do {
            return CaptureImageArtifacts(
                historyPNG: historyPNG,
                savedData: try ImageExporter.encodedData(
                    for: image,
                    format: savedFormat,
                    jpegQuality: jpegQuality,
                    scale: sourceScale,
                    downscaleToPoints: downscaleToPoints
                ),
                pixelWidth: image.width,
                pixelHeight: image.height
            )
        } catch {
            return CaptureImageArtifacts(
                historyPNG: historyPNG,
                savedData: nil,
                pixelWidth: image.width,
                pixelHeight: image.height
            )
        }
    }

    func prepareCaptureOutput(_ image: CGImage, forSharing: Bool = true) async throws -> ShareSafeResult {
        let settings = settings
        guard Self.captureOutputNeedsRedaction(
            autoRedact: settings.shareSafeAutoRedactAfterCapture,
            redactBeforeSharing: settings.shareSafeRedactBeforeSharing,
            isSharing: forSharing
        ) else {
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
    func handleCapturedImage(
        _ image: CGImage,
        sourceScale: CGFloat,
        captureKind: ThumbnailCaptureKind = .area
    ) {
        Task { @MainActor in
            let settings = settings
            var output = image

            let shouldAutoRedact = Self.captureOutputNeedsRedaction(
                autoRedact: settings.shareSafeAutoRedactAfterCapture,
                redactBeforeSharing: settings.shareSafeRedactBeforeSharing,
                isSharing: false
            )
            settings.playSelectedSound()
            let editorController = settings.openEditorAfterCapture
                ? openEditor(with: image, sourceScale: sourceScale, privacyScanPending: shouldAutoRedact)
                : nil
            if shouldAutoRedact, settings.showThumbnailAfterCapture {
                thumbnailController.show(
                    image: image,
                    fileURL: nil,
                    captureKind: captureKind,
                    sourceScale: sourceScale,
                    privacyScanPending: true,
                    unavailableActions: editorController == nil ? [] : [.edit]
                )
            }
            var redactionRects: [CGRect] = []
            if shouldAutoRedact {
                do {
                    let result = try await prepareCaptureOutput(image, forSharing: false)
                    redactionRects = result.redactionRects
                    output = result.image
                } catch {
                    editorController?.finishPrivacyScan(
                        redactionRects: [],
                        style: settings.shareSafeRedactionStyle
                    )
                    thumbnailController.dismiss()
                    if editorController == nil {
                        openEditor(with: image, sourceScale: sourceScale)
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

            let requestedSavedURL = settings.saveToDiskAfterCapture ? settings.newFileURL() : nil
            let imageFormat = settings.imageFormat
            let jpegQuality = settings.jpegQuality
            let downscaleToPoints = settings.downscaleRetina
            let artifacts = await Task.detached(priority: .userInitiated) {
                Self.encodeCaptureArtifacts(
                    image: output,
                    sourceScale: sourceScale,
                    savedFormat: requestedSavedURL == nil ? nil : imageFormat,
                    jpegQuality: jpegQuality,
                    downscaleToPoints: downscaleToPoints
                )
            }.value

            var savedURL: URL?
            if let url = requestedSavedURL, let data = artifacts.savedData {
                do {
                    try await Task.detached(priority: .utility) {
                        try data.write(to: url, options: .atomic)
                    }.value
                    savedURL = url
                } catch {
                    ToastController.shared.show(
                        "Couldn’t save screenshot. Check the save folder and available space.",
                        symbol: "exclamationmark.triangle"
                    )
                }
            } else if requestedSavedURL != nil {
                ToastController.shared.show(
                    "Couldn’t save screenshot. Check the save folder and available space.",
                    symbol: "exclamationmark.triangle"
                )
            }
            var copied = false
            var protectedOutput: CGImage?
            if settings.copyToClipboardAfterCapture {
                var copyOutput: CGImage? = output
                var copyPNGData = artifacts.historyPNG
                if !shouldAutoRedact, settings.shareSafeRedactBeforeSharing {
                    do {
                        protectedOutput = try await prepareCaptureOutput(image).image
                        copyOutput = protectedOutput
                    } catch {
                        copyOutput = nil
                        ToastController.shared.show(
                            "Sensitive-data scan failed. The capture was not copied.",
                            symbol: "exclamationmark.triangle"
                        )
                    }
                    if let protectedOutput {
                        do {
                            copyPNGData = try await Task.detached(priority: .userInitiated) {
                                try ImageExporter.encodedData(
                                    for: protectedOutput,
                                    format: .png,
                                    scale: sourceScale
                                )
                            }.value
                        } catch {
                            copyOutput = nil
                            ToastController.shared.show(
                                "Could not prepare the protected capture. The capture was not copied.",
                                symbol: "exclamationmark.triangle"
                            )
                        }
                    }
                }
                if let copyOutput {
                    let copyFileURL = protectedOutput == nil ? savedURL : nil
                    copied = PasteboardWriter.copy(
                        image: copyOutput,
                        pngData: copyPNGData,
                        fileURL: copyFileURL,
                        sourceScale: sourceScale
                    )
                    if !copied {
                        ToastController.shared.show("Copy failed", symbol: "exclamationmark.triangle")
                    }
                }
            }
            let historyItem: HistoryItem?
            if let historyPNG = artifacts.historyPNG {
                historyItem = await history.add(
                    encodedImage: historyPNG,
                    pixelWidth: artifacts.pixelWidth,
                    pixelHeight: artifacts.pixelHeight,
                    sourceScale: sourceScale
                )
            } else {
                historyItem = nil
            }
            if let item = historyItem {
                let itemID = item.id
                Task {
                    guard let text = try? await OCRService.recognizeText(in: output), !text.isEmpty else { return }
                    history.setOCRText(text, for: itemID)
                }
            } else {
                if savedURL == nil, !copied, editorController == nil {
                    openEditor(with: output, sourceScale: sourceScale)
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
                    captureKind: captureKind,
                    sourceScale: sourceScale,
                    uploadPending: uploadPending,
                    unavailableActions: editorController == nil ? [] : [.edit]
                )
            }
            if let savedURL {
                let protectsUpload = !shouldAutoRedact && settings.shareSafeRedactBeforeSharing
                let uploadImage = protectsUpload ? (protectedOutput ?? image) : nil
                Task {
                    await uploadIfNeeded(
                        fileURL: savedURL,
                        captureImage: uploadImage,
                        sourceScale: sourceScale,
                        imageIsProtected: protectedOutput != nil,
                        requiresProtection: protectsUpload
                    )
                }
            }
        }
    }

    func uploadIfNeeded(
        fileURL: URL,
        captureImage: CGImage? = nil,
        sourceScale: CGFloat = 1,
        imageIsProtected: Bool = false,
        requiresProtection: Bool = false
    ) async {
        let settings = settings
        guard settings.uploadAfterCapture,
              !settings.uploadWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var temporaryDirectory: URL?
        defer {
            if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
        }
        do {
            var uploadURL = fileURL
            if let captureImage {
                let protectedImage: CGImage
                if imageIsProtected {
                    protectedImage = captureImage
                } else if requiresProtection {
                    protectedImage = try await ShareSafeService.process(
                        image: captureImage,
                        style: settings.shareSafeRedactionStyle,
                        useSmartScan: settings.shareSafeSmartScan,
                        usePrivacyFilter: settings.shareSafePrivacyFilter
                    ).image
                } else {
                    protectedImage = captureImage
                }
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Aeroshot-Upload-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                temporaryDirectory = directory
                uploadURL = directory.appendingPathComponent(fileURL.lastPathComponent)
                let format = ImageFormat.allCases.first { $0.fileExtension == fileURL.pathExtension.lowercased() }
                    ?? settings.imageFormat
                try ImageExporter.write(
                    protectedImage,
                    to: uploadURL,
                    format: format,
                    jpegQuality: settings.jpegQuality,
                    scale: sourceScale,
                    downscaleToPoints: settings.downscaleRetina
                )
            }
            let link = try await UploadService.upload(fileURL: uploadURL, webhookURL: settings.uploadWebhookURL)
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
