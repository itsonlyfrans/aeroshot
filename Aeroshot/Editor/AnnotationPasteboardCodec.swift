import AppKit
import Foundation

enum AnnotationPasteboardCodecError: Error, Equatable {
    case invalidPayload
}

@MainActor
enum AnnotationPasteboardCodec {
    static let pasteboardType = NSPasteboard.PasteboardType("com.aeroshot.annotation.overlay.v1")
    static let maximumPayloadByteCount = 2 * 1_024 * 1_024
    static let maximumPointCount = 10_000
    static let maximumTextByteCount = 64 * 1_024
    static let maximumDashCount = 64

    private struct Payload: Codable {
        let version: Int
        let sourceWidth: Double
        let sourceHeight: Double
        let overlay: AeroOverlay
    }

    static func encode(_ annotation: Annotation, imageSize: CGSize) throws -> Data {
        guard imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0 else {
            throw AnnotationPasteboardCodecError.invalidPayload
        }
        let overlay = try EditorProjectBridge.overlay(from: annotation, zIndex: 0, imageSize: imageSize)
        let payload = Payload(version: 1, sourceWidth: imageSize.width,
                              sourceHeight: imageSize.height, overlay: overlay)
        _ = try validatedAnnotation(in: payload)
        return try JSONEncoder().encode(payload)
    }

    static func decode(_ data: Data) throws -> Annotation {
        guard data.count <= maximumPayloadByteCount else {
            throw AnnotationPasteboardCodecError.invalidPayload
        }
        return try validatedAnnotation(in: JSONDecoder().decode(Payload.self, from: data))
    }

    private static func validatedAnnotation(in payload: Payload) throws -> Annotation {
        guard payload.version == 1,
              payload.sourceWidth.isFinite, payload.sourceHeight.isFinite,
              payload.sourceWidth > 0, payload.sourceHeight > 0 else {
            throw AnnotationPasteboardCodecError.invalidPayload
        }
        let overlay = payload.overlay
        guard overlay.geometry.points.count <= maximumPointCount,
              (overlay.content?.utf8.count ?? 0) <= maximumTextByteCount,
              (overlay.editor?.text.utf8.count ?? 0) <= maximumTextByteCount,
              (overlay.editor?.appearance?.strokeDash.count ?? 0) <= maximumDashCount
        else { throw AnnotationPasteboardCodecError.invalidPayload }
        let annotation = try EditorProjectBridge.annotation(from: overlay)
        let bounds = overlay.geometry.bounds
        let normalized = [bounds.x, bounds.y, bounds.width, bounds.height]
        let fillIsValid = overlay.appearance.fillRGBA?.allSatisfy {
            $0.isFinite && (0...1).contains($0)
        } ?? true
        let derivedBounds = annotation.boundingRect
        let sourceRect = CGRect(x: 0, y: 0, width: payload.sourceWidth, height: payload.sourceHeight)
        guard normalized.allSatisfy(\.isFinite), bounds.width >= 0, bounds.height >= 0,
              overlay.appearance.strokeRGBA.count == 4,
              overlay.appearance.strokeRGBA.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              (overlay.appearance.fillRGBA?.count ?? 4) == 4, fillIsValid,
              overlay.appearance.strokeWidth.isFinite, overlay.appearance.strokeWidth > 0,
              overlay.appearance.opacity.isFinite, (0...1).contains(overlay.appearance.opacity),
              annotation.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              derivedBounds.origin.x.isFinite, derivedBounds.origin.y.isFinite,
              derivedBounds.width.isFinite, derivedBounds.height.isFinite,
              derivedBounds.intersects(sourceRect),
              derivedBounds.width <= payload.sourceWidth * 4,
              derivedBounds.height <= payload.sourceHeight * 4,
              annotation.fontSize.isFinite, annotation.fontSize > 0,
              annotation.stepNumber > 0,
              overlay.kind == expectedProjectKind(for: annotation.kind),
              hasValidGeometry(annotation),
              boundsMatchPoints(bounds, annotation.points,
                                sourceSize: CGSize(width: payload.sourceWidth, height: payload.sourceHeight))
        else { throw AnnotationPasteboardCodecError.invalidPayload }
        return annotation
    }

    private static func hasValidGeometry(_ annotation: Annotation) -> Bool {
        switch annotation.kind {
        case .text:
            return annotation.points.count == 1
                && !annotation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .step:
            return annotation.points.count == 1
        case .freehand, .highlighter:
            guard annotation.points.count >= 2, let first = annotation.points.first else { return false }
            let pointBounds = annotation.points.dropFirst().reduce(
                CGRect(x: first.x, y: first.y, width: 0, height: 0)
            ) { $0.union(CGRect(x: $1.x, y: $1.y, width: 0, height: 0)) }
            return pointBounds.width > 0 || pointBounds.height > 0
        case .line, .arrow:
            return annotation.points.count == 2
                && hypot(annotation.points[1].x - annotation.points[0].x,
                         annotation.points[1].y - annotation.points[0].y) > 0
        default:
            return annotation.points.count == 2
                && annotation.points[0] != annotation.points[1]
        }
    }

    private static func boundsMatchPoints(
        _ bounds: AeroNormalizedRect,
        _ points: [CGPoint],
        sourceSize: CGSize
    ) -> Bool {
        guard let first = points.first else { return false }
        let pointBounds = points.dropFirst().reduce(
            CGRect(x: first.x, y: first.y, width: 0, height: 0)
        ) { $0.union(CGRect(x: $1.x, y: $1.y, width: 0, height: 0)) }
        let expected = [pointBounds.minX / sourceSize.width, pointBounds.minY / sourceSize.height,
                        pointBounds.width / sourceSize.width, pointBounds.height / sourceSize.height]
        let actual = [bounds.x, bounds.y, bounds.width, bounds.height]
        return zip(expected, actual).allSatisfy { abs($0 - $1) <= 1e-9 }
    }

    private static func expectedProjectKind(for kind: AnnotationKind) -> AeroOverlay.Kind {
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
}
