import Foundation

nonisolated enum AeroProjectSchema {
    static let currentVersion = 1
}

nonisolated struct AeroProjectCompatibility: Codable, Equatable, Sendable {
    var minimumReaderVersion: Int
    var minimumWriterVersion: Int
    var createdByBuild: String

    init(
        minimumReaderVersion: Int = AeroProjectSchema.currentVersion,
        minimumWriterVersion: Int = AeroProjectSchema.currentVersion,
        createdByBuild: String = "Aeroshot"
    ) {
        self.minimumReaderVersion = minimumReaderVersion
        self.minimumWriterVersion = minimumWriterVersion
        self.createdByBuild = createdByBuild
    }
}

nonisolated enum AeroProjectModelError: Error, Equatable {
    case invalidMediaTime
    case invalidTimeRange
    case invalidDimensions
}

/// An exact media timestamp. Values are reduced on creation so equality and
/// persistence are deterministic without converting through floating point.
nonisolated struct AeroMediaTime: Codable, Equatable, Hashable, Comparable, Sendable {
    let value: Int64
    let timescale: Int32

    init(value: Int64, timescale: Int32) throws {
        guard timescale > 0, !(value == .min && timescale == -1) else {
            throw AeroProjectModelError.invalidMediaTime
        }
        let divisor = Self.greatestCommonDivisor(value.magnitude, UInt64(timescale))
        self.value = value / Int64(divisor)
        self.timescale = timescale / Int32(divisor)
    }

    static let zero = try! AeroMediaTime(value: 0, timescale: 1)

    private enum CodingKeys: String, CodingKey { case value, timescale }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            value: values.decode(Int64.self, forKey: .value),
            timescale: values.decode(Int32.self, forKey: .timescale)
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(value, forKey: .value)
        try values.encode(timescale, forKey: .timescale)
    }

    static func < (lhs: AeroMediaTime, rhs: AeroMediaTime) -> Bool {
        let left = Decimal(lhs.value) * Decimal(rhs.timescale)
        let right = Decimal(rhs.value) * Decimal(lhs.timescale)
        return left < right
    }

    private static func greatestCommonDivisor(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        var a = lhs
        var b = rhs
        while b != 0 {
            (a, b) = (b, a % b)
        }
        return max(a, 1)
    }
}

nonisolated struct AeroMediaTimeRange: Codable, Equatable, Sendable {
    var start: AeroMediaTime
    var duration: AeroMediaTime

    init(start: AeroMediaTime, duration: AeroMediaTime) throws {
        guard duration.value >= 0 else { throw AeroProjectModelError.invalidTimeRange }
        self.start = start
        self.duration = duration
    }

    private enum CodingKeys: String, CodingKey { case start, duration }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            start: values.decode(AeroMediaTime.self, forKey: .start),
            duration: values.decode(AeroMediaTime.self, forKey: .duration)
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(start, forKey: .start)
        try values.encode(duration, forKey: .duration)
    }
}

nonisolated struct AeroPixelSize: Codable, Equatable, Sendable {
    var width: Int
    var height: Int

    init(width: Int, height: Int) throws {
        guard width > 0, height > 0 else { throw AeroProjectModelError.invalidDimensions }
        self.width = width
        self.height = height
    }

    private enum CodingKeys: String, CodingKey { case width, height }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            width: values.decode(Int.self, forKey: .width),
            height: values.decode(Int.self, forKey: .height)
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(width, forKey: .width)
        try values.encode(height, forKey: .height)
    }
}

nonisolated struct AeroMediaMetadata: Codable, Equatable, Sendable {
    enum MediaType: String, Codable, Sendable { case image, video, gif, audio, auxiliary }

    var mediaType: MediaType
    var pixelSize: AeroPixelSize?
    var duration: AeroMediaTime?
    var nominalFrameRate: AeroMediaTime?
    var colorSpaceName: String?
    var hasAudio: Bool
}

nonisolated struct AeroProjectAsset: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let relativePath: String
    let sha256: String
    let byteCount: Int64
    let isImmutableOriginal: Bool
    let metadata: AeroMediaMetadata
}

nonisolated struct AeroNormalizedRect: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let full = AeroNormalizedRect(x: 0, y: 0, width: 1, height: 1)
}

