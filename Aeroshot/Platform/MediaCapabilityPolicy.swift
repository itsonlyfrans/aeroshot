import Foundation

/// A stable, testable version value used instead of consulting the host OS in policy tests.
struct MediaOSVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ major: Int, _ minor: Int = 0, _ patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init(_ version: OperatingSystemVersion) {
        self.init(version.majorVersion, version.minorVersion, version.patchVersion)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    var description: String { "\(major).\(minor).\(patch)" }
}

enum MediaFramework: String, Sendable {
    case screenCaptureKit = "ScreenCaptureKit"
    case avFoundation = "AVFoundation"
}

enum MediaCapability: String, CaseIterable, Sendable {
    case screenStream
    case screenshotManager
    case bestCaptureResolution
    case systemAudioCapture
    case microphoneCapture
    case microphoneDeviceSelection
    case hdrCapture
    case recordingOutput
    case assetWriter
    case assetReader
    case mutableComposition
    case offlineCoreAnimationOverlays
    case assetExportSession
}

enum MediaCapabilityRequirement: String, Sendable {
    case required
    case optional
}

enum MediaCapabilityUse: String, Sendable {
    case current
    case planned
    case optionalOptimization
}

enum MediaFallback: String, Sendable {
    case disableMicrophoneCapture
    case sdrCapture
    case avAssetWriter
}

struct MediaCapabilityDescriptor: Equatable, Sendable {
    let capability: MediaCapability
    let framework: MediaFramework
    let minimumOS: MediaOSVersion
    let requirement: MediaCapabilityRequirement
    let use: MediaCapabilityUse
    let fallback: MediaFallback?
}

enum MediaCapabilityDecision: Equatable, Sendable {
    case native
    case fallback(MediaFallback)
    case unavailable
}

enum MediaRecordingBackend: Equatable, Sendable {
    case avAssetWriter
    case screenCaptureKitRecordingOutput
}

/// Central compatibility policy for capture, recording, and planned media editing.
///
/// Keep feature decisions here and keep framework symbols newer than the deployment
/// target in availability-annotated adapters such as `ScreenCaptureRecordingOutputAdapter`.
struct MediaCapabilityPolicy: Sendable {
    static let deploymentTarget = MediaOSVersion(14, 6)

    let runtimeOS: MediaOSVersion

    init(runtimeOS: MediaOSVersion = MediaOSVersion(ProcessInfo.processInfo.operatingSystemVersion)) {
        self.runtimeOS = runtimeOS
    }

    static let descriptors: [MediaCapabilityDescriptor] = [
        .init(capability: .screenStream, framework: .screenCaptureKit,
              minimumOS: .init(12, 3), requirement: .required, use: .current, fallback: nil),
        .init(capability: .screenshotManager, framework: .screenCaptureKit,
              minimumOS: .init(14, 0), requirement: .required, use: .current, fallback: nil),
        .init(capability: .bestCaptureResolution, framework: .screenCaptureKit,
              minimumOS: .init(14, 0), requirement: .required, use: .current, fallback: nil),
        .init(capability: .systemAudioCapture, framework: .screenCaptureKit,
              minimumOS: .init(13, 0), requirement: .optional, use: .current, fallback: nil),
        .init(capability: .microphoneCapture, framework: .screenCaptureKit,
              minimumOS: .init(15, 0), requirement: .optional, use: .current,
              fallback: .disableMicrophoneCapture),
        .init(capability: .microphoneDeviceSelection, framework: .screenCaptureKit,
              minimumOS: .init(15, 0), requirement: .optional, use: .planned,
              fallback: .disableMicrophoneCapture),
        .init(capability: .hdrCapture, framework: .screenCaptureKit,
              minimumOS: .init(15, 0), requirement: .optional, use: .planned, fallback: .sdrCapture),
        .init(capability: .recordingOutput, framework: .screenCaptureKit,
              minimumOS: .init(15, 0), requirement: .optional, use: .optionalOptimization,
              fallback: .avAssetWriter),
        .init(capability: .assetWriter, framework: .avFoundation,
              minimumOS: .init(10, 7), requirement: .required, use: .current, fallback: nil),
        .init(capability: .assetReader, framework: .avFoundation,
              minimumOS: .init(10, 7), requirement: .required, use: .planned, fallback: nil),
        .init(capability: .mutableComposition, framework: .avFoundation,
              minimumOS: .init(10, 7), requirement: .required, use: .planned, fallback: nil),
        .init(capability: .offlineCoreAnimationOverlays, framework: .avFoundation,
              minimumOS: .init(10, 7), requirement: .required, use: .planned, fallback: nil),
        .init(capability: .assetExportSession, framework: .avFoundation,
              minimumOS: .init(10, 7), requirement: .required, use: .planned, fallback: nil),
    ]

    func descriptor(for capability: MediaCapability) -> MediaCapabilityDescriptor {
        // All enum cases are represented by the static matrix and covered by tests.
        Self.descriptors.first { $0.capability == capability }!
    }

    func decision(for capability: MediaCapability) -> MediaCapabilityDecision {
        let descriptor = descriptor(for: capability)
        if runtimeOS >= descriptor.minimumOS {
            return .native
        }
        if let fallback = descriptor.fallback {
            return .fallback(fallback)
        }
        return .unavailable
    }

    /// Preserves the proven writer path unless a future integration explicitly opts
    /// into the newer ScreenCaptureKit recording output on a supported runtime.
    func recordingBackend(allowRecordingOutput: Bool = false) -> MediaRecordingBackend {
        guard allowRecordingOutput, decision(for: .recordingOutput) == .native else {
            return .avAssetWriter
        }
        return .screenCaptureKitRecordingOutput
    }

    static var deploymentTargetSatisfiesRequiredCapabilities: Bool {
        let policy = Self(runtimeOS: deploymentTarget)
        return descriptors
            .filter { $0.requirement == .required }
            .allSatisfy { policy.decision(for: $0.capability) != .unavailable }
    }
}
