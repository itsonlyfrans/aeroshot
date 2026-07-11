import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum EditorProjectBridgeError: Error, Equatable {
    case missingPrimarySource
    case wrongSourceMediaType(UUID, AeroMediaMetadata.MediaType)
    case sourceIsNotImmutable(UUID)
    case sourceIsNotPNG(UUID)
    case corruptSourceImage(UUID)
    case sourceDimensionsMismatch(UUID)
    case sourceDoesNotMatchDocument(UUID)
    case sourceImageEncodingFailed
    case unsupportedAnnotationColor(UUID)
    case invalidOverlayColor(UUID)
    case unsupportedOverlay(UUID)
    case invalidAnnotationAppearance(UUID)
    case invalidBeautifySettings
}

/// Lossless adapter between the current screenshot editor and the shared
/// project package kernel. This type intentionally has no media/timeline UI
/// responsibilities.
@MainActor
enum EditorProjectBridge {
    @discardableResult
    static func save(
        _ document: EditorDocument,
        to packageURL: URL
    ) throws -> AeroProjectManifest {
        let store = AeroProjectPackageStore(packageURL: packageURL)
        if FileManager.default.fileExists(atPath: packageURL.path) {
            var manifest = try store.load()
            let source = try loadSource(from: manifest, store: store)
            guard let sourcePixels = canonicalPixels(of: source.image),
                  let documentPixels = canonicalPixels(of: document.baseImage),
                  sourcePixels == documentPixels
            else {
                throw EditorProjectBridgeError.sourceDoesNotMatchDocument(source.asset.id)
            }
            try applyEditorState(from: document, to: &manifest)
            return try store.save(manifest)
        }

        return try saveNewPackage(document, to: packageURL)
    }

    static func open(from packageURL: URL) throws -> EditorDocument {
        try openWithManifest(from: packageURL).document
    }

    /// Applies the document's current editor state to an already-loaded
    /// manifest without touching disk. Autosave hands the result to
    /// `AeroProjectAutosaveCoordinator`, avoiding a per-edit reload and
    /// pixel-level source re-validation of the immutable original.
    static func manifest(
        byApplying document: EditorDocument,
        to manifest: AeroProjectManifest
    ) throws -> AeroProjectManifest {
        var updated = manifest
        try applyEditorState(from: document, to: &updated)
        return updated
    }

    static func openWithManifest(
        from packageURL: URL
    ) throws -> (document: EditorDocument, manifest: AeroProjectManifest) {
        let store = AeroProjectPackageStore(packageURL: packageURL)
        let manifest = try store.load()
        let source = try loadSource(from: manifest, store: store)
        let document = EditorDocument(image: source.image)
        document.annotations = try manifest.overlays.map(annotation(from:))
        document.cropRect = manifest.editorCropRectPixels.map(cgRect(from:))
        let straighten = manifest.editorStraightenDegrees ?? 0
        guard straighten.isFinite, abs(straighten) <= 45 else { throw EditorProjectBridgeError.invalidBeautifySettings }
        document.straightenDegrees = straighten
        if let settings = manifest.editorBeautify {
            guard let gradient = BeautifySettings.GradientPreset(rawValue: settings.gradient),
                  let aspect = BeautifySettings.AspectPreset(rawValue: settings.aspectPreset)
            else { throw EditorProjectBridgeError.invalidBeautifySettings }
            document.beautify = BeautifySettings(
                enabled: settings.enabled,
                padding: settings.padding,
                cornerRadius: settings.cornerRadius,
                shadowRadius: settings.shadowRadius,
                shadowOpacity: settings.shadowOpacity,
                gradient: gradient,
                aspectPreset: aspect
            )
        }
        return (document, manifest)
    }

