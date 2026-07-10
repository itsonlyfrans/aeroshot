import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct GIFWriteMetadata: Equatable, Sendable {
    var frameCount: Int
    var durationMicroseconds: Int64
    var loop: GIFLoop
    var imageIOLoopCount: Int
    var outputSize: CGSize
    var byteCount: Int64
    var coalescedFrameCount: Int
    var changedRegionFrameCount: Int
}

nonisolated struct GIFWriter {
    func write(_ document: GIFDocument, to outputURL: URL) async throws -> GIFWriteMetadata {
        let settings = try document.settings.validated()
        let sequence = expandedFrames(document.frames, pingPong: settings.pingPong)
        guard !sequence.isEmpty else { throw GIFCoreError.noFrames }
        let partialURL = outputURL.deletingLastPathComponent()
            .appending(path: "." + outputURL.lastPathComponent + ".partial-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: partialURL) }
        try checkCancellation()

        let coalesced = document.annotations.isEmpty ? try coalescedFrames(sequence) : sequence.map { ($0, $0.durationMicroseconds) }
        var actualSize = CGSize.zero
        var timelineCursor: Int64 = 0
        var encoder: GIFDeltaEncoder?
        for item in coalesced {
            try checkCancellation()
            guard let source = CGImageSourceCreateWithURL(item.frame.sourceURL as CFURL, nil),
                  let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw GIFCoreError.imageReadFailed
            }
            let annotationText = document.annotations.filter {
                $0.range.startMicroseconds < timelineCursor + item.durationMicroseconds && $0.range.endMicroseconds > timelineCursor
            }.map(\.text)
            let image = try transformed(sourceImage, settings: settings, annotationText: annotationText)
            actualSize = CGSize(width: image.width, height: image.height)
            if encoder == nil {
                encoder = try GIFDeltaEncoder(url: partialURL, width: image.width, height: image.height, settings: settings)
            }
            try encoder?.append(image, durationMicroseconds: item.durationMicroseconds)
            timelineCursor += item.durationMicroseconds
        }
        try checkCancellation()
        guard let encoder else { throw GIFCoreError.imageWriteFailed }
        try encoder.finish()
        try checkCancellation()
        if FileManager.default.fileExists(atPath: outputURL.path) {
            _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: partialURL, backupItemName: nil, options: [])
        } else {
            try FileManager.default.moveItem(at: partialURL, to: outputURL)
        }
        let bytes = Int64((try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return GIFWriteMetadata(
            frameCount: coalesced.count,
            durationMicroseconds: sequence.reduce(0) { $0 + $1.durationMicroseconds },
            loop: settings.loop,
            imageIOLoopCount: settings.loop.imageIOLoopCount,
            outputSize: actualSize,
            byteCount: bytes,
            coalescedFrameCount: sequence.count - coalesced.count,
            changedRegionFrameCount: encoder.statistics.changedRegionFrameCount
        )
    }

    private func expandedFrames(_ frames: [GIFFrame], pingPong: Bool) -> [GIFFrame] {
        guard pingPong, frames.count > 1 else { return frames }
        return frames + frames.dropFirst().dropLast().reversed()
    }

    private func checkCancellation() throws {
        if Task.isCancelled { throw GIFCoreError.cancelled }
    }

    private func coalescedFrames(_ frames: [GIFFrame]) throws -> [(frame: GIFFrame, durationMicroseconds: Int64)] {
        var result: [(GIFFrame, Int64)] = []
        var previousData: Data?
        for frame in frames {
            let data = try Data(contentsOf: frame.sourceURL, options: [.mappedIfSafe])
            if data == previousData, !result.isEmpty {
                result[result.count - 1].1 += frame.durationMicroseconds
            } else {
                result.append((frame, frame.durationMicroseconds))
                previousData = data
            }
        }
        return result
    }

    private func transformed(_ image: CGImage, settings: GIFExportSettings, annotationText: [String]) throws -> CGImage {
        let width = settings.outputWidth ?? image.width
        let height = settings.outputHeight ?? image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: (settings.preservesTransparency
                ? CGImageAlphaInfo.premultipliedLast
                : CGImageAlphaInfo.noneSkipLast).rawValue
        ) else { throw GIFCoreError.imageWriteFailed }
        context.interpolationQuality = settings.quality >= 0.67 ? .high : (settings.quality >= 0.34 ? .medium : .low)
        if !settings.preservesTransparency {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let source = settings.crop.map { crop in
            CGRect(x: crop.x * Double(image.width), y: crop.y * Double(image.height),
                   width: crop.width * Double(image.width), height: crop.height * Double(image.height))
        } ?? CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(width) / source.width, y: -CGFloat(height) / source.height)
        context.draw(image, in: CGRect(x: -source.minX, y: -source.minY,
                                      width: CGFloat(image.width), height: CGFloat(image.height)))
        context.restoreGState()
        drawAnnotations(annotationText, in: context, width: width, height: height)
        guard settings.paletteSize < 256 || settings.dither != .none else {
            guard let result = context.makeImage() else { throw GIFCoreError.imageWriteFailed }
            return result
        }
        quantize(context: context, width: width, height: height, paletteSize: settings.paletteSize, dither: settings.dither)
        guard let result = context.makeImage() else { throw GIFCoreError.imageWriteFailed }
        return result
    }

    private func drawAnnotations(_ values: [String], in context: CGContext, width: Int, height: Int) {
        for (index, value) in values.prefix(4).enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [
                kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName("Helvetica-Bold" as CFString, max(12, CGFloat(width) * 0.035), nil),
                kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 1, alpha: 1),
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
            let bounds = CTLineGetBoundsWithOptions(line, [])
            let x: CGFloat = 18, y = CGFloat(height) - 30 - CGFloat(index) * (bounds.height + 14)
            context.setFillColor(CGColor(gray: 0, alpha: 0.78))
            context.fill(CGRect(x: x - 8, y: y - 6, width: min(CGFloat(width) - x, bounds.width + 16), height: bounds.height + 12))
            context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(line, context)
        }
    }

    private func quantize(context: CGContext, width: Int, height: Int, paletteSize: Int, dither: GIFDither) {
        guard let data = context.data else { return }
        let channels = max(2, Int(pow(Double(paletteSize), 1.0 / 3.0).rounded(.down)))
        let step = max(1, 255 / (channels - 1))
        let bytes = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
        let matrix = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * context.bytesPerRow + x * 4
                let bias = dither == .ordered ? (matrix[y % 4][x % 4] - 8) * max(1, step / 16) : 0
                for channel in 0..<3 {
                    let adjusted = min(255, max(0, Int(bytes[offset + channel]) + bias))
                    bytes[offset + channel] = UInt8(min(255, Int((Double(adjusted) / Double(step)).rounded()) * step))
                }
            }
        }
    }
}
