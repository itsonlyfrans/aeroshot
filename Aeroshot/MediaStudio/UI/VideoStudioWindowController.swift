import AppKit
import SwiftUI

@MainActor
final class VideoStudioWindowController: NSWindowController, NSWindowDelegate {
    private var retainedDocument: VideoStudioDocument?

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
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1120, height: 760))
        window.minSize = NSSize(width: 980, height: 680)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    func windowWillClose(_ notification: Notification) { Task { await retainedDocument?.save() } }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}