nonisolated struct AeroProjectCanvas: Codable, Equatable, Sendable {
    enum Background: String, Codable, Sendable { case transparent, source, solid }
    enum ColorSpacePolicy: String, Codable, Sendable { case preserveSource, sRGB, displayP3 }

    var crop: AeroNormalizedRect
    var background: Background
    var backgroundColorRGBA: [Double]?
    var aspectRatio: AeroMediaTime?
    var colorSpacePolicy: ColorSpacePolicy

    static let source = AeroProjectCanvas(
        crop: .full,
        background: .source,
        backgroundColorRGBA: nil,
        aspectRatio: nil,
        colorSpacePolicy: .preserveSource
    )
}

nonisolated struct AeroOverlay: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case arrow, text, step, shape, blur, pixelate, solidRedaction }

    struct Geometry: Codable, Equatable, Sendable {
        var bounds: AeroNormalizedRect
        var points: [AeroPoint]
    }

    struct Appearance: Codable, Equatable, Sendable {
        var strokeRGBA: [Double]
        var fillRGBA: [Double]?
        var strokeWidth: Double
        var opacity: Double
    }

    struct Transform: Codable, Equatable, Sendable {
        var rotationRadians: Double
        var scaleX: Double
        var scaleY: Double
    }

    let id: UUID
    var kind: Kind
    var geometry: Geometry
    var appearance: Appearance
    var transform: Transform
    var zIndex: Int
    var timeRange: AeroMediaTimeRange?
    /// User-visible overlay content used by media preview and offline export.
    var content: String? = nil
    /// Screenshot-editor-only data. Optional so manifests written before the
    /// screenshot adapter continue to decode unchanged.
    var editor: AeroEditorOverlayData? = nil
}

nonisolated struct AeroPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
}

nonisolated struct AeroRect: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

nonisolated struct AeroEditorOverlayData: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case arrow, rectangle, ellipse, line, freehand, highlighter, text
        case redactBlur, redactPixelate, redactSolid, step
    }

    var kind: Kind
    var text: String
    var fontSize: Double
    var stepNumber: Int
    var filled: Bool
    /// Typed editor-only appearance. Absent in version-1 manifests and
    /// interpreted by the editor bridge as the historical rendering defaults.
    var appearance: AeroEditorAnnotationAppearance? = nil
}

nonisolated struct AeroEditorAnnotationAppearance: Codable, Equatable, Sendable {
    struct Shadow: Codable, Equatable, Sendable {
        var colorRGBA: [Double]
        var opacity: Double
        var radius: Double
        var offsetX: Double
        var offsetY: Double
    }

    struct Insets: Codable, Equatable, Sendable {
        var top: Double
        var leading: Double
        var bottom: Double
        var trailing: Double
    }

    var strokeOpacity: Double
    var strokeDash: [Double]
    var strokeDashPhase: Double
    var strokeLineCap: String
    var strokeShadow: Shadow
    var fillOpacity: Double
    var cornerRadius: Double
    var arrowStartStyle: String
    var arrowEndStyle: String
    var arrowHeadLength: Double?
    var arrowHeadWidth: Double?
    var arrowInset: Double?
    var arrowCurve: Double
    var fontName: String?
    var fontWeight: Double
    var textAlignment: String
    var textBackgroundRGBA: [Double]?
    var textBackgroundOpacity: Double
    var textPadding: Insets
    var lineHeight: Double
}

nonisolated struct AeroEditorBeautifySettings: Codable, Equatable, Sendable {
    var enabled: Bool
    var padding: Double
    var cornerRadius: Double
    var shadowRadius: Double
    var shadowOpacity: Double
    var gradient: String
    var aspectPreset: String
}

nonisolated struct AeroTimelineItem: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case sourceRange, trim, speed, freeze, audioState }
    let id: UUID
    var kind: Kind
    var sourceAssetID: UUID?
    var timeRange: AeroMediaTimeRange?
}

nonisolated struct AeroEventTrack: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case cursor, clicks, keystrokes, webcamPresentation }
    let id: UUID
    var kind: Kind
    var isEnabled: Bool
    var assetID: UUID?
}

nonisolated struct AeroExportPreset: Codable, Equatable, Identifiable, Sendable {
    enum Format: String, Codable, Sendable { case png, jpeg, mp4, gif }
    let id: UUID
    var name: String
    var format: Format
    var pixelSize: AeroPixelSize?
    var frameRate: AeroMediaTime?
}

nonisolated struct AeroLastExport: Codable, Equatable, Sendable {
    var presetID: UUID
    var completedAt: Date
    var byteCount: Int64
    var outputChecksum: String
}

