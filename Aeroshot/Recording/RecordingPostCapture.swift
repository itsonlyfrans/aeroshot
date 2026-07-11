import AppKit
import Combine
import SwiftUI

nonisolated enum RecordingEditDestination: Equatable, Sendable {
    case videoStudio
    case gifStudio

    var studioName: String {
        switch self {
        case .videoStudio: "Video Studio"
        case .gifStudio: "GIF Studio"
        }
    }
}

@MainActor
final class RecordingPostCaptureModel: ObservableObject {
    let outputURL: URL
    @Published private(set) var editDisabledReason = ""
    @Published private(set) var isOpeningEditor = false
    private var studioController: NSWindowController?

    init(outputURL: URL) {
        self.outputURL = outputURL
        refreshEditAvailability()
    }

    var canEdit: Bool { editDisabledReason.isEmpty && !isOpeningEditor }

    var editDestination: RecordingEditDestination? {
        Self.editDestination(forPathExtension: outputURL.pathExtension)
    }

    nonisolated static func editDestination(forPathExtension fileExtension: String) -> RecordingEditDestination? {
        switch fileExtension.lowercased() {
        case "mp4", "mov", "m4v": .videoStudio
        case "gif": .gifStudio
        default: nil
        }
    }

    func refreshEditAvailability() {
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            editDisabledReason = "Phase 4 Media Studio cannot open this recording because it is no longer available. Reveal its folder and locate the file."
            return
        }
        guard editDestination != nil else {
            editDisabledReason = "Aeroshot can edit MP4, MOV, and M4V recordings in Video Studio and GIF recordings in GIF Studio."
            return
        }
        editDisabledReason = ""
    }

    func edit() {
        guard canEdit, let destination = editDestination else { return }
        isOpeningEditor = true
        Task {
            defer { isOpeningEditor = false }
            do {
                let controller: NSWindowController
                switch destination {
                case .videoStudio:
                    controller = try await VideoStudioWindowController.open(recordingURL: outputURL)
                case .gifStudio:
                    controller = try GIFStudioWindowController.open(gifURL: outputURL)
                }
                studioController = controller
                controller.showWindow(nil)
                controller.window?.makeKeyAndOrderFront(nil)
            } catch {
                editDisabledReason = "Could not open \(destination.studioName): \(error.localizedDescription)"
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
                    .help(model.editDisabledReason.isEmpty
                        ? "Open this recording in \(model.editDestination?.studioName ?? "the studio")"
                        : model.editDisabledReason)
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
