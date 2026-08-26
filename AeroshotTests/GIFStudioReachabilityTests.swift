import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Aeroshot

/// Slice 2: post-capture edit availability and GIF Studio open factories.
@Suite(.serialized)
struct GIFStudioReachabilityTests {
    @Test func editDestinationMatrixCoversEveryRecordingExtension() {
        #expect(RecordingPostCaptureModel.editDestination(forPathExtension: "mp4") == .videoStudio)
        #expect(RecordingPostCaptureModel.editDestination(forPathExtension: "MOV") == .videoStudio)
        #expect(RecordingPostCaptureModel.editDestination(forPathExtension: "m4v") == .videoStudio)
        #expect(RecordingPostCaptureModel.editDestination(forPathExtension: "gif") == .gifStudio)
        #expect(RecordingPostCaptureModel.editDestination(forPathExtension: "GIF") == .gifStudio)
        #expect(RecordingPostCaptureModel.editDestination(forPathExtension: "png") == nil)
        #expect(RecordingPostCaptureModel.editDestination(forPathExtension: "webm") == nil)
        #expect(RecordingPostCaptureModel.editDestination(forPathExtension: "") == nil)
    }

    @Test @MainActor func gifPostCaptureModelEnablesEditAndNamesGIFStudio() throws {
        try withTemporaryDirectory { root in
            let gif = root.appending(path: "capture.gif")
            try makeGIF(at: gif)
            let model = RecordingPostCaptureModel(outputURL: gif)
            #expect(model.canEdit)
            #expect(model.editDestination == .gifStudio)
            #expect(model.editDisabledReason.isEmpty)
        }
    }

    @Test @MainActor func unsupportedExtensionStatesBothStudiosHonestly() throws {
        try withTemporaryDirectory { root in
            let file = root.appending(path: "capture.webm")
            try Data("x".utf8).write(to: file)
            let model = RecordingPostCaptureModel(outputURL: file)
            #expect(!model.canEdit)
            #expect(model.editDisabledReason.contains("Video Studio"))
            #expect(model.editDisabledReason.contains("GIF Studio"))
        }
    }

    @Test func projectDestinationRoutesByPrimaryMediaType() throws {
        #expect(try ProjectWindowRouter.destination(for: .image) == .screenshotEditor)
        #expect(try ProjectWindowRouter.destination(for: .gif) == .gifStudio)
        #expect(try ProjectWindowRouter.destination(for: .video) == .videoStudio)
        #expect(throws: ProjectWindowRouterError.unsupportedPrimaryMediaType(.audio)) {
            try ProjectWindowRouter.destination(for: .audio)
        }
        #expect(throws: ProjectWindowRouterError.unsupportedPrimaryMediaType(.auxiliary)) {
            try ProjectWindowRouter.destination(for: .auxiliary)
        }
    }

    @Test func primaryMediaTypeReadsGIFManifests() throws {
        try withTemporaryDirectory { root in
            let gif = root.appending(path: "source.gif")
            try makeGIF(at: gif)
            let package = root.appending(path: "project.aeroshot")
            _ = try GIFProjectBridge.importSource(from: gif, to: package)
            #expect(try ProjectWindowRouter.primaryMediaType(ofPackageAt: package) == .gif)
        }
    }

    @Test @MainActor func openGIFURLCreatesPackageThenAdoptsItOnReopen() throws {
        try withTemporaryDirectory { root in
            let gif = root.appending(path: "capture.gif")
            try makeGIF(at: gif)

            let first = try GIFStudioWindowController.open(gifURL: gif)
            defer { first.close() }
            let packageURL = try #require(first.studioDocument.packageURL)
            #expect(packageURL == root.appending(path: "capture.aeroshot"))
            #expect(FileManager.default.fileExists(
                atPath: packageURL.appending(path: AeroProjectPackageStore.manifestFileName).path
            ))

            first.studioDocument.setSelectedDuration(milliseconds: 250)
            let expectedDurations = first.studioDocument.document.frames.map(\.durationMicroseconds)
            let expectedIDs = first.studioDocument.document.frames.map(\.id)
            first.studioDocument.saveNow()

            // A second open of the same recording must adopt the existing
            // package (continuing the project), not re-import the source.
            let second = try GIFStudioWindowController.open(gifURL: gif)
            defer { second.close() }
            #expect(second.studioDocument.document.frames.map(\.durationMicroseconds) == expectedDurations)
            #expect(second.studioDocument.document.frames.map(\.id) == expectedIDs)

            let viaProject = try GIFStudioWindowController.open(projectURL: packageURL)
            defer { viaProject.close() }
            #expect(viaProject.studioDocument.document.frames.map(\.durationMicroseconds) == expectedDurations)
            #expect(viaProject.window?.title.contains("capture") == true)
        }
    }

    @Test @MainActor func closingAStudioControllerReleasesItsOwnerCallbackOnce() throws {
        try withTemporaryDirectory { root in
            let gif = root.appending(path: "capture.gif")
            try makeGIF(at: gif)
            let controller = try GIFStudioWindowController.open(gifURL: gif)
            defer { controller.close() }

            var closeCount = 0
            controller.onClose = { closeCount += 1 }
            controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
            controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))

            #expect(closeCount == 1)
        }
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GIFStudioReachability-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func makeGIF(at url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 3, nil)
        else { throw FixtureError.failed }
        for (index, microseconds) in [33_333, 66_667, 100_000].enumerated() {
            guard let context = CGContext(
                data: nil, width: 3, height: 2, bitsPerComponent: 8, bytesPerRow: 12,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { throw FixtureError.failed }
            context.setFillColor(CGColor(red: CGFloat(index) / 3, green: 0.25, blue: 0.75, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 3, height: 2))
            guard let image = context.makeImage() else { throw FixtureError.failed }
            let delay = Double(microseconds) / 1_000_000
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFUnclampedDelayTime: delay,
                kCGImagePropertyGIFDelayTime: delay,
            ]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.failed }
    }

    private enum FixtureError: Error { case failed }
}
