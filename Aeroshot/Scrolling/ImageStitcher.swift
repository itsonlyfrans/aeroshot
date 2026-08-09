import Accelerate
import CoreGraphics

/// Stitches sequential scroll-capture frames vertically.
///
/// Alignment strategy: full-width 2D grayscale matching. A coarse pass over a
/// downsampled frame finds the candidate scroll offset by minimizing the mean
/// absolute difference of the overlapping region, a full-resolution pass
/// refines it to the exact row, and a correlation gate rejects uncertain
/// locks so a bad frame is skipped instead of producing a torn seam.
nonisolated enum ImageStitcher {

    struct Match {
        /// Rows the content moved up between the two frames (scroll distance in pixels).
        let offset: Int
        /// Sticky rows at the top (e.g. pinned toolbar) identical in both frames.
        let headerRows: Int
        /// Sticky rows at the bottom (e.g. reply bar) identical in both frames.
        let footerRows: Int
        let confidence: Float
        /// Full-image column range that actually scrolls (excludes static
        /// sidebars); useful for cropping the final composite.
        let contentColumns: ClosedRange<Int>
    }

    enum MatchResult {
        /// Frames are the same — the user hasn't scrolled yet.
        case identical
        case matched(Match)
    }

    // MARK: - Matching

    /// Aligns `next` against `previous`. Returns nil when no confident
    /// alignment exists (unrelated frames, or scrolled past the overlap).
    static func match(previous: CGImage, next: CGImage,
                      downsample: Int = 4,
                      minConfidence: Float = 0.95,
                      log: Bool = false) -> MatchResult? {
        guard previous.width == next.width, previous.height == next.height,
              let ga = grayFrame(previous), let gb = grayFrame(next)
        else {
            if log { print("stitch: size mismatch or gray conversion failed") }
            return nil
        }
        guard ga.height > 32 else { return nil }

        // Columns whose pixels change between the frames are the scrolling
        // region; static sidebars, nav rails, and letterboxing are masked out
        // so they can't poison the alignment score.
        let colDiff = columnDiff(ga, gb)
        let activeThreshold: Float = 2.0
        guard let firstActive = colDiff.firstIndex(where: { $0 > activeThreshold }),
              let lastActive = colDiff.lastIndex(where: { $0 > activeThreshold }),
              lastActive - firstActive >= 15
        else {
            let wholeFrameDiff = meanAbsDiff(ga.data, gb.data)
            if log { print("stitch: no active columns (wholeFrameDiff \(wholeFrameDiff))") }
            return wholeFrameDiff < 1.0 ? .identical : nil
        }

        let a = columnsCropped(ga, from: firstActive, to: lastActive)
        let b = columnsCropped(gb, from: firstActive, to: lastActive)
        let h = a.height
        let w = a.width
        // grayFrame trims `edgeInset` leading columns; map back to image space.
        let contentColumns = (firstActive + edgeInset)...(lastActive + edgeInset)

        // Sticky chrome: rows unchanged between the frames at the top/bottom
        // of the scrolling region (tolerant of vibrancy shimmer).
        let rowDiff = rowDiffProfile(a, b)
        let stickyTolerance: Float = 6.0
        var header = 0
        while header < h / 3, rowDiff[header] < stickyTolerance { header += 1 }
        var footer = 0
        while footer < h / 3, rowDiff[h - 1 - footer] < stickyTolerance { footer += 1 }

        let minOverlap = max(32, h / 12)
        let maxShift = h - header - footer - minOverlap
        if log { print("stitch: h=\(h) w=\(w) cols=\(contentColumns) header=\(header) footer=\(footer) maxShift=\(maxShift)") }
        guard maxShift >= 1 else { return nil }

        // Coarse pass on downsampled frames.
        let ds = max(1, downsample)
        let ac = downsampled(a, by: ds)
        let bc = downsampled(b, by: ds)
        let wc = ac.width
        let headerC = header / ds
        let footerC = footer / ds
        let maxShiftC = min(maxShift / ds, ac.height - headerC - footerC - 2)
        guard maxShiftC >= 1 else { return nil }

        var bestCoarse = (shift: 0, score: Float.greatestFiniteMagnitude)
        ac.data.withUnsafeBufferPointer { pa in
            bc.data.withUnsafeBufferPointer { pb in
                for d in 1...maxShiftC {
                    let rows = ac.height - footerC - headerC - d
                    guard rows > 0 else { break }
                    // Content scrolled up by d: next[y] should equal previous[y + d].
                    let score = meanAbsDiff(pa.baseAddress! + (headerC + d) * wc,
                                            pb.baseAddress! + headerC * wc,
                                            count: rows * wc)
                    if score < bestCoarse.score { bestCoarse = (d, score) }
                }
            }
        }
        if log { print("stitch: coarse shift=\(bestCoarse.shift * ds) score=\(bestCoarse.score)") }
        guard bestCoarse.shift > 0 else { return nil }

        // Full-resolution refinement around the coarse candidate. Candidates
        // are ranked by the fraction of rows that match near-exactly: at the
        // true alignment the scrolled content is pixel-identical row by row,
        // while transient overlays (hover cards, banners, animated media,
        // vibrancy shimmer) only subtract from that fraction — they can't
        // fake it at a wrong shift.
        let center = bestCoarse.shift * ds
        var best = (shift: 0, stats: RowStats(longestRunEvidence: -1, exactFraction: 0,
                                              trimmedError: .greatestFiniteMagnitude))
        for d in max(1, center - ds)...min(maxShift, center + ds) {
            let rows = h - footer - header - d
            guard rows >= minOverlap else { continue }
            let stats = rowStats(a, b, shift: d, header: header, rows: rows)
            let better = stats.longestRunEvidence > best.stats.longestRunEvidence ||
                (stats.longestRunEvidence == best.stats.longestRunEvidence &&
                 stats.trimmedError < best.stats.trimmedError)
            if better { best = (d, stats) }
        }
        guard best.shift > 0 else { return nil }

        // Gate: one contiguous exactly-matching band must contain a
        // meaningful amount of visual structure. A wrong shift can align
        // scattered repeats, but not 16+ structured rows in an unbroken run.
        if log {
            print("stitch: refined shift=\(best.shift) runEvidence=\(best.stats.longestRunEvidence) exactFrac=\(best.stats.exactFraction) trimmedError=\(best.stats.trimmedError)")
        }
        guard best.stats.longestRunEvidence >= 16 else {
            if log { print("stitch: REJECTED by gate") }
            return nil
        }

        return .matched(Match(offset: best.shift, headerRows: header,
                              footerRows: footer, confidence: best.stats.exactFraction,
                              contentColumns: contentColumns))
    }

    /// Convenience: just the scroll offset, or nil when there is no confident match.
    static func verticalOffset(previous: CGImage, next: CGImage,
                               downsample: Int = 4,
                               minConfidence: Float = 0.95) -> Int? {
        if case .matched(let m)? = match(previous: previous, next: next,
                                         downsample: downsample, minConfidence: minConfidence) {
            return m.offset
        }
        return nil
    }

    // MARK: - Compositing

    /// Appends the newly revealed rows of `next` below `composite`, skipping
    /// any sticky footer so fixed bottom chrome isn't duplicated mid-image.
    static func append(composite: CGImage, next: CGImage,
                       newContentHeight: Int, footerRows: Int = 0) -> CGImage? {
        guard composite.width == next.width,
              let strip = newContentStrip(from: next,
                                          newContentHeight: newContentHeight,
                                          footerRows: footerRows)
        else { return nil }
        return appendStrip(composite: composite, strip: strip)
    }

    /// Returns only the newly revealed rows from a matched viewport frame.
    static func newContentStrip(from next: CGImage,
                                newContentHeight: Int,
                                footerRows: Int = 0) -> CGImage? {
        guard newContentHeight > 0, footerRows >= 0,
              newContentHeight + footerRows <= next.height
        else { return nil }
        return next.cropping(to: CGRect(x: 0,
                                       y: next.height - footerRows - newContentHeight,
                                       width: next.width,
                                       height: newContentHeight))
    }

    /// Builds the final image once. Live capture stores narrow strips instead
    /// of copying the complete growing image after each frame.
    static func compose(strips: [CGImage]) -> CGImage? {
        guard let first = strips.first,
              strips.allSatisfy({ $0.width == first.width })
        else { return nil }
        let height = strips.reduce(0) { $0 + $1.height }
        guard height > 0,
              let ctx = CGContext(data: nil, width: first.width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .none
        var y = height
        for strip in strips {
            y -= strip.height
            ctx.draw(strip, in: CGRect(x: 0, y: y, width: strip.width, height: strip.height))
        }
        return ctx.makeImage()
    }

    /// Keeps only the newest rows for the live preview.
    static func previewTail(of image: CGImage, maxHeight: Int) -> CGImage? {
        guard maxHeight > 0 else { return nil }
        let height = min(image.height, maxHeight)
        return image.cropping(to: CGRect(x: 0,
                                        y: image.height - height,
                                        width: image.width,
                                        height: height))
    }

    static func removingBottomRows(from image: CGImage, count: Int) -> CGImage? {
        guard count >= 0, count < image.height else { return nil }
        guard count > 0 else { return image }
        return image.cropping(to: CGRect(x: 0, y: 0,
                                        width: image.width,
                                        height: image.height - count))
    }

    /// Draws `strip` directly below `composite` at full width, 1:1 pixels.
    static func appendStrip(composite: CGImage, strip: CGImage) -> CGImage? {
        let width = composite.width
        guard strip.width == width else { return nil }
        let newHeight = composite.height + strip.height
        guard let ctx = CGContext(data: nil, width: width, height: newHeight,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(composite, in: CGRect(x: 0, y: strip.height, width: width, height: composite.height))
        ctx.draw(strip, in: CGRect(x: 0, y: 0, width: width, height: strip.height))
        return ctx.makeImage()
    }

    /// Removes repeated side chrome from the stitched strips. A detected fixed
    /// header stays at the top. The remaining side columns use page background.
    static func freezeStaticColumns(composite: CGImage, firstFrame: CGImage,
                                    scrollingBand: ClosedRange<Int>,
                                    preservedHeaderRows: Int? = nil) -> CGImage? {
        let w = composite.width
        let h = composite.height
        guard firstFrame.width == w else { return nil }
        let fh = min(firstFrame.height, h)
        let preservedRows = min(max(0, preservedHeaderRows ?? fh), fh)
        let regions = [(0, scrollingBand.lowerBound),
                       (scrollingBand.upperBound + 1, w)].filter { $0.1 - $0.0 > 0 }
        guard !regions.isEmpty,
              let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(composite, in: CGRect(x: 0, y: 0, width: w, height: h))
        for (x0, x1) in regions {
            let rw = x1 - x0
            if h > preservedRows, let fill = dominantBottomColor(firstFrame, x0: x0, x1: x1) {
                ctx.setFillColor(fill)
                ctx.fill(CGRect(x: x0, y: 0, width: rw, height: h - preservedRows))
            }
            if preservedRows > 0,
               let slice = firstFrame.cropping(to: CGRect(x: x0, y: 0,
                                                         width: rw, height: preservedRows)) {
                ctx.draw(slice, in: CGRect(x: x0, y: h - preservedRows,
                                          width: rw, height: preservedRows))
            }
        }
        return ctx.makeImage()
    }

    /// Most frequent color among samples along the bottom row of the given
    /// column range — robust against small widgets (avatars, chips) sitting
    /// on the region's background.
    private static func dominantBottomColor(_ image: CGImage, x0: Int, x1: Int) -> CGColor? {
        let rw = x1 - x0
        guard rw > 0, image.height > 0,
              let strip = image.cropping(to: CGRect(x: x0, y: image.height - 1,
                                                    width: rw, height: 1))
        else { return nil }
        var pixels = [UInt8](repeating: 0, count: rw * 4)
        guard let ctx = CGContext(data: &pixels, width: rw, height: 1,
                                  bitsPerComponent: 8, bytesPerRow: rw * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(strip, in: CGRect(x: 0, y: 0, width: rw, height: 1))
        var counts: [UInt32: Int] = [:]
        for x in 0..<rw {
            let i = x * 4
            let key = UInt32(pixels[i]) << 16 | UInt32(pixels[i + 1]) << 8 | UInt32(pixels[i + 2])
            counts[key, default: 0] += 1
        }
        guard let (key, _) = counts.max(by: { $0.value < $1.value }) else { return nil }
        return CGColor(srgbRed: CGFloat((key >> 16) & 0xFF) / 255,
                       green: CGFloat((key >> 8) & 0xFF) / 255,
                       blue: CGFloat(key & 0xFF) / 255, alpha: 1)
    }

    // MARK: - Grayscale frames

    /// Leading columns trimmed by `grayFrame`; used to map masked column
    /// indices back to full-image coordinates.
    private static let edgeInset = 2

    private struct GrayFrame {
        let data: [Float]  // height rows × width cols, scrollbar column excluded
        let width: Int
        let height: Int
    }

    private static func grayFrame(_ image: CGImage) -> GrayFrame? {
        let w = image.width
        let h = image.height
        guard w > 16, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let rowBytes = ctx.bytesPerRow
        // Skip the outer edges and the rightmost strip where an overlay
        // scrollbar appears/moves between frames and would poison the match.
        let x0 = edgeInset
        let x1 = w - max(4, w / 25)
        let wm = x1 - x0
        guard wm > 8 else { return nil }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var floats = [Float](repeating: 0, count: wm * h)
        floats.withUnsafeMutableBufferPointer { buf in
            for y in 0..<h {
                vDSP_vfltu8(bytes + y * rowBytes + x0, 1,
                            buf.baseAddress! + y * wm, 1, vDSP_Length(wm))
            }
        }
        return GrayFrame(data: floats, width: wm, height: h)
    }

    private static func downsampled(_ f: GrayFrame, by ds: Int) -> GrayFrame {
        guard ds > 1 else { return f }
        let w = max(1, f.width / ds)
        let h = max(1, f.height / ds)
        var out = [Float](repeating: 0, count: w * h)
        let norm = Float(ds * ds)
        for y in 0..<h {
            for x in 0..<w {
                var sum: Float = 0
                for dy in 0..<ds {
                    let row = (y * ds + dy) * f.width + x * ds
                    for dx in 0..<ds { sum += f.data[row + dx] }
                }
                out[y * w + x] = sum / norm
            }
        }
        return GrayFrame(data: out, width: w, height: h)
    }

    /// Per-column mean absolute difference between two frames (no shift).
    private static func columnDiff(_ a: GrayFrame, _ b: GrayFrame) -> [Float] {
        let w = a.width
        let h = a.height
        var acc = [Float](repeating: 0, count: w)
        a.data.withUnsafeBufferPointer { pa in
            b.data.withUnsafeBufferPointer { pb in
                for y in 0..<h {
                    let ra = pa.baseAddress! + y * w
                    let rb = pb.baseAddress! + y * w
                    for x in 0..<w {
                        acc[x] += abs(ra[x] - rb[x])
                    }
                }
            }
        }
        let norm = Float(h)
        return acc.map { $0 / norm }
    }

    /// Per-row mean absolute difference between two frames (no shift).
    private static func rowDiffProfile(_ a: GrayFrame, _ b: GrayFrame) -> [Float] {
        let w = a.width
        let h = a.height
        var profile = [Float](repeating: 0, count: h)
        a.data.withUnsafeBufferPointer { pa in
            b.data.withUnsafeBufferPointer { pb in
                for y in 0..<h {
                    profile[y] = meanAbsDiff(pa.baseAddress! + y * w,
                                             pb.baseAddress! + y * w, count: w)
                }
            }
        }
        return profile
    }

    private static func columnsCropped(_ f: GrayFrame, from x0: Int, to x1: Int) -> GrayFrame {
        let w = x1 - x0 + 1
        guard w < f.width else { return f }
        var out = [Float](repeating: 0, count: w * f.height)
        f.data.withUnsafeBufferPointer { p in
            out.withUnsafeMutableBufferPointer { o in
                for y in 0..<f.height {
                    o.baseAddress!.advanced(by: y * w)
                        .update(from: p.baseAddress! + y * f.width + x0, count: w)
                }
            }
        }
        return GrayFrame(data: out, width: w, height: f.height)
    }

    struct RowStats {
        /// Most structured rows (rows with edges/text — real alignment
        /// evidence) inside any single contiguous run of exactly-matching
        /// rows. True alignments produce long clean runs; coincidental
        /// matches at wrong shifts are scattered single rows.
        let longestRunEvidence: Int
        let exactFraction: Float
        /// Mean error of the best 75% of rows.
        let trimmedError: Float
    }

    private static func rowStats(_ a: GrayFrame, _ b: GrayFrame,
                                 shift: Int, header: Int, rows: Int) -> RowStats {
        let w = a.width
        var rowScores = [Float](repeating: 0, count: rows)
        var exact = 0
        var runEvidence = 0
        var bestRunEvidence = 0
        a.data.withUnsafeBufferPointer { pa in
            b.data.withUnsafeBufferPointer { pb in
                for r in 0..<rows {
                    let rowB = pb.baseAddress! + (header + r) * w
                    let score = meanAbsDiff(pa.baseAddress! + (header + shift + r) * w,
                                            rowB, count: w)
                    rowScores[r] = score
    if score < 1.5 {
                        exact += 1
                        // Structure = horizontal detail (in-row variance) or a
                        // vertical edge (differs from the row above); flat
                        // filler rows prove nothing about alignment.
                        var mean: Float = 0, meanSq: Float = 0
                        vDSP_meanv(rowB, 1, &mean, vDSP_Length(w))
                        vDSP_measqv(rowB, 1, &meanSq, vDSP_Length(w))
                        var structured = meanSq - mean * mean > 9  // sd > 3
                        if !structured, header + r > 0 {
                            structured = meanAbsDiff(rowB, rowB - w, count: w) > 3
                        }
                        if structured { runEvidence += 1 }
                        bestRunEvidence = max(bestRunEvidence, runEvidence)
                    } else {
                        runEvidence = 0
                    }
                }
            }
        }
        rowScores.sort()
        let kept = max(1, (rows * 3) / 4)
        var mean: Float = 0
        vDSP_meanv(rowScores, 1, &mean, vDSP_Length(kept))
        return RowStats(longestRunEvidence: bestRunEvidence,
                        exactFraction: Float(exact) / Float(rows),
                        trimmedError: mean)
    }

    // MARK: - Math

    private static func meanAbsDiff(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        guard n > 0 else { return .greatestFiniteMagnitude }
        return a.withUnsafeBufferPointer { pa in
            b.withUnsafeBufferPointer { pb in
                meanAbsDiff(pa.baseAddress!, pb.baseAddress!, count: n)
            }
        }
    }

    private static func meanAbsDiff(_ a: UnsafePointer<Float>, _ b: UnsafePointer<Float>, count n: Int) -> Float {
        guard n > 0 else { return .greatestFiniteMagnitude }
        let chunk = 8192
        var total: Float = 0
        withUnsafeTemporaryAllocation(of: Float.self, capacity: min(n, chunk)) { buf in
            var i = 0
            while i < n {
                let c = min(chunk, n - i)
                vDSP_vsub(b + i, 1, a + i, 1, buf.baseAddress!, 1, vDSP_Length(c))
                vDSP_vabs(buf.baseAddress!, 1, buf.baseAddress!, 1, vDSP_Length(c))
                var sum: Float = 0
                vDSP_sve(buf.baseAddress!, 1, &sum, vDSP_Length(c))
                total += sum
                i += c
            }
        }
        return total / Float(n)
    }

    static func normalizedCorrelation(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        guard n > 1 else { return -1 }
        var meanA: Float = 0, meanB: Float = 0
        vDSP_meanv(a, 1, &meanA, vDSP_Length(n))
        vDSP_meanv(b, 1, &meanB, vDSP_Length(n))
        var da = [Float](repeating: 0, count: n)
        var db = [Float](repeating: 0, count: n)
        var negMeanA = -meanA, negMeanB = -meanB
        vDSP_vsadd(a, 1, &negMeanA, &da, 1, vDSP_Length(n))
        vDSP_vsadd(b, 1, &negMeanB, &db, 1, vDSP_Length(n))
        var dot: Float = 0, magA: Float = 0, magB: Float = 0
        vDSP_dotpr(da, 1, db, 1, &dot, vDSP_Length(n))
        vDSP_svesq(da, 1, &magA, vDSP_Length(n))
        vDSP_svesq(db, 1, &magB, vDSP_Length(n))
        let denom = sqrt(magA * magB)
        guard denom > 1e-6 else { return -1 }
        return dot / denom
    }
}
