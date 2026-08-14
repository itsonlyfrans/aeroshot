import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Aeroshot

@Suite("Release reliability and local diagnostics", .serialized)
struct ReleaseReliabilityTests {
    @Test @MainActor func appLaunchPathsRemainSingleInstance() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Aeroshot-instance-lock-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockURL = directory.appending(path: "instance.lock")

        var first: SingleInstanceLock? = try SingleInstanceLock(url: lockURL)
        #expect(first != nil)
        #expect(throws: SingleInstanceLock.AcquisitionError.alreadyRunning) {
            _ = try SingleInstanceLock(url: lockURL)
        }
        first = nil
        _ = try SingleInstanceLock(url: lockURL)

        let testEnvironment = [
            "XCTestSessionIdentifier": UUID().uuidString,
            "XCTestBundlePath": "Contents/PlugIns/AeroshotTests.xctest"
        ]
        #expect(SingleInstanceLock.isHostedUnitTest(environment: testEnvironment))
        #expect(!SingleInstanceLock.isHostedUnitTest(environment: [
            "XCTestSessionIdentifier": UUID().uuidString,
            "XCTestBundlePath": "Contents/PlugIns/AeroshotUITests.xctest"
        ]))
        #expect(!SingleInstanceLock.isHostedUnitTest(environment: [:]))
        #expect(SingleInstanceLock.isHostedUITest(environment: ["AEROSHOT_UI_TEST": "1"]))
        #expect(!SingleInstanceLock.isHostedUITest(environment: [:]))

        let script = try String(contentsOf: root.appending(path: "script/build_and_run.sh"), encoding: .utf8)
        #expect(!script.contains("/usr/bin/open -n"))

        let onboarding = try String(
            contentsOf: root.appending(path: "Aeroshot/Settings/OnboardingWindowController.swift"),
            encoding: .utf8
        )
        #expect(!onboarding.contains("createsNewApplicationInstance = true"))
        #expect(onboarding.contains(#"while /bin/kill -0 "$1""#))
    }

    @Test @MainActor func diagnosticsDefaultOffAndRequireExplicitConsent() throws {
        let suite = "Aeroshot.ReleaseReliability." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = DiagnosticConsentStore(defaults: defaults)
        let diagnostics = LocalDiagnostics(consent: consent)

        #expect(!consent.isEnabled)
        diagnostics.record(DiagnosticEvent(subsystem: .application, outcome: .started))
        #expect(diagnostics.events.isEmpty)
        let destination = temporaryDirectory().appending(path: "support.json")
        defer { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }
        #expect(throws: DiagnosticSupportBundleError.consentRequired) {
            try diagnostics.exportSupportBundle(to: destination)
        }

        consent.setEnabled(true)
        diagnostics.record(DiagnosticEvent(subsystem: .application, outcome: .succeeded))
        #expect(diagnostics.events.count == 1)
        consent.setEnabled(false)
        diagnostics.record(DiagnosticEvent(subsystem: .application, outcome: .failed))
        #expect(diagnostics.events.count == 1)
    }

    @Test func adversarialSanitizerRejectsContentAndUnknownMetadata() {
        let sentinels: [String: Any] = [
            "pixels": Data([0xde, 0xad]), "ocr": "PRIVATE OCR", "event_data": "key:A",
            "window_title": "Payroll", "filename": "taxes.png", "path": "/Users/owl/private",
            "url": "https://secret.example/?token=abc", "token": "bearer-123", "secret": "hunter2",
            "attempt_count": "7", "prior_data_retained": "true", "unknown": 99,
            "item_count": NSNumber(value: 4), "cache_rebuilt": true
        ]
        let sanitized = DiagnosticSanitizer.sanitize(sentinels)
        #expect(sanitized.counters == ["item_count": 4])
        #expect(sanitized.flags == ["cache_rebuilt": true])
    }

    @Test @MainActor func supportBundleContainsOnlyTypedSanitizedData() throws {
        let suite = "Aeroshot.ReleaseReliability." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = DiagnosticConsentStore(defaults: defaults)
        consent.setEnabled(true)
        let diagnostics = LocalDiagnostics(consent: consent)
        diagnostics.record(DiagnosticEvent(
            timestamp: Date(timeIntervalSince1970: 0), subsystem: .project, outcome: .recovered,
            counters: ["generation": 2, "filename": 999],
            flags: ["prior_data_retained": true, "has_secret": true]
        ))
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(path: "support.json")
        try diagnostics.exportSupportBundle(to: destination, now: Date(timeIntervalSince1970: 1))
        let data = try Data(contentsOf: destination)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DiagnosticSupportBundle.self, from: data)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(decoded.events.first?.counters == ["generation": 2])
        #expect(decoded.events.first?.flags == ["prior_data_retained": true])
        for forbidden in ["filename", "path", "url", "token", "secret", "ocr", "pixels"] {
            #expect(!text.localizedCaseInsensitiveContains(forbidden))
        }
    }

    @Test func corruptManifestAndAssetFailClosedWhilePriorGenerationRecovers() throws {
        try withProject { store in
            let asset = try store.storeOriginal(
                Data("original".utf8), fileExtension: "png", metadata: imageMetadata()
            )
            let first = try store.save(AeroProjectManifest(assets: [asset], primarySourceAssetID: asset.id))
            var second = first
            second.canvas.background = .transparent
            _ = try store.save(second)
            try Data("corrupt".utf8).write(to: store.packageURL.appending(path: AeroProjectPackageStore.manifestFileName))
            let recovered = try store.loadRecoveringIfNeeded()
            #expect(recovered.id == first.id)
            #expect(recovered.canvas == first.canvas)
            #expect(recovered.assets == first.assets)
            #expect(recovered.recovery.generation == first.recovery.generation)

            try Data("tampered".utf8).write(to: store.URL(forRelativePath: asset.relativePath))
            #expect(throws: (any Error).self) { try store.load() }
        }
    }

    @Test func interruptedSaveAndStaleCacheRetainImmutablePriorData() throws {
        struct Interrupted: Error {}
        try withProject { store in
            let bytes = Data("immutable source".utf8)
            let asset = try store.storeOriginal(bytes, fileExtension: "png", metadata: imageMetadata())
            let first = try store.save(AeroProjectManifest(assets: [asset], primarySourceAssetID: asset.id))
            let stale = store.packageURL.appending(path: "generated/stale.cache")
            try Data("stale derivative".utf8).write(to: stale)
            var changed = first
            changed.canvas.background = .solid
            #expect(throws: Interrupted.self) {
                try store.save(changed) { if $0 == .beforeAtomicReplacement { throw Interrupted() } }
            }
            let retained = try store.load()
            #expect(retained.id == first.id)
            #expect(retained.canvas == first.canvas)
            #expect(retained.assets == first.assets)
            #expect(retained.recovery.generation == first.recovery.generation)
            #expect(try Data(contentsOf: store.URL(forRelativePath: asset.relativePath)) == bytes)
        }
    }

    @Test func everyAtomicSaveBoundaryPreservesPriorDataForInjectedSystemFailures() throws {
        struct InjectedSaveFailure: Error {
            let kind: String
        }
        let failures = ["process-termination", "disk-full", "write-denied"]

        for stage in AeroProjectSaveStage.allCases {
            for failure in failures {
                try withProject { store in
                    let bytes = Data("immutable original \(failure)".utf8)
                    let asset = try store.storeOriginal(
                        bytes,
                        fileExtension: "png",
                        metadata: imageMetadata()
                    )
                    let first = try store.save(AeroProjectManifest(
                        assets: [asset],
                        primarySourceAssetID: asset.id
                    ))
                    var changed = first
                    changed.canvas.background = .transparent

                    #expect(throws: InjectedSaveFailure.self) {
                        try store.save(changed) { reachedStage in
                            if reachedStage == stage {
                                throw InjectedSaveFailure(kind: failure)
                            }
                        }
                    }

                    let retained = try store.load()
                    #expect(retained.id == first.id)
                    #expect(retained.canvas == first.canvas)
                    #expect(retained.recovery.generation == first.recovery.generation)
                    #expect(try Data(contentsOf: store.URL(forRelativePath: asset.relativePath)) == bytes)
                    let leftovers = try FileManager.default.contentsOfDirectory(atPath: store.packageURL.path)
                    #expect(leftovers.allSatisfy { !$0.hasPrefix(".manifest-") })
                }
            }
        }
    }

    @Test func missingMediaSourceDoesNotReplaceExistingDestination() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(path: "existing.mp4")
        let sentinel = Data("valid prior export".utf8)
        try sentinel.write(to: destination)
        let source = directory.appending(path: "missing.mp4")
        let metadata = AeroMediaMetadata(
            mediaType: .video, pixelSize: try AeroPixelSize(width: 320, height: 240),
            duration: try AeroMediaTime(value: 1, timescale: 1),
            nominalFrameRate: try AeroMediaTime(value: 30, timescale: 1), colorSpaceName: nil, hasAudio: false
        )
        let asset = AeroProjectAsset(
            id: UUID(), relativePath: "missing.mp4", sha256: "none", byteCount: 0,
            isImmutableOriginal: true, metadata: metadata
        )
        let snapshot = MediaExportSnapshot(projectID: UUID(), sourceURL: source, sourceAsset: asset, canvas: .source)
        let preset = MediaExportPreset.h264(
            size: try AeroPixelSize(width: 320, height: 240), frameRate: try AeroMediaTime(value: 30, timescale: 1)
        )
        await #expect(throws: MediaExportError.sourceUnavailable) {
            try await MediaExportCoordinator().export(snapshot: snapshot, preset: preset, destination: destination)
        }
        #expect(try Data(contentsOf: destination) == sentinel)
    }

    @Test func interruptedGIFRetainsDestinationAndLowSpaceLeavesNoOverflow() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(path: "existing.gif")
        let sentinel = Data("valid prior gif".utf8)
        try sentinel.write(to: destination)
        let missing = directory.appending(path: "missing.png")
        let document = try GIFDocument(frames: [try GIFFrame(sourceURL: missing, durationMicroseconds: 50_000)])
        await #expect(throws: (any Error).self) { try await GIFWriter().write(document, to: destination) }
        #expect(try Data(contentsOf: destination) == sentinel)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy { !$0.contains(".partial-") })

        let spoolDirectory = directory.appending(path: "spool", directoryHint: .isDirectory)
        let spool = try GIFFrameSpool(directoryURL: spoolDirectory, limits: .init(maximumFrameCount: 2, maximumBytes: 1))
        #expect(try spool.append(image(), durationMicroseconds: 50_000) == false)
        #expect(spool.statistics.byteCount == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: spoolDirectory.path).isEmpty)
    }

    @Test func corruptAndInterruptedGIFPartialsNeverReplaceTheDestination() async throws {
        struct InjectedInterruption: Error {}
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let frameURL = directory.appending(path: "frame.png")
        try ImageExporter.write(image(), to: frameURL, format: .png)
        let document = try GIFDocument(frames: [
            try GIFFrame(sourceURL: frameURL, durationMicroseconds: 50_000)
        ])
        let destination = directory.appending(path: "existing.gif")
        let sentinel = Data("valid prior gif".utf8)

        for mode in ["frame", "corrupt", "interrupt"] {
            try sentinel.write(to: destination, options: .atomic)
            do {
                _ = try await GIFWriter().write(document, to: destination) { stage in
                    switch (mode, stage) {
                    case ("frame", .frameEncoded):
                        throw InjectedInterruption()
                    case ("corrupt", .partialFinished(let partial)):
                        try Data("corrupt generated gif".utf8).write(to: partial, options: .atomic)
                    case ("interrupt", .beforeAtomicCommit):
                        throw InjectedInterruption()
                    default:
                        break
                    }
                }
                Issue.record("Expected \(mode) GIF write to fail")
            } catch {}

            #expect(try Data(contentsOf: destination) == sentinel)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).allSatisfy {
                !$0.contains(".partial-")
            })
        }
    }

    @Test func recoveryDiscoverySkipsCorruptionAndKeepsValidSession() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = Date(timeIntervalSince1970: 10)
        let configuration = try RecordingSessionConfiguration(
            source: .display(id: "display"), dimensions: RecordingDimensions(width: 100, height: 100),
            frameRate: RecordingFrameRate(framesPerSecond: 30), cursorMode: .visible,
            audio: RecordingAudioConfiguration(capturesSystemAudio: false), webcam: nil,
            countdown: RecordingCountdown(seconds: 0), events: RecordingEventConfiguration(),
            requiredSpaceEstimateBytes: 1
        )
        let manifest = RecordingRecoveryManifest(
            session: RecordingSessionSnapshot(sessionID: UUID(), configuration: configuration, createdAt: date),
            lifecycle: .recording, partialMedia: try RecordingRelativePath("partial/session.mov"),
            updatedAt: date
        )
        try JSONEncoder().encode(manifest).write(to: directory.appending(path: "valid.json"))
        try Data("not json".utf8).write(to: directory.appending(path: "corrupt.json"))
        #expect(RecordingRecoveryStore(directoryURL: directory).discover(at: date) == [manifest])
    }

    @Test func automationRejectsRemoteTraversalRelativeDuplicateAndUnknownInputs() throws {
        let urls = [
            "https://capture?mode=area",
            "aeroshot://open-project?path=https%3A%2F%2Fexample.com%2Fx",
            "aeroshot://open-project?path=..%2Fprivate",
            "aeroshot://capture?mode=area&mode=screen",
            "aeroshot://shell?command=rm"
        ]
        for raw in urls {
            #expect(throws: AutomationParseError.self) { try AutomationActionParser.parse(url: #require(URL(string: raw))) }
        }
        #expect(throws: AutomationParseError.self) { try AutomationActionParser.localURL("relative/file", name: "path") }
    }

    @Test @MainActor func libraryReconciliationMarksMissingAndRemovesDuplicate() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "source.bin")
        try Data("same".utf8).write(to: source)
        let store = HistoryStore(directory: directory, trashHandler: { _ in })
        let first = try #require(store.addArtifact(from: source, kind: .recording))
        let second = try #require(store.addArtifact(from: source, kind: .recording))
        try FileManager.default.removeItem(at: store.fileURL(for: first))
        let result = store.reconcile()
        #expect(result.removedDuplicateIDs == [first.id])
        #expect(result.missingItemIDs == [first.id])
        #expect(store.items.map(\.id) == [second.id])
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "Aeroshot-Reliability-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func withProject(_ body: (AeroProjectPackageStore) throws -> Void) throws {
        let url = temporaryDirectory().appending(path: "Project.aeroshot", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try body(AeroProjectPackageStore(packageURL: url, now: { Date(timeIntervalSince1970: 0) }))
    }

    private func imageMetadata() -> AeroMediaMetadata {
        AeroMediaMetadata(
            mediaType: .image, pixelSize: try! AeroPixelSize(width: 1, height: 1),
            duration: nil, nominalFrameRate: nil, colorSpaceName: nil, hasAudio: false
        )
    }

    private func image() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try #require(context.makeImage())
    }
}
