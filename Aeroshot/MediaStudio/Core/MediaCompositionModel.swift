import Foundation

nonisolated struct MediaSourceAsset: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let url: URL
    let duration: RationalTime
    var hasVideo = true
    var hasAudio = true
}

nonisolated struct MediaSlice: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    let sourceAssetID: UUID
    var sourceRange: RationalTimeRange
}

nonisolated struct SourcePosition: Codable, Hashable, Sendable {
    let assetID: UUID
    let time: RationalTime
}

nonisolated enum TimedOverlayKind: String, Codable, Hashable, Sendable { case callout, text, shape, image }

nonisolated struct NormalizedOverlayBounds: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let legacyCallout = NormalizedOverlayBounds(x: 0.1, y: 0.1, width: 0.35, height: 0.15)

    var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 &&
            width > 0 && height > 0 && x + width <= 1 && y + height <= 1
    }
}

nonisolated struct SRGBAColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let legacyCallout = SRGBAColor(red: 1, green: 0.75, blue: 0.1, alpha: 1)

    var components: [Double] { [red, green, blue, alpha] }
    var isValid: Bool { components.allSatisfy { $0.isFinite && (0...1).contains($0) } }
}

nonisolated struct TimedOverlay: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    let kind: TimedOverlayKind
    var range: RationalTimeRange
    var payload: String
    var bounds: NormalizedOverlayBounds = .legacyCallout
    var color: SRGBAColor = .legacyCallout
}

nonisolated struct NormalizedCrop: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

nonisolated struct CanvasState: Codable, Hashable, Sendable {
    var crop: NormalizedCrop?
    var width: Int
    var height: Int
}

nonisolated struct AudioState: Codable, Hashable, Sendable {
    var isMuted = false
    var gain: Float = 1
    var fadeIn = RationalTime.zero
    var fadeOut = RationalTime.zero

    private enum CodingKeys: String, CodingKey { case isMuted, gain, fadeIn, fadeOut }

    init(isMuted: Bool = false, gain: Float = 1, fadeIn: RationalTime = .zero, fadeOut: RationalTime = .zero) {
        self.isMuted = isMuted
        self.gain = gain
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isMuted = try values.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        gain = try values.decodeIfPresent(Float.self, forKey: .gain) ?? 1
        fadeIn = try values.decodeIfPresent(RationalTime.self, forKey: .fadeIn) ?? .zero
        fadeOut = try values.decodeIfPresent(RationalTime.self, forKey: .fadeOut) ?? .zero
    }
}

nonisolated struct RequestSize: Codable, Hashable, Sendable { let width: Int; let height: Int }
nonisolated struct ThumbnailRequest: Codable, Hashable, Sendable { let assetID: UUID; let times: [RationalTime]; let maximumSize: RequestSize }
nonisolated struct WaveformRequest: Codable, Hashable, Sendable { let assetID: UUID; let range: RationalTimeRange; let sampleCount: Int }

nonisolated enum RecordedEffectKind: String, Codable, Hashable, Sendable { case cursor, click }
nonisolated struct RecordedEffectEvent: Codable, Hashable, Sendable {
    var kind: RecordedEffectKind
    var timeMicroseconds: Int64
    var x: Double
    var y: Double
}

nonisolated struct FreezeFrameEffect: Codable, Hashable, Sendable {
    var timeMicroseconds: Int64
    var durationMicroseconds: Int64
}

nonisolated struct WebcamEffect: Codable, Hashable, Sendable {
    var isEnabled = false
    var sourceAssetID: UUID?
    var corner = "BR"
    var isCircular = true
}

nonisolated struct PresentationEffectsState: Codable, Hashable, Sendable {
    var events: [RecordedEffectEvent] = []
    var cursorEmphasis: Double = 0
    var clickEmphasis: Double = 0
    var freezeFrame: FreezeFrameEffect?
    /// `nil` keeps the source aspect ratio. Other values use the UI aspect labels.
    var reframeAspectRatio: String?
    var webcam = WebcamEffect()
    var punchInClickTimes: [Int64] = []
    var clickSound = "off"

    private enum CodingKeys: String, CodingKey {
        case events, cursorEmphasis, clickEmphasis, freezeFrame, reframeAspectRatio
        case webcam, punchInClickTimes, clickSound
    }

    init(events: [RecordedEffectEvent] = [], cursorEmphasis: Double = 0, clickEmphasis: Double = 0,
         freezeFrame: FreezeFrameEffect? = nil, reframeAspectRatio: String? = nil,
         webcam: WebcamEffect = .init(), punchInClickTimes: [Int64] = [], clickSound: String = "off") {
        self.events = events
        self.cursorEmphasis = cursorEmphasis
        self.clickEmphasis = clickEmphasis
        self.freezeFrame = freezeFrame
        self.reframeAspectRatio = reframeAspectRatio
        self.webcam = webcam
        self.punchInClickTimes = punchInClickTimes
        self.clickSound = clickSound
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            events: try values.decodeIfPresent([RecordedEffectEvent].self, forKey: .events) ?? [],
            cursorEmphasis: try values.decodeIfPresent(Double.self, forKey: .cursorEmphasis) ?? 0,
            clickEmphasis: try values.decodeIfPresent(Double.self, forKey: .clickEmphasis) ?? 0,
            freezeFrame: try values.decodeIfPresent(FreezeFrameEffect.self, forKey: .freezeFrame),
            reframeAspectRatio: try values.decodeIfPresent(String.self, forKey: .reframeAspectRatio),
            webcam: try values.decodeIfPresent(WebcamEffect.self, forKey: .webcam) ?? .init(),
            punchInClickTimes: try values.decodeIfPresent([Int64].self, forKey: .punchInClickTimes) ?? [],
            clickSound: try values.decodeIfPresent(String.self, forKey: .clickSound) ?? "off"
        )
    }
}