/// Lossless persisted representation of the media core. Kept separate from the
/// original generic timeline fields so version-1 screenshot manifests retain
/// their exact schema and semantics.
nonisolated struct AeroMediaCompositionState: Codable, Equatable, Sendable {
    struct Slice: Codable, Equatable, Identifiable, Sendable {
        let id: UUID
        var sourceAssetID: UUID
        var sourceRange: AeroMediaTimeRange
    }

    struct TimedOverlay: Codable, Equatable, Identifiable, Sendable {
        enum Kind: String, Codable, Sendable { case callout, text, shape, image }
        let id: UUID
        var kind: Kind
        var timeRange: AeroMediaTimeRange
        var payload: String
    }

    struct Canvas: Codable, Equatable, Sendable {
        var crop: AeroNormalizedRect?
        var pixelSize: AeroPixelSize
    }

    struct Audio: Codable, Equatable, Sendable {
        var isMuted: Bool
        var gain: Float
        var fadeIn: AeroMediaTime = .zero
        var fadeOut: AeroMediaTime = .zero

        private enum CodingKeys: String, CodingKey { case isMuted, gain, fadeIn, fadeOut }
        init(isMuted: Bool, gain: Float, fadeIn: AeroMediaTime = .zero, fadeOut: AeroMediaTime = .zero) {
            self.isMuted = isMuted
            self.gain = gain
            self.fadeIn = fadeIn
            self.fadeOut = fadeOut
        }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            isMuted = try values.decode(Bool.self, forKey: .isMuted)
            gain = try values.decode(Float.self, forKey: .gain)
            fadeIn = try values.decodeIfPresent(AeroMediaTime.self, forKey: .fadeIn) ?? .zero
            fadeOut = try values.decodeIfPresent(AeroMediaTime.self, forKey: .fadeOut) ?? .zero
        }
    }

    struct ExportPreset: Codable, Equatable, Identifiable, Sendable {
        enum Codec: String, Codable, Sendable { case h264, hevc }
        let id: UUID
        var name: String
        var codec: Codec
        var pixelSize: AeroPixelSize
        var frameRate: AeroMediaTime
        var targetBitRate: Int
    }

    var slices: [Slice]
    var timedOverlays: [TimedOverlay]
    var canvas: Canvas?
    var audio: Audio
    var exportPresets: [ExportPreset]
}

nonisolated struct AeroGeneratedCachePolicy: Codable, Equatable, Sendable {
    enum Eviction: String, Codable, Sendable { case leastRecentlyUsed }
    var maximumBytes: Int64
    var eviction: Eviction
    var isPurgeable: Bool

    static let `default` = AeroGeneratedCachePolicy(
        maximumBytes: 512 * 1_024 * 1_024,
        eviction: .leastRecentlyUsed,
        isPurgeable: true
    )
}

nonisolated struct AeroRecoveryMetadata: Codable, Equatable, Sendable {
    var generation: Int
    var recoverableManifestPath: String?

    static let initial = AeroRecoveryMetadata(generation: 0, recoverableManifestPath: nil)
}

nonisolated enum AeroGIFEditStateError: Error, Equatable {
    case noFrames
    case duplicateFrameID(UUID)
    case invalidFrameDuration(UUID)
    case invalidFramePath(String)
    case durationOverflow
    case invalidLoopCount
    case invalidOutputDimensions
    case invalidPaletteSize
    case invalidQuality
    case invalidSpoolLimits
    case invalidCrop
    case invalidAnnotation(UUID)
}

