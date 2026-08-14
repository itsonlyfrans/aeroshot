import AppKit
import SwiftUI

@MainActor
final class VideoStudioWindowController: NSWindowController, NSWindowDelegate {
    private var retainedDocument: VideoStudioDocument?
    private var isCloseApproved = false

    static func open(recordingURL: URL) async throws -> VideoStudioWindowController {
        let packageURL = recordingURL.deletingPathExtension().appendingPathExtension("aeroshot")
        let document: VideoStudioDocument
        if FileManager.default.fileExists(atPath: packageURL.appending(path: AeroProjectPackageStore.manifestFileName).path) {
            document = try await .open(packageURL: packageURL)
        } else {
            document = try await .create(from: recordingURL, packageURL: packageURL)
        }
        return VideoStudioWindowController(document: document)
    }

    init(document: VideoStudioDocument) {
        retainedDocument = document
        let window = NSWindow(contentViewController: NSHostingController(rootView: VideoStudioView(document: document)))
        window.title = "Video Studio — \(document.packageURL.deletingPathExtension().lastPathComponent)"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 1600, height: 1000))
        window.minSize = NSSize(width: 1120, height: 760)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isCloseApproved { return true }
        do {
            try retainedDocument?.saveForClose()
            return true
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn’t Save Video Project"
            alert.informativeText = "The latest changes could not be written. \(error.localizedDescription)"
            alert.addButton(withTitle: "Cancel")
            let closeButton = alert.addButton(withTitle: "Close Anyway")
            closeButton.hasDestructiveAction = true
            alert.beginSheetModal(for: sender) { [weak self] response in
                guard response == .alertSecondButtonReturn else { return }
                self?.isCloseApproved = true
                sender.close()
            }
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        retainedDocument?.cancelExport()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}
