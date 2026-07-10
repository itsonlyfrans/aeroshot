import AppKit
import Combine
import SwiftUI

@MainActor
final class RecordingPostCaptureModel: ObservableObject {
    let outputURL: URL
    @Published private(set) var editDisabledReason = ""
    @Published private(set) var isOpeningEditor = false
    private var studioController: VideoStudioWindowController?

    init(outputURL: URL) {
        self.outputURL = outputURL
        refreshEditAvailability()
    }

    var canEdit: Bool { editDisabledReason.isEmpty && !isOpeningEditor }

    func refreshEditAvailability() {
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            editDisabledReason = "Phase 4 Media Studio cannot open this recording because it is no longer available. Reveal its folder and locate the file."
            return
        }
        guard ["mp4", "mov", "m4v"].contains(outputURL.pathExtension.lowercased()) else {
            editDisabledReason = "Video Studio can currently open MP4, MOV, and M4V recordings."
            return
        }
        editDisabledReason = ""
    }

    func edit() {
        guard canEdit else { return }
        isOpeningEditor = true
        Task {
            defer { isOpeningEditor = false }
            do {
                let controller = try await VideoStudioWindowController.open(recordingURL: outputURL)
                studioController = controller
                controller.showWindow(nil)
                controller.window?.makeKeyAndOrderFront(nil)
            } catch {
                editDisabledReason = "Could not open Video Studio: \(error.localizedDescription)"
            }
        }
    }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([outputURL as NSURL])
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = outputURL.lastPathComponent
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        try? FileManager.default.copyItem(at: outputURL, to: destination)
    }

    func reveal() { NSWorkspace.shared.activateFileViewerSelecting([outputURL]) }
}

struct RecordingPostCaptureView: View {
    @ObservedObject var model: RecordingPostCaptureModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recording saved", systemImage: "checkmark.circle.fill").font(.headline)
            Text(model.outputURL.lastPathComponent).lineLimit(1).foregroundStyle(.secondary)
            HStack {
                Button(model.isOpeningEditor ? "Opening…" : "Edit") { model.edit() }
                    .disabled(!model.canEdit)
                    .help(model.editDisabledReason.isEmpty ? "Open this recording in Video Studio" : model.editDisabledReason)
                    .accessibilityIdentifier("recordingPostCapture.edit")
                Button("Copy") { model.copy() }
                    .onDrag { NSItemProvider(contentsOf: model.outputURL) ?? NSItemProvider() }
                Button("Save As…") { model.saveAs() }
                Spacer()
                Button("Reveal") { model.reveal() }.buttonStyle(.borderedProminent)
            }
            if !model.editDisabledReason.isEmpty {
                HStack {
                    Text(model.editDisabledReason)
                    Button("Retry") { model.refreshEditAvailability() }
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16).frame(width: 520)
    }
}

@MainActor
final class RecordingPostCaptureWindowController: NSWindowController {
    init(outputURL: URL) {
        let view = RecordingPostCaptureView(model: RecordingPostCaptureModel(outputURL: outputURL))
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Recording Complete"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}
