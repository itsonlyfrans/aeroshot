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

nonisolated struct TimedOverlay: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    let kind: TimedOverlayKind
    var range: RationalTimeRange
    var payload: String
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
}

nonisolated struct RequestSize: Codable, Hashable, Sendable { let width: Int; let height: Int }
nonisolated struct ThumbnailRequest: Codable, Hashable, Sendable { let assetID: UUID; let times: [RationalTime]; let maximumSize: RequestSize }
nonisolated struct WaveformRequest: Codable, Hashable, Sendable { let assetID: UUID; let range: RationalTimeRange; let sampleCount: Int }

nonisolated enum MediaModelValidationError: Error, Codable, Hashable, Sendable {
    case duplicateAsset(UUID)
    case invalidAssetDuration(UUID)
    case missingAsset(UUID)
    case invalidSourceRange(sliceIndex: Int)
    case sourceRangeOutsideAsset(sliceIndex: Int)
    case invalidOverlayRange(UUID)
    case invalidCrop
    case invalidCanvas
    case invalidAudioGain
}

nonisolated struct MediaCompositionModel: Codable, Hashable, Sendable {
    var assets: [MediaSourceAsset]
    var slices: [MediaSlice]
    var overlays: [TimedOverlay] = []
    var canvas: CanvasState?
    var audio = AudioState()

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
        if let canvas {
            if canvas.width <= 0 || canvas.height <= 0 { errors.append(.invalidCanvas) }
            if let crop = canvas.crop,
               crop.x < 0 || crop.y < 0 || crop.width <= 0 || crop.height <= 0 || crop.x + crop.width > 1 || crop.y + crop.height > 1 {
                errors.append(.invalidCrop)
            }
        }
        if !audio.gain.isFinite || audio.gain < 0 { errors.append(.invalidAudioGain) }
        return errors
    }
}
