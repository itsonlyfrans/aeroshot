import AppKit
import CoreGraphics

enum ShareSafeRedactionStyle: String, CaseIterable, Identifiable {
    case blur
    case pixelate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blur: return "Blur"
        case .pixelate: return "Pixelate"
        }
    }

    var annotationKind: AnnotationKind {
        switch self {
        case .blur: return .redactBlur
        case .pixelate: return .redactPixelate
        }
    }
}

struct ShareSafeResult: Sendable {
    let image: CGImage
    let matchCount: Int
}

enum ShareSafeService {
    private static let lineMergeThreshold: CGFloat = 8

    /// Scan the image for sensitive text regions and bake redactions.
    nonisolated static func process(image: CGImage, style: ShareSafeRedactionStyle) async throws -> ShareSafeResult {
        let rects = try await detectSensitiveRects(in: image)
        let redacted = await bakeRedactions(on: image, rects: rects, style: style)
        return ShareSafeResult(image: redacted, matchCount: rects.count)
    }

    nonisolated static func detectSensitiveRects(in image: CGImage) async throws -> [CGRect] {
        let observations = try await OCRService.recognizeObservations(in: image)
        let bounds = CGRect(origin: .zero, size: CGSize(width: image.width, height: image.height))
        let lineGroups = groupObservationsByLine(observations)
        var rects: [CGRect] = []

        for group in lineGroups {
            let text = group.map(\.text).joined(separator: " ")
            guard PIIDetector.lineShouldBeRedacted(text) else { continue }
            let union = group.map(\.boundingBox).reduce(CGRect.null) { $0.union($1) }
            let padded = union.insetBy(dx: -12, dy: -10).intersection(bounds)
            if !padded.isEmpty { rects.append(padded) }
        }

        return mergeRects(rects)
    }

    /// Merge OCR tokens that Vision split onto the same visual line (e.g. email + TLD).
    nonisolated static func groupObservationsByLine(_ observations: [OCRTextObservation]) -> [[OCRTextObservation]] {
        guard !observations.isEmpty else { return [] }
        let sorted = observations.sorted { lhs, rhs in
            if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 1 {
                return lhs.boundingBox.midY < rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        var groups: [[OCRTextObservation]] = []
        var current: [OCRTextObservation] = [sorted[0]]

        for observation in sorted.dropFirst() {
            let previous = current.last!
            let yDelta = abs(observation.boundingBox.midY - previous.boundingBox.midY)
            let lineHeight = max(previous.boundingBox.height, observation.boundingBox.height, 1)
            if yDelta <= max(lineMergeThreshold, lineHeight * 0.6) {
                current.append(observation)
            } else {
                groups.append(current)
                current = [observation]
            }
        }
        groups.append(current)
        return groups
    }

    @MainActor
    static func shareSafe(
        image: CGImage,
        fileURL: URL?,
        from view: NSView?,
        style: ShareSafeRedactionStyle
    ) async {
        ToastController.shared.show("Scanning for sensitive data…", symbol: "shield.checkered")

        do {
            let result = try await process(image: image, style: style)
            if result.matchCount == 0 {
                ToastController.shared.show("No sensitive data found", symbol: "checkmark.shield")
                ShareService.shareImage(image, fileURL: fileURL, from: view)
                return
            }

            ToastController.shared.show("Redacted \(result.matchCount) sensitive item\(result.matchCount == 1 ? "" : "s")", symbol: "checkmark.shield")
            ShareService.shareImage(result.image, fileURL: nil, from: view)
        } catch {
            ToastController.shared.show("Share Safe scan failed", symbol: "exclamationmark.triangle")
            ShareService.shareImage(image, fileURL: fileURL, from: view)
        }
    }

    @MainActor
    private static func bakeRedactions(on image: CGImage, rects: [CGRect], style: ShareSafeRedactionStyle) -> CGImage {
        guard !rects.isEmpty else { return image }
        let document = EditorDocument(image: image)
        document.annotations = rects.map { rect in
            Annotation(
                kind: style.annotationKind,
                points: [rect.origin, CGPoint(x: rect.maxX, y: rect.maxY)],
                lineWidth: 0
            )
        }
        return document.renderFinal() ?? image
    }

    private static func mergeRects(_ rects: [CGRect]) -> [CGRect] {
        var merged = rects
        var changed = true
        while changed {
            changed = false
            outer: for i in 0..<merged.count {
                for j in (i + 1)..<merged.count {
                    if merged[i].intersects(merged[j]) {
                        merged[i] = merged[i].union(merged[j])
                        merged.remove(at: j)
                        changed = true
                        break outer
                    }
                }
            }
        }
        return merged
    }
}
