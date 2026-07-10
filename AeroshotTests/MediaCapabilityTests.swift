import Testing
@testable import Aeroshot

@MainActor
struct MediaCapabilityTests {
    @Test func matrixHasExactlyOneEntryForEveryCapability() {
        let capabilities = MediaCapabilityPolicy.descriptors.map(\.capability)

        #expect(capabilities.count == MediaCapability.allCases.count)
        #expect(Set(capabilities).count == MediaCapability.allCases.count)
    }

    @Test func deploymentTargetSupportsEveryRequiredCapability() {
        #expect(MediaCapabilityPolicy.deploymentTarget == MediaOSVersion(14, 6))
        #expect(MediaCapabilityPolicy.deploymentTargetSatisfiesRequiredCapabilities)
    }

    @Test func macOS146UsesDocumentedFallbacksForNewScreenCaptureKitFeatures() {
        let policy = MediaCapabilityPolicy(runtimeOS: .init(14, 6))

        #expect(policy.decision(for: .microphoneCapture) == .fallback(.disableMicrophoneCapture))
        #expect(policy.decision(for: .microphoneDeviceSelection) == .fallback(.disableMicrophoneCapture))
        #expect(policy.decision(for: .hdrCapture) == .fallback(.sdrCapture))
        #expect(policy.decision(for: .recordingOutput) == .fallback(.avAssetWriter))
    }

    @Test func macOS15EnablesNewScreenCaptureKitCapabilities() {
        let policy = MediaCapabilityPolicy(runtimeOS: .init(15, 0))

        #expect(policy.decision(for: .microphoneCapture) == .native)
        #expect(policy.decision(for: .microphoneDeviceSelection) == .native)
        #expect(policy.decision(for: .hdrCapture) == .native)
        #expect(policy.decision(for: .recordingOutput) == .native)
    }

    @Test func recordingOutputNeverChangesBackendWithoutExplicitOptIn() {
        let oldRuntime = MediaCapabilityPolicy(runtimeOS: .init(14, 6))
        let newRuntime = MediaCapabilityPolicy(runtimeOS: .init(15, 0))

        #expect(oldRuntime.recordingBackend() == .avAssetWriter)
        #expect(newRuntime.recordingBackend() == .avAssetWriter)
        #expect(oldRuntime.recordingBackend(allowRecordingOutput: true) == .avAssetWriter)
        #expect(newRuntime.recordingBackend(allowRecordingOutput: true) == .screenCaptureKitRecordingOutput)
    }

    @Test func currentMacOS146CaptureAndWriterPathIsNative() {
        let policy = MediaCapabilityPolicy(runtimeOS: .init(14, 6))

        #expect(policy.decision(for: .screenStream) == .native)
        #expect(policy.decision(for: .screenshotManager) == .native)
        #expect(policy.decision(for: .bestCaptureResolution) == .native)
        #expect(policy.decision(for: .systemAudioCapture) == .native)
        #expect(policy.decision(for: .assetWriter) == .native)
    }
}
