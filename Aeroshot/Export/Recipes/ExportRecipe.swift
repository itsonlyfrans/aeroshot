import Foundation

nonisolated enum ExportRecipeID: String, Codable, CaseIterable, Equatable, Sendable {
    case documentation
    case socialSquare
    case socialLandscape
    case retinaAsset
    case downscaledAsset
}

nonisolated enum ExportResize: Codable, Equatable, Sendable {
    case original
    case points
    case scale(Double)
    case exact(width: Int, height: Int)
}

nonisolated enum ExportRecipeFormat: Codable, Equatable, Sendable {
    case png
    case jpeg(quality: Double)
    case heic(quality: Double)
    case mp4(codec: ExportVideoCodec, frameRate: Int)
    case gif(paletteSize: Int)
}

nonisolated enum ExportVideoCodec: String, Codable, Equatable, Sendable {
    case h264
    case hevc
}

nonisolated enum PrivacyReviewRequirement: String, Codable, Equatable, Sendable {
    case required
    case optional
}

nonisolated struct ExportRecipe: Codable, Equatable, Sendable {
    var id: ExportRecipeID
    var resize: ExportResize
    var format: ExportRecipeFormat
    var fileNameSuffix: String
    var privacyReview: PrivacyReviewRequirement

    static let documentation = Self(
        id: .documentation, resize: .points, format: .png,
        fileNameSuffix: "", privacyReview: .required
    )
    static let socialSquare = Self(
        id: .socialSquare, resize: .exact(width: 1_080, height: 1_080), format: .jpeg(quality: 0.9),
        fileNameSuffix: "-square", privacyReview: .required
    )
    static let socialLandscape = Self(
        id: .socialLandscape, resize: .exact(width: 1_600, height: 900), format: .jpeg(quality: 0.9),
        fileNameSuffix: "-landscape", privacyReview: .required
    )
    static let retinaAsset = Self(
        id: .retinaAsset, resize: .original, format: .png,
        fileNameSuffix: "@2x", privacyReview: .required
    )
    static let downscaledAsset = Self(
        id: .downscaledAsset, resize: .scale(0.5), format: .png,
        fileNameSuffix: "", privacyReview: .required
    )
    static let builtIns = [documentation, socialSquare, socialLandscape, retinaAsset, downscaledAsset]
}

nonisolated enum PrivacyReviewFailure: String, Codable, Equatable, Sendable {
    case scannerUnavailable
    case scanFailed
    case findingsUnresolved
}

nonisolated enum PrivacyReview: Codable, Equatable, Sendable {
    case notPerformed
    case passed(reviewID: UUID)
    case failed(reason: PrivacyReviewFailure)
}

/// Named boundary used by sharing/export controllers before any destination request is created.
typealias ShareSafePrecondition = PrivacyReview

nonisolated struct ExportRecipeSource: Equatable, Sendable {
    var pixelSize: AeroPixelSize
    var scale: Double

    init(pixelSize: AeroPixelSize, scale: Double) {
        self.pixelSize = pixelSize
        self.scale = scale
    }
}

nonisolated struct StillExportInput: Equatable, Sendable {
    var format: ImageFormat
    var jpegQuality: Double
    var scale: Double
    var downscaleToPoints: Bool
    var targetPixelSize: AeroPixelSize
}

nonisolated enum CompiledExportInput: Equatable, Sendable {
    case still(StillExportInput)
    case media(MediaExportPreset)
    case gif(GIFExportSettings)
}

nonisolated struct CompiledExportRecipe: Equatable, Sendable {
    var recipeID: ExportRecipeID
    var pixelSize: AeroPixelSize
    var fileName: String
    var exportInput: CompiledExportInput
    fileprivate var reviewID: UUID?

    func auditResult(destination: ExportDestinationKind, byteCount: Int64) -> ExportAuditResult {
        ExportAuditResult(
            recipeID: recipeID, reviewID: reviewID, destinationKind: destination,
            byteCount: max(byteCount, 0)
        )
    }
}

nonisolated struct ExportAuditResult: Equatable, Sendable {
    let recipeID: ExportRecipeID
    let reviewID: UUID?
    let destinationKind: ExportDestinationKind
    let byteCount: Int64
}

nonisolated enum ExportRecipeError: Error, Equatable, Sendable {
    case privacyReviewRequired
    case invalidScale
    case invalidDimensions
    case invalidQuality
    case invalidFrameRate
    case invalidPaletteSize
    case emptyFileName
}

