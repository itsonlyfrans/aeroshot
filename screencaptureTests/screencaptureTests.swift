import AppKit
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

    @Test func cocoaPointToCGRoundTrips() {
        let primaryHeight: CGFloat = 1080
        let point = NSPoint(x: 250, y: 400)
        let cg = GeometryConversions.cocoaPointToCG(point, primaryHeight: primaryHeight)
        #expect(cg == CGPoint(x: 250, y: 680))
        let rect = CGRect(x: 100, y: 200, width: 300, height: 150)
        #expect(rect.contains(cg) == rect.contains(CGPoint(x: cg.x, y: cg.y)))
    }

    @Test func pixelSizeRounds() {
        let size = GeometryConversions.pixelSize(for: CGRect(x: 0, y: 0, width: 100.4, height: 50.6), scale: 2)
        #expect(size == CGSize(width: 201, height: 101))
    }
}

// MARK: - SettingsStore

struct SettingsStoreTests {
    @MainActor
    @Test func duplicateStoredHotkeyFallsBackToDefault() {
        let duplicate = HotkeyAction.captureArea.defaultHotkey
        let resolved = SettingsStore.resolvedHotkeys(stored: [
            HotkeyAction.showHistory.rawValue: duplicate
        ])
        #expect(resolved[.showHistory] == HotkeyAction.showHistory.defaultHotkey)
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

    @Test func detectsKnownOffsetExactly() {
        let page = makePage(height: 1200)
        let a = viewport(of: page, top: 0, height: 400)
        let b = viewport(of: page, top: 120, height: 400)
        let offset = ImageStitcher.verticalOffset(previous: a, next: b, downsample: 4)
        #expect(offset == 120)  // full-res refinement should be row-exact
    }

    @Test func identicalFramesReportedAsIdentical() {
        let page = makePage(height: 600)
        let a = viewport(of: page, top: 50, height: 400)
        guard case .identical? = ImageStitcher.match(previous: a, next: a) else {
            Issue.record("expected .identical")
            return
        }
    }

    @Test func stickyFooterDetectedAndExcluded() {
        // Two frames scrolled by 100 px sharing an identical 60 px bottom bar.
        let page = makePage(height: 1200)
        let bar = makeSolidBar(width: 200, height: 60)
        let a = compose(top: viewport(of: page, top: 0, height: 340), bottom: bar)
        let b = compose(top: viewport(of: page, top: 100, height: 340), bottom: bar)
        guard case .matched(let m)? = ImageStitcher.match(previous: a, next: b) else {
            Issue.record("no match")
            return
        }
        #expect(m.offset == 100)
        #expect(abs(m.footerRows - 60) <= 2)
        let stitched = ImageStitcher.append(composite: a, next: b,
                                            newContentHeight: m.offset, footerRows: m.footerRows)
        #expect(stitched?.height == 400 + m.offset)
    }

    private func makeSolidBar(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// Stacks `top` above `bottom` into one image.
    private func compose(top: CGImage, bottom: CGImage) -> CGImage {
        let h = top.height + bottom.height
        let ctx = CGContext(data: nil, width: top.width, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .none
        ctx.draw(top, in: CGRect(x: 0, y: bottom.height, width: top.width, height: top.height))
        ctx.draw(bottom, in: CGRect(x: 0, y: 0, width: bottom.width, height: bottom.height))
        return ctx.makeImage()!
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

    /// Worst-case real content: mostly-black page, sparse "text" rows, static
    /// black sidebars, sticky header — like a dark-mode social feed.
    @Test func sparseDarkPageWithSidebarsAndHeader() {
        let width = 400
        let pageHeight = 3000
        let ctx = CGContext(data: nil, width: width, height: pageHeight, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: pageHeight))
        // Sparse content only in the center column (x 120..280), ~every 40 px.
        var seed: UInt64 = 7
        for y in stride(from: 0, to: pageHeight, by: 40) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let v = 0.3 + CGFloat((seed >> 33) % 128) / 255.0
            let lineWidth = 40 + Int((seed >> 40) % 120)
            ctx.setFillColor(CGColor(gray: v, alpha: 1))
            ctx.fill(CGRect(x: 120, y: y, width: lineWidth, height: 6))
        }
        let page = ctx.makeImage()!

        func frame(top: Int) -> CGImage {
            let viewportH = 500
            let body = page.cropping(to: CGRect(x: 0, y: top, width: width, height: viewportH - 50))!
            // Sticky 50 px header stacked on top of the scrolled body.
            let hctx = CGContext(data: nil, width: width, height: viewportH, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            hctx.interpolationQuality = .none
            hctx.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.3, alpha: 1))
            hctx.fill(CGRect(x: 0, y: viewportH - 50, width: width, height: 50))
            hctx.draw(body, in: CGRect(x: 0, y: 0, width: width, height: viewportH - 50))
            return hctx.makeImage()!
        }

        for scroll in [40, 120, 260] {
            guard case .matched(let m)? = ImageStitcher.match(previous: frame(top: 0), next: frame(top: scroll)) else {
                Issue.record("no match at scroll \(scroll)")
                continue
            }
            #expect(m.offset == scroll, "scroll \(scroll)")
        }
    }

    @Test func normalizedCorrelationIdentity() {
        let signal: [Float] = (0..<64).map { Float(sin(Double($0) * 0.3)) }
        #expect(ImageStitcher.normalizedCorrelation(signal, signal) > 0.999)
    }
}

// MARK: - PIIDetector

struct PIIDetectorTests {
    @Test func detectsEmail() {
        let text = "Contact sarah.chen@acmecorp.com for help"
        let ranges = PIIDetector.sensitiveRanges(in: text)
        #expect(ranges.contains { String(text[$0]).contains("@") })
    }

    @Test func detectsInternalEmail() {
        #expect(PIIDetector.lineShouldBeRedacted("support@company.internal"))
    }

    @Test func detectsSplitEmailTokensOnSameLine() {
        let group = [
            OCRTextObservation(text: "support@company", boundingBox: CGRect(x: 10, y: 20, width: 120, height: 18)),
            OCRTextObservation(text: ".internal", boundingBox: CGRect(x: 132, y: 20, width: 60, height: 18)),
        ]
        let merged = ShareSafeService.groupObservationsByLine(group)
        #expect(merged.count == 1)
        let line = merged[0].map(\.text).joined(separator: " ")
        #expect(PIIDetector.lineShouldBeRedacted(line))
    }

    @Test func detectsPhoneNumber() {
        let text = "Call me at (415) 555-0192 tomorrow"
        let ranges = PIIDetector.sensitiveRanges(in: text)
        #expect(!ranges.isEmpty)
    }

    @Test func detectsStripeSecret() {
        let text = "key leaked: sk_live_4eC39HqLyjWDarjtT1zdp7dc"
        let ranges = PIIDetector.sensitiveRanges(in: text)
        #expect(ranges.contains { String(text[$0]).contains("sk_live_") })
    }

    @Test func ignoresBenignText() {
        let text = "Build succeeded with no warnings"
        #expect(PIIDetector.sensitiveRanges(in: text).isEmpty)
    }
}
