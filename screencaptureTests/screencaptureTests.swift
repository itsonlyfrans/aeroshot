import CoreGraphics
import Testing
@testable import screencapture

// MARK: - GeometryConversions

struct GeometryConversionsTests {
    @Test func cocoaToCGRoundTrips() {
        let primaryHeight: CGFloat = 1080
        let rect = CGRect(x: 100, y: 200, width: 300, height: 150)
        let cg = GeometryConversions.cocoaToCG(rect, primaryHeight: primaryHeight)
        #expect(cg == CGRect(x: 100, y: 1080 - 200 - 150, width: 300, height: 150))
        let back = GeometryConversions.cgToCocoa(cg, primaryHeight: primaryHeight)
        #expect(back == rect)
    }

    @Test func pixelSizeRounds() {
        let size = GeometryConversions.pixelSize(for: CGRect(x: 0, y: 0, width: 100.4, height: 50.6), scale: 2)
        #expect(size == CGSize(width: 201, height: 101))
    }
}

// MARK: - UndoStack

@MainActor
struct UndoStackTests {

    private func makeImage() -> CGImage {
        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    @Test func addUndoRedo() {
        let doc = EditorDocument(image: makeImage())
        let annotation = Annotation(kind: .arrow, points: [.zero, CGPoint(x: 10, y: 10)])
        doc.perform(AddAnnotationCommand(annotation: annotation))
        #expect(doc.annotations.count == 1)
        doc.undo()
        #expect(doc.annotations.isEmpty)
        doc.redo()
        #expect(doc.annotations.count == 1)
    }

    @Test func twentyMixedOpsUndoAll() {
        let doc = EditorDocument(image: makeImage())
        for i in 0..<20 {
            switch i % 4 {
            case 0:
                doc.perform(AddAnnotationCommand(annotation: Annotation(kind: .rectangle, points: [.zero, CGPoint(x: CGFloat(i), y: 5)])))
            case 1:
                doc.perform(SetCropCommand(before: doc.cropRect, after: CGRect(x: 0, y: 0, width: CGFloat(i + 1), height: 2)))
            case 2:
                var b = doc.beautify
                b.padding = CGFloat(i)
                doc.perform(SetBeautifyCommand(before: doc.beautify, after: b))
            default:
                if let last = doc.annotations.last {
                    var modified = last
                    modified.lineWidth = CGFloat(i)
                    doc.perform(ModifyAnnotationCommand(before: last, after: modified))
                }
            }
        }
        #expect(doc.undoStack.canUndo)
        for _ in 0..<20 { doc.undo() }
        #expect(doc.annotations.isEmpty)
        #expect(doc.cropRect == nil)
        #expect(doc.beautify == BeautifySettings())
        #expect(!doc.undoStack.canUndo)
        #expect(doc.undoStack.canRedo)
    }

    @Test func redoClearedByNewCommand() {
        let doc = EditorDocument(image: makeImage())
        doc.perform(AddAnnotationCommand(annotation: Annotation(kind: .line, points: [.zero, CGPoint(x: 1, y: 1)])))
        doc.undo()
        #expect(doc.undoStack.canRedo)
        doc.perform(AddAnnotationCommand(annotation: Annotation(kind: .line, points: [.zero, CGPoint(x: 2, y: 2)])))
        #expect(!doc.undoStack.canRedo)
    }
}

// MARK: - ImageStitcher

struct ImageStitcherTests {

    /// Renders a tall gradient-with-stripes "page" and returns a viewport crop.
    private func makePage(height: Int) -> CGImage {
        let width = 200
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Deterministic pseudo-random horizontal stripes so correlation locks in.
        var seed: UInt64 = 42
        for y in 0..<height {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let v = CGFloat((seed >> 33) % 256) / 255.0
            ctx.setFillColor(CGColor(red: v, green: 1 - v, blue: v * 0.5, alpha: 1))
            ctx.fill(CGRect(x: 0, y: y, width: width, height: 1))
        }
        return ctx.makeImage()!
    }

    private func viewport(of page: CGImage, top: Int, height: Int) -> CGImage {
        page.cropping(to: CGRect(x: 0, y: top, width: page.width, height: height))!
    }

    @Test func detectsKnownOffset() {
        let page = makePage(height: 1200)
        let a = viewport(of: page, top: 0, height: 400)
        let b = viewport(of: page, top: 120, height: 400)
        let offset = ImageStitcher.verticalOffset(previous: a, next: b, downsample: 4)
        #expect(offset != nil)
        if let offset {
            #expect(abs(offset - 120) <= 8)  // within downsample tolerance
        }
    }

    @Test func rejectsUnrelatedFrames() {
        let pageA = makePage(height: 600)
        var seedPage: CGImage {
            let ctx = CGContext(data: nil, width: 200, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 400))
            return ctx.makeImage()!
        }
        let a = viewport(of: pageA, top: 0, height: 400)
        let offset = ImageStitcher.verticalOffset(previous: a, next: seedPage, minConfidence: 0.9)
        #expect(offset == nil)
    }

    @Test func stitchGrowsComposite() {
        let page = makePage(height: 1000)
        let a = viewport(of: page, top: 0, height: 300)
        let b = viewport(of: page, top: 100, height: 300)
        guard let offset = ImageStitcher.verticalOffset(previous: a, next: b) else {
            Issue.record("offset not found")
            return
        }
        let stitched = ImageStitcher.append(composite: a, next: b, newContentHeight: offset)
        #expect(stitched != nil)
        #expect(stitched?.height == 300 + offset)
        #expect(stitched?.width == 200)
    }

    @Test func normalizedCorrelationIdentity() {
        let signal: [Float] = (0..<64).map { Float(sin(Double($0) * 0.3)) }
        #expect(ImageStitcher.normalizedCorrelation(signal, signal) > 0.999)
    }
}
