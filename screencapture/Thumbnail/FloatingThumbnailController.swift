import AppKit
import SwiftUI

/// Shows the Quick Access Overlay: a floating thumbnail in the bottom-left
/// corner after each capture, with copy/save/edit/pin/OCR actions and
/// drag-out support.
@MainActor
final class FloatingThumbnailController {
    private unowned let appState: AppState
    private var panel: NSPanel?
    private var dismissTimer: Timer?

    init(appState: AppState) {
        self.appState = appState
    }

    func show(image: CGImage, fileURL: URL?) {
        dismiss()

        let model = ThumbnailModel(image: image, fileURL: fileURL)
        model.onCopy = { [weak self] in
            PasteboardWriter.copy(image: image)
            self?.dismiss()
        }
        model.onSave = { [weak self] in
            guard let self else { return }
            let url = self.appState.settings.newFileURL()
            try? ImageExporter.write(image, to: url, format: self.appState.settings.imageFormat)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            self.dismiss()
        }
        model.onEdit = { [weak self] in
            self?.appState.openEditor(with: image)
            self?.dismiss()
        }
        model.onPin = { [weak self] in
            self?.appState.pinController.pin(image: image)
            self?.dismiss()
        }
        model.onOCR = { [weak self] in
            Task {
                if let text = try? await OCRService.recognizeText(in: image) {
                    PasteboardWriter.copy(text: text)
                }
                self?.dismiss()
            }
        }
        model.onClose = { [weak self] in self?.dismiss() }
        model.onHoverChanged = { [weak self] hovering in
            if hovering {
                self?.dismissTimer?.invalidate()
            } else {
                self?.scheduleDismiss()
            }
        }

        let view = FloatingThumbnailView(model: model)
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)

        let panel = NSPanel(contentRect: hosting.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting

        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: vf.minX + 20, y: vf.minY + 20))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        scheduleDismiss()
    }

    private func scheduleDismiss() {
        dismissTimer?.invalidate()
        let duration = appState.settings.thumbnailDuration
        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
