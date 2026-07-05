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
        model.onShare = { [weak self] in
            guard let self, let view = self.panel?.contentView else { return }
            ShareService.shareImage(image, fileURL: fileURL, from: view)
        }
        model.onShareSafe = { [weak self] in
            guard let self, let view = self.panel?.contentView else { return }
            Task {
                await ShareSafeService.shareSafe(
                    image: image,
                    fileURL: fileURL,
                    from: view,
                    style: self.appState.settings.shareSafeRedactionStyle
                )
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

        let view = FloatingThumbnailView(
            model: model,
            showActionsAlways: appState.settings.showThumbnailActionsAlways
        )
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.layoutSubtreeIfNeeded()
        var contentSize = hosting.intrinsicContentSize
        if contentSize.width < 40 || contentSize.height < 40 {
            contentSize = CGSize(width: 296, height: 248)
        }
        hosting.frame = CGRect(origin: .zero, size: contentSize)

        let panel = NSPanel(contentRect: hosting.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let screen {
            let vf = screen.visibleFrame
            var origin = NSPoint(x: vf.minX + 20, y: vf.minY + 20)
            // Keep the full panel inside the visible frame when action buttons are shown.
            origin.x = min(origin.x, vf.maxX - contentSize.width - 8)
            origin.y = min(origin.y, vf.maxY - contentSize.height - 8)
            panel.setFrameOrigin(origin)
        }
        panel.orderFrontRegardless()
        self.panel = panel
        scheduleDismiss()
    }

    private func scheduleDismiss() {
        dismissTimer?.invalidate()
        let duration = appState.settings.thumbnailDuration
        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismiss()
            }
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
