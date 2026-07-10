import AppKit
import SwiftUI

@MainActor
final class GIFStudioWindowController: NSWindowController, NSWindowDelegate {
    let studioDocument: GIFStudioDocument

    init(document: GIFStudioDocument) {
        studioDocument = document
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_060, height: 740),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "GIF Studio"
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