/// Lossless GIF-editor state. Frame images are purgeable derivatives; the
/// immutable source GIF remains the ownership-critical asset.
nonisolated struct AeroGIFEditState: Codable, Equatable, Sendable {
    struct Frame: Codable, Equatable, Identifiable, Sendable {
        let id: UUID
        var generatedRelativePath: String
        var durationMicroseconds: Int64
        /// Index in the immutable source GIF, when this derivative originated
        /// there. Used to regenerate trimmed/duplicated edits after cache purge.
        var sourceFrameIndex: Int? = nil
    }

    enum Loop: Codable, Equatable, Sendable {
        case once
        case count(Int)
        case forever

        private enum CodingKeys: String, CodingKey { case kind, count }
        private enum Kind: String, Codable { case once, count, forever }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            switch try values.decode(Kind.self, forKey: .kind) {
            case .once: self = .once
            case .forever: self = .forever
            case .count:
                let count = try values.decode(Int.self, forKey: .count)
                guard count > 0 else { throw AeroGIFEditStateError.invalidLoopCount }
                self = .count(count)
            }
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .once: try values.encode(Kind.once, forKey: .kind)
            case .forever: try values.encode(Kind.forever, forKey: .kind)
            case .count(let count):
                guard count > 0 else { throw AeroGIFEditStateError.invalidLoopCount }
                try values.encode(Kind.count, forKey: .kind)
                try values.encode(count, forKey: .count)
            }
        }
    }

    enum Dither: String, Codable, Sendable { case none, ordered }
    struct Annotation: Codable, Equatable, Identifiable, Sendable {
        let id: UUID
        var startMicroseconds: Int64
        var durationMicroseconds: Int64
        var text: String
    }

    var frames: [Frame]
    var loop: Loop
    var pingPong: Bool
    var outputWidth: Int?
    var outputHeight: Int?
    var paletteSize: Int
    var dither: Dither
    var preservesTransparency: Bool
    var quality: Double
    var spoolMaximumFrameCount: Int
    var spoolMaximumBytes: Int64
    var crop: AeroNormalizedRect?
    var annotations: [Annotation]

    init(
        frames: [Frame], loop: Loop = .forever, pingPong: Bool = false,
        outputWidth: Int? = nil, outputHeight: Int? = nil, paletteSize: Int = 256,
        dither: Dither = .none, preservesTransparency: Bool = true,
        quality: Double = 1, spoolMaximumFrameCount: Int = 18_000,
        spoolMaximumBytes: Int64 = 4 * 1_024 * 1_024 * 1_024,
        crop: AeroNormalizedRect? = nil, annotations: [Annotation] = []
    ) throws {
        self.frames = frames
        self.loop = loop
        self.pingPong = pingPong
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.paletteSize = paletteSize
        self.dither = dither
        self.preservesTransparency = preservesTransparency
        self.quality = quality
        self.spoolMaximumFrameCount = spoolMaximumFrameCount
        self.spoolMaximumBytes = spoolMaximumBytes
        self.crop = crop
        self.annotations = annotations
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case frames, loop, pingPong, outputWidth, outputHeight, paletteSize, dither
        case preservesTransparency, quality, spoolMaximumFrameCount, spoolMaximumBytes, crop, annotations
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            frames: values.decode([Frame].self, forKey: .frames),
            loop: values.decode(Loop.self, forKey: .loop),
            pingPong: values.decode(Bool.self, forKey: .pingPong),
            outputWidth: values.decodeIfPresent(Int.self, forKey: .outputWidth),
            outputHeight: values.decodeIfPresent(Int.self, forKey: .outputHeight),
            paletteSize: values.decode(Int.self, forKey: .paletteSize),
            dither: values.decode(Dither.self, forKey: .dither),
            preservesTransparency: values.decode(Bool.self, forKey: .preservesTransparency),
            quality: values.decode(Double.self, forKey: .quality),
            spoolMaximumFrameCount: values.decode(Int.self, forKey: .spoolMaximumFrameCount),
            spoolMaximumBytes: values.decode(Int64.self, forKey: .spoolMaximumBytes),
            crop: values.decodeIfPresent(AeroNormalizedRect.self, forKey: .crop),
            annotations: values.decodeIfPresent([Annotation].self, forKey: .annotations) ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(frames, forKey: .frames)
        try values.encode(loop, forKey: .loop)
        try values.encode(pingPong, forKey: .pingPong)
        try values.encodeIfPresent(outputWidth, forKey: .outputWidth)
        try values.encodeIfPresent(outputHeight, forKey: .outputHeight)
        try values.encode(paletteSize, forKey: .paletteSize)
        try values.encode(dither, forKey: .dither)
        try values.encode(preservesTransparency, forKey: .preservesTransparency)
        try values.encode(quality, forKey: .quality)
        try values.encode(spoolMaximumFrameCount, forKey: .spoolMaximumFrameCount)
        try values.encode(spoolMaximumBytes, forKey: .spoolMaximumBytes)
        try values.encodeIfPresent(crop, forKey: .crop)
        try values.encode(annotations, forKey: .annotations)
    }

    func validate() throws {
        guard !frames.isEmpty else { throw AeroGIFEditStateError.noFrames }
        var ids = Set<UUID>()
        var total: Int64 = 0
        for frame in frames {
            guard ids.insert(frame.id).inserted else { throw AeroGIFEditStateError.duplicateFrameID(frame.id) }
            guard frame.durationMicroseconds > 0 else { throw AeroGIFEditStateError.invalidFrameDuration(frame.id) }
            guard frame.sourceFrameIndex.map({ $0 >= 0 }) ?? true else {
                throw AeroGIFEditStateError.invalidFramePath(frame.generatedRelativePath)
            }
            guard frame.generatedRelativePath.hasPrefix("generated/gif-frames/"),
                  !frame.generatedRelativePath.contains(".."), !frame.generatedRelativePath.contains("\\")
            else { throw AeroGIFEditStateError.invalidFramePath(frame.generatedRelativePath) }
            guard total <= Int64.max - frame.durationMicroseconds else { throw AeroGIFEditStateError.durationOverflow }
            total += frame.durationMicroseconds
        }
        if case .count(let count) = loop, count <= 0 { throw AeroGIFEditStateError.invalidLoopCount }
        if let outputWidth, outputWidth <= 0 { throw AeroGIFEditStateError.invalidOutputDimensions }
        if let outputHeight, outputHeight <= 0 { throw AeroGIFEditStateError.invalidOutputDimensions }
        guard (2...256).contains(paletteSize) else { throw AeroGIFEditStateError.invalidPaletteSize }
        guard quality.isFinite, (0...1).contains(quality) else { throw AeroGIFEditStateError.invalidQuality }
        guard spoolMaximumFrameCount > 0, spoolMaximumBytes > 0, frames.count <= spoolMaximumFrameCount else {
            throw AeroGIFEditStateError.invalidSpoolLimits
        }
        if let crop {
            guard [crop.x, crop.y, crop.width, crop.height].allSatisfy(\.isFinite), crop.x >= 0, crop.y >= 0,
                  crop.width > 0, crop.height > 0, crop.x + crop.width <= 1, crop.y + crop.height <= 1 else {
                throw AeroGIFEditStateError.invalidCrop
            }
        }
        for annotation in annotations {
            guard annotation.startMicroseconds >= 0, annotation.durationMicroseconds > 0, !annotation.text.isEmpty,
                  annotation.startMicroseconds <= total - annotation.durationMicroseconds else {
                throw AeroGIFEditStateError.invalidAnnotation(annotation.id)
            }
        }
    }
}

