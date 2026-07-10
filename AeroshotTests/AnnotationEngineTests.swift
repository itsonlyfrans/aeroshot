import AppKit
import Testing
@testable import Aeroshot

@MainActor
struct AnnotationEngineTests {
    @Test func legacyInitializerDefaultsRemainExact() {
        let annotation = Annotation(kind: .arrow)

        #expect(annotation.points.isEmpty)
        #expect(annotation.color == .systemRed)
        #expect(annotation.lineWidth == 4)
        #expect(annotation.text == "")
        #expect(annotation.fontSize == 24)
        #expect(annotation.stepNumber == 1)
        #expect(!annotation.filled)
        #expect(annotation.appearance == AnnotationAppearance())
        #expect(annotation.appearance.stroke.opacity == 1)
        #expect(annotation.appearance.stroke.dash.isEmpty)
        #expect(annotation.appearance.cornerRadius == 2)
        #expect(annotation.appearance.arrow.startStyle == .none)
        #expect(annotation.appearance.arrow.endStyle == .filled)
        #expect(annotation.appearance.arrow.headLength == nil)
        #expect(annotation.appearance.arrow.headWidth == nil)
        #expect(annotation.appearance.arrow.inset == nil)
        #expect(annotation.appearance.arrow.curve == 0)
        #expect(annotation.appearance.typography.weight == .semibold)
        #expect(annotation.appearance.typography.padding == AnnotationInsets())
        #expect(annotation.appearance.typography.lineHeight == 1)
    }

    @Test func degenerateGeometryIsSafeAndDeterministic() {
        for kind in AnnotationKind.allTestKinds {
            let empty = Annotation(kind: kind)
            #expect(empty.boundingRect == .zero)
            #expect(empty.handles().isEmpty)
            #expect(!empty.hitTest(.zero))
        }

        let arrow = Annotation(kind: .arrow, points: [CGPoint(x: 4, y: 4), CGPoint(x: 4, y: 4)])
        #expect(AnnotationGeometry.arrowGeometry(for: arrow) == nil)
        #expect(arrow.boundingRect == .zero)
        #expect(arrow.handles() == [CGPoint(x: 4, y: 4)])
    }

    @Test func lineHitToleranceAcceptsImageSpaceInput() {
        let line = Annotation(
            kind: .line,
            points: [CGPoint(x: 0, y: 10), CGPoint(x: 100, y: 10)],
            lineWidth: 4
        )

        #expect(line.hitTest(CGPoint(x: 50, y: 16), tolerance: 4))
        #expect(!line.hitTest(CGPoint(x: 50, y: 17), tolerance: 4))
        #expect(line.hitTest(CGPoint(x: 50, y: 17), tolerance: 5))
    }

