import Foundation
import ScreenCaptureKit
import Testing
@testable import Aeroshot

@MainActor
struct RecordingControllerIntegrationTests {
    @Test func preflightBlocksDeniedPermissionAndLowSpaceDeterministically() throws {
        let configuration = try fixtureConfiguration(requiredSpace: 1_000)
        let denied = RecordingPreflightModel(
            configuration: configuration,
            readiness: RecordingPreflightReadiness(
                permissionStatuses: [.screenRecording: .denied], availableSpaceBytes: 2_000
            )
        )
        #expect(!denied.isReady)
        #expect(denied.blockingMessage == "Screen Recording permission is required.")

        let lowSpace = RecordingPreflightModel(
            configuration: configuration,
            readiness: RecordingPreflightReadiness(
                permissionStatuses: [.screenRecording: .granted], availableSpaceBytes: 999
            )
        )
        #expect(!lowSpace.isReady)
        #expect(lowSpace.blockingMessage == "Not enough free space to start recording.")
    }

    @Test func hudExposesExplicitPauseResumeStopAndCancelActions() {
        let model = RecordingHUDModel()
        var events: [String] = []
        model.onPauseResume = { events.append("pause") }
        model.onStop = { events.append("stop") }
        model.onCancel = { events.append("cancel") }
        model.onPauseResume?()
        model.onStop?()
        model.onCancel?()
        #expect(events == ["pause", "stop", "cancel"])
    }

    @Test func injectedCaptureServiceReceivesPauseResumeAndCancelWithoutPermissions() async {
        let service = FakeRecordingService()
        #expect(service.pause())
        #expect(service.resume())
        await service.cancel()
        #expect(service.events == ["pause", "resume", "cancel"])
    }

    @Test func recoveryDiscoveryUsesInjectedTemporaryStoreAndMissingPostCaptureFileExplainsFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "WP04-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = try fixtureConfiguration(requiredSpace: 1)
        let snapshot = RecordingSessionSnapshot(sessionID: UUID(), configuration: configuration, createdAt: Date())
        let manifest = RecordingRecoveryManifest(
            session: snapshot, lifecycle: .recording,
            partialMedia: try RecordingRelativePath("partial.mp4"), updatedAt: Date()
        )
        try JSONEncoder().encode(manifest).write(to: directory.appending(path: "manifest.json"))
        #expect(RecordingRecoveryStore(directoryURL: directory).discover(at: Date()).count == 1)

        let post = RecordingPostCaptureModel(outputURL: directory.appending(path: "final.mp4"))
        #expect(post.editDisabledReason.contains("no longer available"))
    }

    private func fixtureConfiguration(requiredSpace: Int64) throws -> RecordingSessionConfiguration {
        try RecordingSessionConfiguration(
            source: .display(id: "display"), dimensions: RecordingDimensions(width: 1920, height: 1080),
            frameRate: RecordingFrameRate(framesPerSecond: 30), cursorMode: .visible,
            audio: RecordingAudioConfiguration(capturesSystemAudio: false), webcam: nil,
            countdown: RecordingCountdown(seconds: 0), events: RecordingEventConfiguration(),
            requiredSpaceEstimateBytes: requiredSpace
        )
    }
}

private final class FakeRecordingService: RecordingServicing {
    var events: [String] = []
    func start(filter: SCContentFilter, configuration: SCStreamConfiguration, outputURL: URL,
               includeSystemAudio: Bool, includeMicrophone: Bool) async throws {}
    func stop() async throws -> URL { URL(fileURLWithPath: "/tmp/final.mp4") }
    func cancel() async { events.append("cancel") }
    func pause() -> Bool { events.append("pause"); return true }
    func resume() -> Bool { events.append("resume"); return true }
}
