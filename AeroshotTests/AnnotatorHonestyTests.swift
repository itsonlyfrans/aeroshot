import AppKit
import CoreGraphics
import Testing
@testable import Aeroshot

/// Slice 3: inspector sections may only appear when the renderer honors them,
/// privacy redactions stay opaque, and straighten is undoable.
@Suite(.serialized)
@MainActor
struct AnnotatorHonestyTests {
    @Test func inspectorSectionMatrixExposesOnlyHonoredControls() {
        let allKinds: [AnnotationKind] = [
            .arrow, .rectangle, .ellipse, .line, .freehand, .highlighter,
            .text, .redactBlur, .redactPixelate, .redactSolid, .step,
        ]
        for kind in allKinds {
            let sections = AnnotationInspectorSection.sections(for: kind)
            if kind.isRedaction {
                // Redactions expose information, not appearance controls.
                #expect(sections == [.redaction], "\(kind) must expose only the redaction section")
            } else {
                #expect(!sections.contains(.redaction))
                #expect(sections.contains(.color) && sections.contains(.shadow),
                        "\(kind) draws through applyAppearance, so color and shadow are honored")
                // Text/step glyph rendering ignores stroke width/dash/cap;
                // they get an opacity control instead of a full stroke section.
                let isGlyph = kind == .text || kind == .step
                #expect(sections.contains(.stroke) == !isGlyph)
                #expect(sections.contains(.strokeOpacity) == isGlyph)
                #expect(sections.contains(.fillAndShape) == (kind == .rectangle || kind == .ellipse))
                #expect(sections.contains(.arrowheads) == (kind == .arrow))
                #expect(sections.contains(.text) == isGlyph)
            }
        }
    }

    @Test func straightenIsUndoableAndBumpsUndoTick() {
        let document = EditorDocument(image: makeImage(width: 8, height: 8, fill: .white))
        let tickBefore = document.undoTick

        document.perform(SetStraightenCommand(before: 0, after: 3.5))
        #expect(document.straightenDegrees == 3.5)
        #expect(document.undoTick == tickBefore + 1)
        #expect(document.undoStack.canUndo)

        document.undo()
        #expect(document.straightenDegrees == 0)

        document.redo()
        #expect(document.straightenDegrees == 3.5)
    }

    @Test func finalRenderComposesStraightenCropAndBeautifyDeterministically() throws {
        let document = EditorDocument(image: makeTwoToneImage(width: 100, height: 80))
        document.straightenDegrees = 5
        document.cropRect = CGRect(x: 20, y: 10, width: 60, height: 40)
        document.beautify = BeautifySettings(
            enabled: true,
            padding: 10,
            cornerRadius: 6,
            shadowRadius: 4,
            shadowOpacity: 0.25,
            gradient: .ocean,
            aspectPreset: .auto
        )

        let first = try #require(document.renderFinal())
        let second = try #require(document.renderFinal())
        #expect(first.width == 80)
        #expect(first.height == 60)
        #expect(first.dataProvider?.data == second.dataProvider?.data)
    }

    @Test func exportForcesSolidRedactionsOpaque() throws {
        let document = EditorDocument(image: makeImage(width: 20, height: 20, fill: .white))
        document.annotations = [makeRedaction(.redactSolid, from: .zero, to: CGPoint(x: 20, y: 20), opacity: 0.4)]

        let rendered = try #require(AnnotationRenderer.renderAnnotated(document: document))
        let center = try #require(pixel(of: rendered, x: 10, y: 10))
        for channel in [center.r, center.g, center.b] {
            #expect(channel <= 2, "solid redaction must ignore stored opacity, got \(center)")
        }
    }

    @Test func canvasPreviewMatchesOpaqueRedactionExport() throws {
        for (kind, opacity) in [(AnnotationKind.redactSolid, 0.35), (.redactBlur, 0.5), (.redactPixelate, 0.7)] {
            let base = makeTwoToneImage(width: 100, height: 60)
            let document = EditorDocument(image: base)
            document.annotations = [
                makeRedaction(kind, from: CGPoint(x: 20, y: 10), to: CGPoint(x: 80, y: 50), opacity: opacity)
            ]

            let exported = try #require(AnnotationRenderer.renderAnnotated(document: document))

            let canvas = EditorCanvasNSView(document: document)
            canvas.frame = NSRect(x: 0, y: 0, width: 132, height: 92)
            // Render into an explicit 1x sRGB rep: parity is about compositing
            // math, so both pipelines must blend in the same colorspace and
            // without retina resampling.
            let rep = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 132, pixelsHigh: 92,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
            )?.retagging(with: .sRGB))
            canvas.cacheDisplay(in: canvas.bounds, to: rep)
            let canvasImage = try #require(rep.cgImage)
            // At 132×92 the image fits at exactly 1:1 with a 16pt margin, so
            // image pixel (x, y) is view pixel (x + 16, y + 16).

            for point in [(35, 25), (50, 30), (70, 45)] {
                let exportPixel = try #require(pixel(of: exported, x: point.0, y: point.1))
                let canvasPixel = try #require(pixel(
                    of: canvasImage, x: point.0 + 16, y: point.1 + 16
                ))
                for (a, b) in [(exportPixel.r, canvasPixel.r), (exportPixel.g, canvasPixel.g), (exportPixel.b, canvasPixel.b)] {
                    #expect(abs(Int(a) - Int(b)) <= 4,
                            "\(kind) at opacity \(opacity), pixel \(point): export \(exportPixel) vs canvas \(canvasPixel)")
                }
            }
        }
    }

    // MARK: - Fixtures

    private func makeRedaction(_ kind: AnnotationKind, from: CGPoint, to: CGPoint, opacity: Double) -> Annotation {
        var appearance = AnnotationAppearance()
        appearance.fill.opacity = CGFloat(opacity)
        return Annotation(kind: kind, points: [from, to], lineWidth: 0, appearance: appearance)
    }

    private func makeImage(width: Int, height: Int, fill: NSColor) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(fill.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// Left half dark, right half light, so blur/pixelate output differs from
    /// the base and opacity blending is observable.
    private func makeTwoToneImage(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.9, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return ctx.makeImage()!
    }

    private func pixel(of image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8)? {
        guard x >= 0, y >= 0, x < image.width, y < image.height else { return nil }
        guard let ctx = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        guard let data = ctx.data else { return nil }
        let p = data.bindMemory(to: UInt8.self, capacity: 4)
        return (p[0], p[1], p[2])
    }
}
