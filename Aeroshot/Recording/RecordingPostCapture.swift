import AppKit
import Combine

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
