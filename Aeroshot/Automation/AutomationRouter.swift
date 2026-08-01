import AppKit
import Foundation

nonisolated enum AutomationResult: Equatable, Sendable {
    case accepted(String)
    case rejected(String)

    var message: String {
        switch self { case .accepted(let value), .rejected(let value): value }
    }
    var succeeded: Bool { if case .accepted = self { true } else { false } }
}

@MainActor
protocol AutomationActionHosting: AnyObject {
    func capture(_ mode: AutomationCaptureMode) -> AutomationResult
    func openProject(at url: URL) -> AutomationResult
    func export(_ preset: AutomationExportPreset, project: URL, destination: URL) -> AutomationResult
    func reveal(_ url: URL) -> AutomationResult
    func reviewPrivacy() -> AutomationResult
    func openAtlas(surface: AtlasWorkbenchSurface) -> AutomationResult
}

@MainActor
final class AutomationRouter {
    private weak var host: AutomationActionHosting?
    init(host: AutomationActionHosting) { self.host = host }

    func route(_ action: AutomationAction) -> AutomationResult {
        guard let host else { return .rejected("Aeroshot is not ready.") }
        switch action {
        case .capture(let mode): return host.capture(mode)
        case .openProject(let url): return host.openProject(at: url)
        case .exportPreset(let preset, let project, let destination): return host.export(preset, project: project, destination: destination)
        case .reveal(let url): return host.reveal(url)
        case .privacyReview: return host.reviewPrivacy()
        case .atlas(let surface): return host.openAtlas(surface: surface)
        }
    }
}

@MainActor
extension AppDelegate: AutomationActionHosting {
    func capture(_ mode: AutomationCaptureMode) -> AutomationResult {
        switch mode {
        case .area: appState.captureController.beginAreaCapture()
        case .window: appState.captureController.beginWindowCapture()
        case .screen: appState.captureController.captureFullScreen()
        case .lastRegion: appState.captureController.captureLastRegion()
        case .scrolling: appState.scrollingCaptureController.begin()
        case .text: appState.ocrCaptureController.begin()
        case .recordArea: appState.recordingController.beginAreaRecording()
        case .recordScreen: appState.recordingController.beginScreenRecording()
        }
        return .accepted("Started \(mode.rawValue).")
    }

    func openProject(at url: URL) -> AutomationResult {
        guard url.pathExtension.lowercased() == "aeroshot", FileManager.default.fileExists(atPath: url.path) else {
            return .rejected("Project must be an existing .aeroshot package.")
        }
        do {
            let destination = try ProjectWindowRouter.openProject(at: url, appState: appState)
            return .accepted("Opened \(url.lastPathComponent) in \(destination.displayName).")
        } catch { return .rejected("Project could not be opened: \(error.localizedDescription)") }
    }

    func export(_ preset: AutomationExportPreset, project: URL, destination: URL) -> AutomationResult {
        guard project.pathExtension.lowercased() == "aeroshot", FileManager.default.fileExists(atPath: project.path) else {
            return .rejected("Export requires an existing .aeroshot project.")
        }
        guard destination.deletingLastPathComponent().isFileURL else { return .rejected("Export destination must be local.") }
        return .rejected("The \(preset.rawValue) preset requires an open Studio export session; unattended export is not supported yet.")
    }

    func reveal(_ url: URL) -> AutomationResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .rejected("The item does not exist.") }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return .accepted("Revealed \(url.lastPathComponent).")
    }

    func reviewPrivacy() -> AutomationResult {
        appState.showSettingsWindow()
        return .accepted("Opened privacy settings for review.")
    }

    func openAtlas(surface: AtlasWorkbenchSurface) -> AutomationResult {
        appState.showAtlasWorkbench(surface: surface)
        return .accepted("Opened the Atlas \(surface.title) surface.")
    }
}