nonisolated enum MediaModelValidationError: Error, Codable, Hashable, Sendable {
    case duplicateAsset(UUID)
    case invalidAssetDuration(UUID)
    case missingAsset(UUID)
    case invalidSourceRange(sliceIndex: Int)
    case sourceRangeOutsideAsset(sliceIndex: Int)
    case invalidOverlayRange(UUID)
    case invalidOverlayBounds(UUID)
    case invalidOverlayColor(UUID)
    case invalidCrop
    case invalidCanvas
    case invalidAudioGain
    case invalidAudioFade
    case invalidEffectEvent
    case invalidPresentationEffect
}

nonisolated struct MediaCompositionModel: Codable, Hashable, Sendable {
    var assets: [MediaSourceAsset]
    var slices: [MediaSlice]
    var overlays: [TimedOverlay] = []
    var canvas: CanvasState?
    var audio = AudioState()
    var effects = PresentationEffectsState()

    var duration: RationalTime {
        slices.reduce(.zero) { result, slice in (try? result + slice.sourceRange.duration) ?? result }
    }

    func validate() -> [MediaModelValidationError] {
        var errors: [MediaModelValidationError] = []
        var assetByID: [UUID: MediaSourceAsset] = [:]
        for asset in assets {
            if assetByID.updateValue(asset, forKey: asset.id) != nil { errors.append(.duplicateAsset(asset.id)) }
            if asset.duration < .zero { errors.append(.invalidAssetDuration(asset.id)) }
        }
        for (index, slice) in slices.enumerated() {
            guard let asset = assetByID[slice.sourceAssetID] else { errors.append(.missingAsset(slice.sourceAssetID)); continue }
            if slice.sourceRange.start < .zero || slice.sourceRange.duration <= .zero {
                errors.append(.invalidSourceRange(sliceIndex: index))
            } else if slice.sourceRange.end > asset.duration {
                errors.append(.sourceRangeOutsideAsset(sliceIndex: index))
            }
        }
        for overlay in overlays where overlay.range.start < .zero || overlay.range.duration < .zero || overlay.range.end > duration {
            errors.append(.invalidOverlayRange(overlay.id))
        }
        for overlay in overlays {
            if !overlay.bounds.isValid { errors.append(.invalidOverlayBounds(overlay.id)) }
            if !overlay.color.isValid { errors.append(.invalidOverlayColor(overlay.id)) }
        }
        if let canvas {
            if canvas.width <= 0 || canvas.height <= 0 { errors.append(.invalidCanvas) }
            if let crop = canvas.crop,
               ![crop.x, crop.y, crop.width, crop.height].allSatisfy(\.isFinite) ||
               crop.x < 0 || crop.y < 0 || crop.width <= 0 || crop.height <= 0 || crop.x + crop.width > 1 || crop.y + crop.height > 1 {
                errors.append(.invalidCrop)
            }
        }
        if !audio.gain.isFinite || audio.gain < 0 { errors.append(.invalidAudioGain) }
        if audio.fadeIn < .zero || audio.fadeOut < .zero ||
            ((try? audio.fadeIn + audio.fadeOut) ?? duration) > duration {
            errors.append(.invalidAudioFade)
        }
        let durationMicroseconds = Int64(max(0, duration.seconds * 1_000_000))
        if effects.events.contains(where: { $0.timeMicroseconds < 0 || $0.timeMicroseconds > durationMicroseconds || !$0.x.isFinite || !$0.y.isFinite || !(0...1).contains($0.x) || !(0...1).contains($0.y) }) ||
            !effects.cursorEmphasis.isFinite || !(0...2).contains(effects.cursorEmphasis) ||
            !effects.clickEmphasis.isFinite || !(0...2).contains(effects.clickEmphasis) {
            errors.append(.invalidEffectEvent)
        }
        let validRatios: Set<String> = ["16:9", "1:1", "9:16", "4:5"]
        let validSounds: Set<String> = ["off", "snug_click", "pebble_tap", "latch_tap", "wisp_puff"]
        if (effects.freezeFrame.map {
            $0.timeMicroseconds < 0 || $0.timeMicroseconds > durationMicroseconds ||
            $0.durationMicroseconds <= 0 || $0.durationMicroseconds > 10_000_000
        } ?? false) ||
           (effects.reframeAspectRatio.map { !validRatios.contains($0) } ?? false) ||
           !["TL", "TR", "BL", "BR"].contains(effects.webcam.corner) ||
           effects.punchInClickTimes.contains(where: { $0 < 0 || $0 > durationMicroseconds }) ||
           !validSounds.contains(effects.clickSound) {
            errors.append(.invalidPresentationEffect)
        }
        return errors
    }
}
