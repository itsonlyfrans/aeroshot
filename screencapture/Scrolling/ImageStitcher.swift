import Accelerate
import CoreGraphics

/// Stitches sequential scroll-capture frames vertically by finding the pixel
/// offset between consecutive frames with normalized cross-correlation on a
/// downsampled grayscale center strip.
enum ImageStitcher {

    struct StitchError: Error {
        let reason: String
    }

    // MARK: - Grayscale extraction

    /// Luma rows for the horizontal center strip of the image, downsampled by
    /// `downsample` in both axes. Returns row-major [height][width] floats.
    static func lumaRows(of image: CGImage, downsample: Int = 4) -> (data: [Float], width: Int, height: Int)? {
        let stripWidth = image.width / 2
        let stripX = image.width / 4
        let w = max(1, stripWidth / downsample)
        let h = max(1, image.height / downsample)
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        ctx.interpolationQuality = .low
        // Draw only the center strip, scaled into the small context.
        let cropped = image.cropping(to: CGRect(x: stripX, y: 0, width: stripWidth, height: image.height))
        guard let cropped else { return nil }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: w * h)
        var floats = [Float](repeating: 0, count: w * h)
        vDSP.convertElements(of: UnsafeBufferPointer(start: bytes, count: w * h), to: &floats)
        return (floats, w, h)
    }

    /// Mean intensity per row.
    static func rowProfile(_ luma: [Float], width: Int, height: Int) -> [Float] {
        var profile = [Float](repeating: 0, count: height)
        for row in 0..<height {
            luma.withUnsafeBufferPointer { buffer in
                var mean: Float = 0
                vDSP_meanv(buffer.baseAddress! + row * width, 1, &mean, vDSP_Length(width))
                profile[row] = mean
            }
        }
        return profile
    }

    // MARK: - Offset detection

    /// Finds the vertical offset (in full-resolution pixels) by which `next`
    /// is scrolled relative to `previous`. Returns nil if no confident match.
    static func verticalOffset(previous: CGImage, next: CGImage,
                               downsample: Int = 4,
                               minConfidence: Float = 0.9) -> Int? {
        guard previous.width == next.width, previous.height == next.height,
              let a = lumaRows(of: previous, downsample: downsample),
              let b = lumaRows(of: next, downsample: downsample)
        else { return nil }

        let profileA = rowProfile(a.data, width: a.width, height: a.height)
        let profileB = rowProfile(b.data, width: b.width, height: b.height)
        guard let (offsetSmall, confidence) = bestShift(reference: profileA, moving: profileB),
              confidence >= minConfidence, offsetSmall > 0
        else { return nil }
        return offsetSmall * downsample
    }

    /// Slides `moving` upward over `reference` and returns the shift with the
    /// highest normalized correlation of the overlapping region.
    /// A positive result means content moved up by that many rows (scrolled down).
    static func bestShift(reference: [Float], moving: [Float]) -> (shift: Int, confidence: Float)? {
        let n = min(reference.count, moving.count)
        guard n > 16 else { return nil }
        var best: (shift: Int, confidence: Float)?
        let maxShift = n - 12  // require at least 12 rows of overlap
        for shift in 1...maxShift {
            let overlap = n - shift
            // reference rows [shift..<n] should match moving rows [0..<overlap]
            let refSlice = Array(reference[shift..<n])
            let movSlice = Array(moving[0..<overlap])
            let corr = normalizedCorrelation(refSlice, movSlice)
            if corr > (best?.confidence ?? -1) {
                best = (shift, corr)
            }
        }
        return best
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

    // MARK: - Sticky header detection

    /// Number of top rows that are (nearly) identical between two frames —
    /// likely a sticky header that should be cropped from appended frames.
    static func stickyHeaderHeight(previous: CGImage, next: CGImage, downsample: Int = 4) -> Int {
        guard let a = lumaRows(of: previous, downsample: downsample),
              let b = lumaRows(of: next, downsample: downsample),
              a.width == b.width, a.height == b.height
        else { return 0 }
        var identicalRows = 0
        let tolerance: Float = 2.0
        for row in 0..<a.height {
            var diff: Float = 0
            let offset = row * a.width
            for col in 0..<a.width {
                diff += abs(a.data[offset + col] - b.data[offset + col])
            }
            if diff / Float(a.width) < tolerance {
                identicalRows += 1
            } else {
                break
            }
        }
        // Only treat as sticky header if a meaningful band matched but not everything.
        if identicalRows >= a.height { return 0 }
        return identicalRows * downsample
    }

    // MARK: - Compositing

    /// Append `next` below the already-stitched `composite` given the offset of
    /// `next` relative to the last appended frame.
    static func append(composite: CGImage, next: CGImage, newContentHeight: Int) -> CGImage? {
        guard newContentHeight > 0, newContentHeight <= next.height else { return nil }
        let width = composite.width
        let newHeight = composite.height + newContentHeight
        guard let ctx = CGContext(data: nil, width: width, height: newHeight,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // CGContext origin is bottom-left: existing composite goes on top.
        ctx.draw(composite, in: CGRect(x: 0, y: newContentHeight, width: width, height: composite.height))
        // The new content is the bottom `newContentHeight` pixels of `next`.
        let cropRect = CGRect(x: 0, y: next.height - newContentHeight, width: next.width, height: newContentHeight)
        guard let newStrip = next.cropping(to: cropRect) else { return nil }
        ctx.draw(newStrip, in: CGRect(x: 0, y: 0, width: width, height: newContentHeight))
        return ctx.makeImage()
    }
}