nonisolated enum ExportRecipeCompiler {
    static func compile(
        recipe: ExportRecipe,
        source: ExportRecipeSource,
        baseName: String,
        privacyReview: PrivacyReview
    ) throws -> CompiledExportRecipe {
        let reviewID: UUID?
        switch privacyReview {
        case .passed(let id): reviewID = id
        case .notPerformed, .failed:
            guard recipe.privacyReview == .optional else { throw ExportRecipeError.privacyReviewRequired }
            reviewID = nil
        }
        guard source.scale.isFinite, source.scale > 0 else { throw ExportRecipeError.invalidScale }
        let requestedSize = try outputSize(recipe.resize, source: source)
        let size: AeroPixelSize
        if case .mp4 = recipe.format { size = try even(requestedSize) }
        else { size = requestedSize }
        let name = try fileName(baseName: baseName, suffix: recipe.fileNameSuffix, format: recipe.format)
        let input = try exporterInput(recipe.format, size: size, source: source, resize: recipe.resize)
        return CompiledExportRecipe(
            recipeID: recipe.id, pixelSize: size, fileName: name,
            exportInput: input, reviewID: reviewID
        )
    }

    private static func outputSize(_ resize: ExportResize, source: ExportRecipeSource) throws -> AeroPixelSize {
        let width: Int
        let height: Int
        switch resize {
        case .original:
            width = source.pixelSize.width
            height = source.pixelSize.height
        case .points:
            width = Int((Double(source.pixelSize.width) / source.scale).rounded())
            height = Int((Double(source.pixelSize.height) / source.scale).rounded())
        case .scale(let factor):
            guard factor.isFinite, factor > 0 else { throw ExportRecipeError.invalidScale }
            width = Int((Double(source.pixelSize.width) * factor).rounded())
            height = Int((Double(source.pixelSize.height) * factor).rounded())
        case .exact(let requestedWidth, let requestedHeight):
            width = requestedWidth
            height = requestedHeight
        }
        guard width > 0, height > 0, width <= 8_192, height <= 8_192 else {
            throw ExportRecipeError.invalidDimensions
        }
        return try AeroPixelSize(width: width, height: height)
    }

    private static func exporterInput(
        _ format: ExportRecipeFormat,
        size: AeroPixelSize,
        source: ExportRecipeSource,
        resize: ExportResize
    ) throws -> CompiledExportInput {
        switch format {
        case .png:
            return .still(.init(
                format: .png, jpegQuality: 1, scale: source.scale,
                downscaleToPoints: resize == .points, targetPixelSize: size
            ))
        case .jpeg(let quality):
            guard (0...1).contains(quality) else { throw ExportRecipeError.invalidQuality }
            return .still(.init(
                format: .jpeg, jpegQuality: quality, scale: source.scale,
                downscaleToPoints: resize == .points, targetPixelSize: size
            ))
        case .heic(let quality):
            guard (0...1).contains(quality) else { throw ExportRecipeError.invalidQuality }
            return .still(.init(
                format: .heic, jpegQuality: quality, scale: source.scale,
                downscaleToPoints: resize == .points, targetPixelSize: size
            ))
        case .mp4(let codec, let frameRate):
            guard (1...120).contains(frameRate) else { throw ExportRecipeError.invalidFrameRate }
            // MediaExportPreset remains the single source of codec/rate/bitrate policy.
            let rate = try AeroMediaTime(value: Int64(frameRate), timescale: 1)
            let preset: MediaExportPreset = codec == .h264
                ? .h264(size: size, frameRate: rate)
                : .hevc(size: size, frameRate: rate)
            try preset.validate()
            return .media(preset)
        case .gif(let paletteSize):
            guard (2...256).contains(paletteSize) else { throw ExportRecipeError.invalidPaletteSize }
            // GIFWriter consumes this existing settings type; frame pacing remains in GIFDocument frames.
            let settings = GIFExportSettings(
                outputWidth: size.width, outputHeight: size.height, paletteSize: paletteSize
            )
            return .gif(try settings.validated())
        }
    }

    private static func even(_ size: AeroPixelSize) throws -> AeroPixelSize {
        let width = size.width - size.width % 2
        let height = size.height - size.height % 2
        guard width >= 16, height >= 16 else { throw ExportRecipeError.invalidDimensions }
        return try AeroPixelSize(width: width, height: height)
    }

    private static func fileName(baseName: String, suffix: String, format: ExportRecipeFormat) throws -> String {
        let source = baseName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let components = source.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        let stem = components.filter { !$0.isEmpty }.joined(separator: "-")
        guard !stem.isEmpty else { throw ExportRecipeError.emptyFileName }
        let ext: String
        switch format {
        case .png: ext = "png"
        case .jpeg: ext = "jpg"
        case .heic: ext = "heic"
        case .mp4: ext = "mp4"
        case .gif: ext = "gif"
        }
        return stem + suffix + "." + ext
    }
}