    @Test func toolSpecificShapeAndRedactionHitTests() {
        let outline = Annotation(
            kind: .rectangle,
            points: [CGPoint(x: 10, y: 20), CGPoint(x: 50, y: 60)],
            lineWidth: 2
        )
        var filled = outline
        filled.filled = true
        let redaction = Annotation(
            kind: .redactBlur,
            points: [CGPoint(x: 10, y: 20), CGPoint(x: 50, y: 60)]
        )

        #expect(outline.hitTest(CGPoint(x: 10, y: 40), tolerance: 0))
        #expect(!outline.hitTest(CGPoint(x: 30, y: 40), tolerance: 0))
        #expect(filled.hitTest(CGPoint(x: 30, y: 40), tolerance: 0))
        #expect(redaction.hitTest(CGPoint(x: 30, y: 40), tolerance: 0))
        #expect(!redaction.hitTest(CGPoint(x: 9, y: 40), tolerance: 0))
        #expect(outline.handles() == [
            CGPoint(x: 10, y: 20), CGPoint(x: 50, y: 20),
            CGPoint(x: 50, y: 60), CGPoint(x: 10, y: 60),
        ])
    }

    @Test func freehandBoundsAndHitsFollowPolylineRatherThanBoundingBox() {
        let annotation = Annotation(
            kind: .freehand,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 20, y: 20)],
            lineWidth: 4
        )

        #expect(annotation.boundingRect == CGRect(x: -2, y: -2, width: 24, height: 24))
        #expect(annotation.hitTest(CGPoint(x: 10, y: 1), tolerance: 0))
        #expect(!annotation.hitTest(CGPoint(x: 10, y: 10), tolerance: 0))
        #expect(annotation.handles() == [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 20)])
    }

    @Test func arrowheadsAreIndependentAndCustomDimensionsAreExact() throws {
        var appearance = AnnotationAppearance()
        appearance.arrow = AnnotationArrowAppearance(
            startStyle: .open,
            endStyle: .filled,
            headLength: 10,
            headWidth: 12,
            inset: 3,
            curve: 0
        )
        let annotation = Annotation(
            kind: .arrow,
            points: [CGPoint(x: 10, y: 20), CGPoint(x: 50, y: 20)],
            lineWidth: 4,
            appearance: appearance
        )
        let geometry = try #require(AnnotationGeometry.arrowGeometry(for: annotation))
        let start = try #require(geometry.startHead)
        let end = try #require(geometry.endHead)

        #expect(start.style == .open)
        #expect(end.style == .filled)
        #expect(approximatelyEqual(geometry.shaft.boundingBoxOfPath.minX, 13))
        #expect(approximatelyEqual(geometry.shaft.boundingBoxOfPath.maxX, 47))
        #expect(annotation.hitTest(CGPoint(x: 10, y: 20), tolerance: 0))
        #expect(annotation.hitTest(CGPoint(x: 50, y: 20), tolerance: 0))
    }

    @Test func curvedArrowProducesExpandedDeterministicBounds() throws {
        var appearance = AnnotationAppearance()
        appearance.arrow.curve = 30
        let annotation = Annotation(
            kind: .arrow,
            points: [CGPoint(x: 10, y: 40), CGPoint(x: 90, y: 40)],
            lineWidth: 4,
            appearance: appearance
        )
        let first = try #require(AnnotationGeometry.arrowGeometry(for: annotation))
        let second = try #require(AnnotationGeometry.arrowGeometry(for: annotation))

        #expect(first.shaft.boundingBoxOfPath == second.shaft.boundingBoxOfPath)
        #expect(first.shaft.boundingBoxOfPath.maxY > 40)
        #expect(annotation.boundingRect.contains(CGPoint(x: 50, y: 55)))
    }

    @Test func typographyControlsPaddingLineHeightAndAlignmentBounds() {
        var appearance = AnnotationAppearance()
        appearance.typography.padding = AnnotationInsets(top: 3, leading: 5, bottom: 7, trailing: 11)
        appearance.typography.lineHeight = 1.5
        appearance.typography.alignment = .trailing
        appearance.typography.backgroundColor = .yellow
        appearance.typography.backgroundOpacity = 0.25
        let annotation = Annotation(
            kind: .text,
            points: [CGPoint(x: 12, y: 24)],
            text: "wide\nx",
            fontSize: 20,
            appearance: appearance
        )
        let font = AnnotationGeometry.font(for: annotation)
        let expectedHeight = (font.ascender - font.descender + font.leading) * 3 + 10

        #expect(annotation.boundingRect.origin == CGPoint(x: 12, y: 24))
        #expect(approximatelyEqual(annotation.boundingRect.height, expectedHeight))
        #expect(annotation.boundingRect.width > "wide".size(withAttributes: [.font: font]).width)
    }

    @Test func rendererAppliesOpacityAndDashDeterministically() throws {
        var appearance = AnnotationAppearance()
        appearance.stroke.opacity = 0.5
        appearance.stroke.dash = [4, 4]
        let annotation = Annotation(
            kind: .line,
            points: [CGPoint(x: 2, y: 8), CGPoint(x: 30, y: 8)],
            color: .red,
            lineWidth: 2,
            appearance: appearance
        )
        let pixels = try renderedPixels(annotation, width: 32, height: 16)

        #expect(pixels.alpha(x: 3, y: 8) == 128)
        #expect(pixels.alpha(x: 8, y: 8) == 0)
        #expect(pixels.alpha(x: 11, y: 8) == 128)
    }

    @Test func legacyArrowRenderingIsByteEquivalent() throws {
        let annotation = Annotation(
            kind: .arrow,
            points: [CGPoint(x: 8, y: 24), CGPoint(x: 56, y: 12)],
            color: .systemRed,
            lineWidth: 4
        )

        let current = try renderedPixels(annotation, width: 64, height: 40).bytes
        let legacy = try legacyArrowPixels(annotation, width: 64, height: 40)
        #expect(current == legacy)
    }
}

private extension AnnotationKind {
    static let allTestKinds: [AnnotationKind] = [
        .arrow, .rectangle, .ellipse, .line, .freehand, .highlighter, .text,
        .redactBlur, .redactPixelate, .redactSolid, .step,
    ]
}

private struct PixelBuffer {
    let bytes: [UInt8]
    let width: Int
    let height: Int

    func alpha(x: Int, y: Int) -> UInt8 {
        bytes[(y * width + x) * 4 + 3]
    }
}

@MainActor
private func renderedPixels(_ annotation: Annotation, width: Int, height: Int) throws -> PixelBuffer {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let context = try #require(makeContext(bytes: &bytes, width: width, height: height))
    context.setShouldAntialias(false)
    AnnotationRenderer.draw(annotation, in: context)
    return PixelBuffer(bytes: bytes, width: width, height: height)
}

@MainActor
private func legacyArrowPixels(_ annotation: Annotation, width: Int, height: Int) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let context = try #require(makeContext(bytes: &bytes, width: width, height: height))
    context.setShouldAntialias(false)
    context.setStrokeColor(annotation.color.cgColor)
    context.setFillColor(annotation.color.cgColor)
    context.setLineWidth(annotation.lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    let start = annotation.points[0]
    let end = annotation.points[1]
    let angle = atan2(end.y - start.y, end.x - start.x)
    let headLength = max(annotation.lineWidth * 4, 14)
    let headAngle: CGFloat = .pi / 7
    let lineEnd = CGPoint(x: end.x - cos(angle) * headLength * 0.6,
                          y: end.y - sin(angle) * headLength * 0.6)
    context.move(to: start)
    context.addLine(to: lineEnd)
    context.strokePath()
    let first = CGPoint(x: end.x - cos(angle - headAngle) * headLength,
                        y: end.y - sin(angle - headAngle) * headLength)
    let second = CGPoint(x: end.x - cos(angle + headAngle) * headLength,
                         y: end.y - sin(angle + headAngle) * headLength)
    context.move(to: end)
    context.addLine(to: first)
    context.addLine(to: second)
    context.closePath()
    context.fillPath()
    return bytes
}

private func makeContext(bytes: inout [UInt8], width: Int, height: Int) -> CGContext? {
    CGContext(
        data: &bytes,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
}

private func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat = 0.001) -> Bool {
    abs(lhs - rhs) <= tolerance
}
