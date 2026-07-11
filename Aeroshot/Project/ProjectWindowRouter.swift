import AppKit

nonisolated enum ProjectOpenDestination: Equatable, Sendable {
    case screenshotEditor
    case gifStudio
    case videoStudio

    var displayName: String {
        switch self {
        case .screenshotEditor: "the screenshot editor"
        case .gifStudio: "GIF Studio"
        case .videoStudio: "Video Studio"
        }
    }
}

nonisolated enum ProjectWindowRouterError: LocalizedError, Equatable {
    case missingPrimarySource
    case unsupportedPrimaryMediaType(AeroMediaMetadata.MediaType)

    var errorDescription: String? {
        switch self {
        case .missingPrimarySource:
            "This project has no primary source asset, so Aeroshot cannot pick an editor for it."
        case .unsupportedPrimaryMediaType(let type):
            "Aeroshot cannot edit projects whose primary source is \(type.rawValue) media."
        }
    }
}

/// Opens a `.aeroshot` package in the editor that matches its primary source
/// media type. Every project-opening entry point (File menu, automation,
/// History) routes through here so image, GIF, and video packages all land in
/// a real editor instead of a wrong-media error.
@MainActor
enum ProjectWindowRouter {
    /// Studio window controllers do not retain themselves; hold them until
    /// their windows close.
    private static var retainedControllers: [NSWindowController] = []

    nonisolated static func destination(
        for mediaType: AeroMediaMetadata.MediaType
    ) throws -> ProjectOpenDestination {
        switch mediaType {
        case .image: .screenshotEditor
        case .gif: .gifStudio
        case .video: .videoStudio
        case .audio, .auxiliary:
            throw ProjectWindowRouterError.unsupportedPrimaryMediaType(mediaType)
        }
    }

    /// Opens the project and returns the destination it was routed to.
    /// Video Studio loads its AVAsset asynchronously; a failure after this
    /// call returns is presented to the user as an alert.
    @discardableResult
    static func openProject(at packageURL: URL, appState: AppState) throws -> ProjectOpenDestination {
        let destination = try destination(for: primaryMediaType(ofPackageAt: packageURL))
        switch destination {
        case .screenshotEditor:
            try EditorWindowController.openProject(at: packageURL, appState: appState)
        case .gifStudio:
            present(try GIFStudioWindowController.open(projectURL: packageURL))
        case .videoStudio:
            Task { @MainActor in
                do {
                    present(VideoStudioWindowController(document: try await .open(packageURL: packageURL)))
                } catch {
                    presentOpenFailure(error, packageURL: packageURL)
                }
            }
        }
        return destination
    }

    static func openGIF(at gifURL: URL) throws {
        present(try GIFStudioWindowController.open(gifURL: gifURL))
    }

    nonisolated static func primaryMediaType(ofPackageAt packageURL: URL) throws -> AeroMediaMetadata.MediaType {
        let manifest = try AeroProjectPackageStore(packageURL: packageURL).load()
        guard let id = manifest.primarySourceAssetID,
              let source = manifest.assets.first(where: { $0.id == id }) else {
            throw ProjectWindowRouterError.missingPrimarySource
        }
        return source.metadata.mediaType
    }

    private static func present(_ controller: NSWindowController) {
        retainedControllers.append(controller)
        if let window = controller.window {
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak controller] _ in
                MainActor.assumeIsolated {
                    retainedControllers.removeAll { $0 === controller }
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private static func presentOpenFailure(_ error: Error, packageURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t Open Project"
        alert.informativeText = "\(packageURL.lastPathComponent): \(error.localizedDescription)"
        alert.runModal()
    }
}