nonisolated struct AeroProjectManifest: Codable, Equatable, Identifiable, Sendable {
    var schemaVersion: Int
    let id: UUID
    var createdAt: Date
    var modifiedAt: Date
    var compatibility: AeroProjectCompatibility
    var assets: [AeroProjectAsset]
    var primarySourceAssetID: UUID?
    var canvas: AeroProjectCanvas
    var overlays: [AeroOverlay]
    var timeline: [AeroTimelineItem]
    var eventTracks: [AeroEventTrack]
    var exportPresets: [AeroExportPreset]
    var lastSuccessfulExport: AeroLastExport?
    var generatedCachePolicy: AeroGeneratedCachePolicy
    var recovery: AeroRecoveryMetadata
    /// Exact pixel-space editor crop. `nil` means no crop; `canvas.crop`
    /// remains populated for project-wide consumers.
    var editorCropRectPixels: AeroRect?
    /// Exact screenshot-editor beautify state. Optional for old manifests.
    var editorBeautify: AeroEditorBeautifySettings?
    /// Non-destructive screenshot straighten angle in degrees. Optional for old manifests.
    var editorStraightenDegrees: Double?
    /// Exact editable media state. Optional for all pre-media and screenshot
    /// projects, preserving backward decoding compatibility.
    var mediaComposition: AeroMediaCompositionState?
    /// Exact editable GIF state. Optional for legacy screenshot/media projects.
    var gifEditState: AeroGIFEditState?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        modifiedAt: Date? = nil,
        compatibility: AeroProjectCompatibility = AeroProjectCompatibility(),
        assets: [AeroProjectAsset] = [],
        primarySourceAssetID: UUID? = nil,
        canvas: AeroProjectCanvas = .source,
        overlays: [AeroOverlay] = [],
        timeline: [AeroTimelineItem] = [],
        eventTracks: [AeroEventTrack] = [],
        exportPresets: [AeroExportPreset] = [],
        lastSuccessfulExport: AeroLastExport? = nil,
        generatedCachePolicy: AeroGeneratedCachePolicy = .default,
        recovery: AeroRecoveryMetadata = .initial,
        editorCropRectPixels: AeroRect? = nil,
        editorBeautify: AeroEditorBeautifySettings? = nil,
        editorStraightenDegrees: Double? = nil,
        mediaComposition: AeroMediaCompositionState? = nil,
        gifEditState: AeroGIFEditState? = nil
    ) {
        schemaVersion = AeroProjectSchema.currentVersion
        self.id = id
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.compatibility = compatibility
        self.assets = assets
        self.primarySourceAssetID = primarySourceAssetID
        self.canvas = canvas
        self.overlays = overlays
        self.timeline = timeline
        self.eventTracks = eventTracks
        self.exportPresets = exportPresets
        self.lastSuccessfulExport = lastSuccessfulExport
        self.generatedCachePolicy = generatedCachePolicy
        self.recovery = recovery
        self.editorCropRectPixels = editorCropRectPixels
        self.editorBeautify = editorBeautify
        self.editorStraightenDegrees = editorStraightenDegrees
        self.mediaComposition = mediaComposition
        self.gifEditState = gifEditState
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, projectID, createdAt, modifiedAt, compatibility, assets
        case primarySourceAssetID, canvas, overlays, timeline, eventTracks, exportPresets
        case lastSuccessfulExport, generatedCachePolicy, recovery
        case editorCropRectPixels, editorBeautify, editorStraightenDegrees, mediaComposition, gifEditState
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        id = try values.decodeIfPresent(UUID.self, forKey: .id)
            ?? values.decode(UUID.self, forKey: .projectID)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        modifiedAt = try values.decode(Date.self, forKey: .modifiedAt)
        compatibility = try values.decodeIfPresent(AeroProjectCompatibility.self, forKey: .compatibility)
            ?? AeroProjectCompatibility()
        assets = try values.decodeIfPresent([AeroProjectAsset].self, forKey: .assets) ?? []
        primarySourceAssetID = try values.decodeIfPresent(UUID.self, forKey: .primarySourceAssetID)
        canvas = try values.decodeIfPresent(AeroProjectCanvas.self, forKey: .canvas) ?? .source
        overlays = try values.decodeIfPresent([AeroOverlay].self, forKey: .overlays) ?? []
        timeline = try values.decodeIfPresent([AeroTimelineItem].self, forKey: .timeline) ?? []
        eventTracks = try values.decodeIfPresent([AeroEventTrack].self, forKey: .eventTracks) ?? []
        exportPresets = try values.decodeIfPresent([AeroExportPreset].self, forKey: .exportPresets) ?? []
        lastSuccessfulExport = try values.decodeIfPresent(AeroLastExport.self, forKey: .lastSuccessfulExport)
        generatedCachePolicy = try values.decodeIfPresent(AeroGeneratedCachePolicy.self, forKey: .generatedCachePolicy) ?? .default
        recovery = try values.decodeIfPresent(AeroRecoveryMetadata.self, forKey: .recovery) ?? .initial
        editorCropRectPixels = try values.decodeIfPresent(AeroRect.self, forKey: .editorCropRectPixels)
        editorBeautify = try values.decodeIfPresent(AeroEditorBeautifySettings.self, forKey: .editorBeautify)
        editorStraightenDegrees = try values.decodeIfPresent(Double.self, forKey: .editorStraightenDegrees)
        mediaComposition = try values.decodeIfPresent(AeroMediaCompositionState.self, forKey: .mediaComposition)
        gifEditState = try values.decodeIfPresent(AeroGIFEditState.self, forKey: .gifEditState)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(id, forKey: .id)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(modifiedAt, forKey: .modifiedAt)
        try values.encode(compatibility, forKey: .compatibility)
        try values.encode(assets, forKey: .assets)
        try values.encodeIfPresent(primarySourceAssetID, forKey: .primarySourceAssetID)
        try values.encode(canvas, forKey: .canvas)
        try values.encode(overlays, forKey: .overlays)
        try values.encode(timeline, forKey: .timeline)
        try values.encode(eventTracks, forKey: .eventTracks)
        try values.encode(exportPresets, forKey: .exportPresets)
        try values.encodeIfPresent(lastSuccessfulExport, forKey: .lastSuccessfulExport)
        try values.encode(generatedCachePolicy, forKey: .generatedCachePolicy)
        try values.encode(recovery, forKey: .recovery)
        try values.encodeIfPresent(editorCropRectPixels, forKey: .editorCropRectPixels)
        try values.encodeIfPresent(editorBeautify, forKey: .editorBeautify)
        try values.encodeIfPresent(editorStraightenDegrees, forKey: .editorStraightenDegrees)
        try values.encodeIfPresent(mediaComposition, forKey: .mediaComposition)
        try values.encodeIfPresent(gifEditState, forKey: .gifEditState)
    }
}
