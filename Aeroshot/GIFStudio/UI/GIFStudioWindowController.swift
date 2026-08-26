import AppKit
import SwiftUI

@MainActor
final class GIFStudioWindowController: NSWindowController, NSWindowDelegate {
    let studioDocument: GIFStudioDocument
    private var isCloseApproved = false
    var onClose: (() -> Void)?

    /// Opens a captured GIF, adopting its sibling `.aeroshot` package when one
    /// already exists so edits keep accumulating in the same project.
    static func open(gifURL: URL) throws -> GIFStudioWindowController {
        let packageURL = gifURL.deletingPathExtension().appendingPathExtension("aeroshot")
        let document: GIFStudioDocument
        if FileManager.default.fileExists(atPath: packageURL.appending(path: AeroProjectPackageStore.manifestFileName).path) {
            document = try .open(packageURL: packageURL)
        } else {
            document = try .create(from: gifURL, packageURL: packageURL)
        }
        return GIFStudioWindowController(document: document)
    }

    static func open(projectURL: URL) throws -> GIFStudioWindowController {
        GIFStudioWindowController(document: try .open(packageURL: projectURL))
    }

    init(document: GIFStudioDocument) {
        studioDocument = document
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_600, height: 1_000),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = document.packageURL.map {
            "GIF Studio — \($0.deletingPathExtension().lastPathComponent)"
        } ?? "GIF Studio"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 1_100, height: 720)
        window.contentView = NSHostingView(rootView: GIFStudioView(model: document))
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isCloseApproved { return true }
        do {
            try studioDocument.saveForClose()
            return true
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn’t Save GIF Project"
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
        studioDocument.cancelExport()
        onClose?()
        onClose = nil
    }
}