    private static func saveNewPackage(
        _ document: EditorDocument,
        to packageURL: URL
    ) throws -> AeroProjectManifest {
        guard let pngData = NSBitmapImageRep(cgImage: document.baseImage)
            .representation(using: .png, properties: [:])
        else { throw EditorProjectBridgeError.sourceImageEncodingFailed }

        let fileManager = FileManager.default
        let parentURL = packageURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        let temporaryURL = parentURL.appending(
            path: ".\(packageURL.lastPathComponent)-\(UUID().uuidString).tmp"
        )
        let temporaryStore = AeroProjectPackageStore(packageURL: temporaryURL)
        do {
            let asset = try temporaryStore.storeOriginal(
                pngData,
                fileExtension: "png",
                metadata: AeroMediaMetadata(
                    mediaType: .image,
                    pixelSize: try AeroPixelSize(
                        width: document.baseImage.width,
                        height: document.baseImage.height
                    ),
                    duration: nil,
                    nominalFrameRate: nil,
                    colorSpaceName: document.baseImage.colorSpace?.name as String?,
                    hasAudio: false
                )
            )
            var manifest = AeroProjectManifest(
                assets: [asset],
                primarySourceAssetID: asset.id
            )
            try applyEditorState(from: document, to: &manifest)
            let saved = try temporaryStore.save(manifest)
            try fileManager.moveItem(at: temporaryURL, to: packageURL)
            return saved
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    private static func applyEditorState(
        from document: EditorDocument,
        to manifest: inout AeroProjectManifest
    ) throws {
        guard document.straightenDegrees.isFinite, abs(document.straightenDegrees) <= 45 else {
            throw EditorProjectBridgeError.invalidBeautifySettings
        }
        let size = document.pixelSize
        manifest.canvas.crop = document.cropRect.map { normalizedRect($0, in: size) } ?? .full
        manifest.editorCropRectPixels = document.cropRect.map(aeroRect(from:))
        manifest.editorStraightenDegrees = document.straightenDegrees == 0 ? nil : document.straightenDegrees
        manifest.editorBeautify = AeroEditorBeautifySettings(
            enabled: document.beautify.enabled,
            padding: document.beautify.padding,
            cornerRadius: document.beautify.cornerRadius,
            shadowRadius: document.beautify.shadowRadius,
            shadowOpacity: document.beautify.shadowOpacity,
            gradient: document.beautify.gradient.rawValue,
            aspectPreset: document.beautify.aspectPreset.rawValue
        )
        manifest.overlays = try document.annotations.enumerated().map { index, annotation in
            try overlay(from: annotation, zIndex: index, imageSize: size)
        }
    }

    static func overlay(
        from annotation: Annotation,
        zIndex: Int,
        imageSize: CGSize
    ) throws -> AeroOverlay {
        guard let color = annotation.color.usingColorSpace(.sRGB) else {
            throw EditorProjectBridgeError.unsupportedAnnotationColor(annotation.id)
        }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let annotationRGBA = [Double(red), Double(green), Double(blue), Double(alpha)]
        let appearance = annotation.appearance
        let shadowRGBA = try rgba(from: appearance.stroke.shadow.color, annotationID: annotation.id)
        let backgroundRGBA = try appearance.typography.backgroundColor.map {
            try rgba(from: $0, annotationID: annotation.id)
        }
        let persistedAppearance = AeroEditorAnnotationAppearance(
            strokeOpacity: appearance.stroke.opacity,
            strokeDash: appearance.stroke.dash.map(Double.init),
            strokeDashPhase: appearance.stroke.dashPhase,
            strokeLineCap: appearance.stroke.lineCap.rawValue,
            strokeShadow: .init(
                colorRGBA: shadowRGBA,
                opacity: appearance.stroke.shadow.opacity,
                radius: appearance.stroke.shadow.radius,
                offsetX: appearance.stroke.shadow.offset.width,
                offsetY: appearance.stroke.shadow.offset.height
            ),
            fillOpacity: appearance.fill.opacity,
            cornerRadius: appearance.cornerRadius,
            arrowStartStyle: appearance.arrow.startStyle.rawValue,
            arrowEndStyle: appearance.arrow.endStyle.rawValue,
            arrowHeadLength: appearance.arrow.headLength.map(Double.init),
            arrowHeadWidth: appearance.arrow.headWidth.map(Double.init),
            arrowInset: appearance.arrow.inset.map(Double.init),
            arrowCurve: appearance.arrow.curve,
            fontName: appearance.typography.fontName,
            fontWeight: appearance.typography.weight.rawValue,
            textAlignment: appearance.typography.alignment.rawValue,
            textBackgroundRGBA: backgroundRGBA,
            textBackgroundOpacity: appearance.typography.backgroundOpacity,
            textPadding: .init(
                top: appearance.typography.padding.top,
                leading: appearance.typography.padding.leading,
                bottom: appearance.typography.padding.bottom,
                trailing: appearance.typography.padding.trailing
            ),
            lineHeight: appearance.typography.lineHeight
        )
        guard isValid(persistedAppearance) else {
            throw EditorProjectBridgeError.invalidAnnotationAppearance(annotation.id)
        }
        return AeroOverlay(
            id: annotation.id,
            kind: projectKind(from: annotation.kind),
            geometry: AeroOverlay.Geometry(
                bounds: normalizedPointBounds(annotation.points, in: imageSize),
                points: annotation.points.map { AeroPoint(x: $0.x, y: $0.y) }
            ),
            appearance: AeroOverlay.Appearance(
                strokeRGBA: annotationRGBA,
                fillRGBA: annotation.filled ? annotationRGBA : nil,
                strokeWidth: annotation.lineWidth,
                opacity: 1
            ),
            transform: AeroOverlay.Transform(rotationRadians: 0, scaleX: 1, scaleY: 1),
            zIndex: zIndex,
            timeRange: nil,
            editor: AeroEditorOverlayData(
                kind: editorKind(from: annotation.kind),
                text: annotation.text,
                fontSize: annotation.fontSize,
                stepNumber: annotation.stepNumber,
                filled: annotation.filled,
                appearance: persistedAppearance
            )
        )
    }

    static func annotation(from overlay: AeroOverlay) throws -> Annotation {
        guard overlay.timeRange == nil,
              overlay.transform == AeroOverlay.Transform(rotationRadians: 0, scaleX: 1, scaleY: 1),
              let editor = overlay.editor
        else { throw EditorProjectBridgeError.unsupportedOverlay(overlay.id) }
        guard overlay.appearance.strokeRGBA.count == 4 else {
            throw EditorProjectBridgeError.invalidOverlayColor(overlay.id)
        }
        let rgba = overlay.appearance.strokeRGBA
        guard rgba.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              overlay.appearance.opacity.isFinite, (0...1).contains(overlay.appearance.opacity),
              overlay.appearance.strokeWidth.isFinite, overlay.appearance.strokeWidth > 0,
              editor.fontSize.isFinite, editor.fontSize > 0,
              (overlay.kind != .step || editor.stepNumber > 0) else {
            throw EditorProjectBridgeError.invalidOverlayColor(overlay.id)
        }
        let color = NSColor(
            srgbRed: rgba[0],
            green: rgba[1],
            blue: rgba[2],
            alpha: rgba[3] * overlay.appearance.opacity
        )
        let appearance = try annotationAppearance(from: editor.appearance, annotationID: overlay.id)
        return Annotation(
            id: overlay.id,
            kind: annotationKind(from: editor.kind),
            points: overlay.geometry.points.map { CGPoint(x: $0.x, y: $0.y) },
            color: color,
            lineWidth: overlay.appearance.strokeWidth,
            text: editor.text,
            fontSize: editor.fontSize,
            stepNumber: editor.stepNumber,
            filled: editor.filled,
            appearance: appearance
        )
    }

    private static func annotationAppearance(
        from value: AeroEditorAnnotationAppearance?,
        annotationID: UUID
    ) throws -> AnnotationAppearance {
        guard let value else { return AnnotationAppearance() }
        guard isValid(value),
              let lineCap = AnnotationLineCap(rawValue: value.strokeLineCap),
              let startStyle = AnnotationArrowheadStyle(rawValue: value.arrowStartStyle),
              let endStyle = AnnotationArrowheadStyle(rawValue: value.arrowEndStyle),
              let alignment = AnnotationTextAlignment(rawValue: value.textAlignment),
              let shadowColor = color(from: value.strokeShadow.colorRGBA)
        else { throw EditorProjectBridgeError.invalidAnnotationAppearance(annotationID) }
        // A nil text background is the default and must round-trip as nil;
        // only a present-but-malformed RGBA is invalid.
        let backgroundColor = try value.textBackgroundRGBA.map { rgba -> NSColor in
            guard let color = color(from: rgba) else {
                throw EditorProjectBridgeError.invalidAnnotationAppearance(annotationID)
            }
            return color
        }

        let stroke = AnnotationStrokeAppearance(
                opacity: CGFloat(value.strokeOpacity),
                dash: value.strokeDash.map { CGFloat($0) },
                dashPhase: CGFloat(value.strokeDashPhase),
                lineCap: lineCap,
                shadow: AnnotationShadow(
                    color: shadowColor,
                    opacity: CGFloat(value.strokeShadow.opacity),
                    radius: CGFloat(value.strokeShadow.radius),
                    offset: CGSize(width: CGFloat(value.strokeShadow.offsetX), height: CGFloat(value.strokeShadow.offsetY))
                )
            )
        let fill = AnnotationFillAppearance(opacity: CGFloat(value.fillOpacity))
        let arrow = AnnotationArrowAppearance(
                startStyle: startStyle,
                endStyle: endStyle,
                headLength: value.arrowHeadLength.map { CGFloat($0) },
                headWidth: value.arrowHeadWidth.map { CGFloat($0) },
                inset: value.arrowInset.map { CGFloat($0) },
                curve: CGFloat(value.arrowCurve)
            )
        let typography = AnnotationTypography(
                fontName: value.fontName,
                weight: NSFont.Weight(rawValue: CGFloat(value.fontWeight)),
                alignment: alignment,
                backgroundColor: backgroundColor,
                backgroundOpacity: CGFloat(value.textBackgroundOpacity),
                padding: AnnotationInsets(
                    top: CGFloat(value.textPadding.top),
                    leading: CGFloat(value.textPadding.leading),
                    bottom: CGFloat(value.textPadding.bottom),
                    trailing: CGFloat(value.textPadding.trailing)
                ),
                lineHeight: CGFloat(value.lineHeight)
            )
        return AnnotationAppearance(
            stroke: stroke,
            fill: fill,
            cornerRadius: CGFloat(value.cornerRadius),
            arrow: arrow,
            typography: typography
        )
    }

    private static func isValid(_ value: AeroEditorAnnotationAppearance) -> Bool {
        let unitValues = [value.strokeOpacity, value.strokeShadow.opacity,
                          value.fillOpacity, value.textBackgroundOpacity]
        let nonnegative = value.strokeDash + [value.strokeShadow.radius, value.cornerRadius]
            + [value.arrowHeadLength, value.arrowHeadWidth, value.arrowInset].compactMap { $0 }
            + [value.textPadding.top, value.textPadding.leading,
               value.textPadding.bottom, value.textPadding.trailing]
        let finite = [value.strokeDashPhase, value.strokeShadow.offsetX,
                      value.strokeShadow.offsetY, value.arrowCurve,
                      value.fontWeight, value.lineHeight]
        return unitValues.allSatisfy { $0.isFinite && (0...1).contains($0) }
            && nonnegative.allSatisfy { $0.isFinite && $0 >= 0 }
            && finite.allSatisfy(\.isFinite)
            && value.lineHeight > 0
            && color(from: value.strokeShadow.colorRGBA) != nil
            && (value.textBackgroundRGBA.map { color(from: $0) != nil } ?? true)
    }

    private static func rgba(from color: NSColor, annotationID: UUID) throws -> [Double] {
        guard let color = color.usingColorSpace(.sRGB) else {
            throw EditorProjectBridgeError.unsupportedAnnotationColor(annotationID)
        }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [Double(red), Double(green), Double(blue), Double(alpha)]
    }

    private static func color(from rgba: [Double]) -> NSColor? {
        guard rgba.count == 4, rgba.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            return nil
        }
        return NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
    }

    private static func loadSource(
        from manifest: AeroProjectManifest,
        store: AeroProjectPackageStore
    ) throws -> (asset: AeroProjectAsset, image: CGImage) {
        guard let sourceID = manifest.primarySourceAssetID else {
            throw EditorProjectBridgeError.missingPrimarySource
        }
        guard let asset = manifest.assets.first(where: { $0.id == sourceID }) else {
            throw AeroProjectPackageError.missingPrimarySource(sourceID)
        }
        guard asset.metadata.mediaType == .image else {
            throw EditorProjectBridgeError.wrongSourceMediaType(sourceID, asset.metadata.mediaType)
        }
        guard asset.isImmutableOriginal else {
            throw EditorProjectBridgeError.sourceIsNotImmutable(sourceID)
        }
        guard asset.relativePath.hasSuffix(".png") else {
            throw EditorProjectBridgeError.sourceIsNotPNG(sourceID)
        }
        let data = try Data(contentsOf: store.URL(forRelativePath: asset.relativePath))
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw EditorProjectBridgeError.corruptSourceImage(sourceID)
        }
        guard let sourceType = CGImageSourceGetType(source) as String? else {
            throw EditorProjectBridgeError.corruptSourceImage(sourceID)
        }
        guard sourceType == UTType.png.identifier else {
            throw EditorProjectBridgeError.sourceIsNotPNG(sourceID)
        }
        guard CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw EditorProjectBridgeError.corruptSourceImage(sourceID) }
        if let size = asset.metadata.pixelSize,
           size.width != image.width || size.height != image.height {
            throw EditorProjectBridgeError.sourceDimensionsMismatch(sourceID)
        }
        return (asset, image)
    }

    private static func canonicalPixels(of image: CGImage) -> Data? {
        let bytesPerRow = image.width * 4
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let bytes = context.data
        else { return nil }
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: bytes, count: bytesPerRow * image.height)
    }

    private static func normalizedPointBounds(
        _ points: [CGPoint],
        in size: CGSize
    ) -> AeroNormalizedRect {
        guard let first = points.first else { return .full }
        let bounds = points.dropFirst().reduce(
            CGRect(x: first.x, y: first.y, width: 0, height: 0)
        ) { partial, point in
            partial.union(CGRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        return normalizedRect(bounds, in: size)
    }

    private static func normalizedRect(_ rect: CGRect, in size: CGSize) -> AeroNormalizedRect {
        AeroNormalizedRect(
            x: rect.minX / size.width,
            y: rect.minY / size.height,
            width: rect.width / size.width,
            height: rect.height / size.height
        )
    }

    private static func aeroRect(from rect: CGRect) -> AeroRect {
        AeroRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }

    private static func cgRect(from rect: AeroRect) -> CGRect {
        CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    private static func projectKind(from kind: AnnotationKind) -> AeroOverlay.Kind {
        switch kind {
        case .arrow: .arrow
        case .text: .text
        case .step: .step
        case .redactBlur: .blur
        case .redactPixelate: .pixelate
        case .redactSolid: .solidRedaction
        default: .shape
        }
    }

    private static func editorKind(from kind: AnnotationKind) -> AeroEditorOverlayData.Kind {
        AeroEditorOverlayData.Kind(rawValue: kind.rawValue)!
    }

    private static func annotationKind(from kind: AeroEditorOverlayData.Kind) -> AnnotationKind {
        AnnotationKind(rawValue: kind.rawValue)!
    }
}
