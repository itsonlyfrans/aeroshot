import AppKit
import SwiftUI

@MainActor
final class GIFStudioWindowController: NSWindowController, NSWindowDelegate {
    let studioDocument: GIFStudioDocument

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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_060, height: 740),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = document.packageURL.map {
            "GIF Studio — \($0.deletingPathExtension().lastPathComponent)"
        } ?? "GIF Studio"
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: GIFStudioView(model: document))
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func windowWillClose(_ notification: Notification) {
        studioDocument.saveNow()
        studioDocument.cancelExport()
    }
}
