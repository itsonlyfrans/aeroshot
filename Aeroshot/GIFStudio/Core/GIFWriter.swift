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

nonisolated enum GIFWriteStage: Sendable {
    case frameEncoded(Int)
    case partialFinished(URL)
    case beforeAtomicCommit(URL)
}

nonisolated struct GIFWriter {
    func write(
        _ document: GIFDocument,
        to outputURL: URL,
        failureInjector: @Sendable (GIFWriteStage) throws -> Void = { _ in }
    ) async throws -> GIFWriteMetadata {
        let settings = try document.settings.validated()
        let plan = try GIFPresentationPlan(
            durations: document.frames.map(\.durationMicroseconds),
            pingPong: settings.pingPong
        )
        let sequence = plan.entries.map { document.frames[$0.sourceIndex] }
        guard !sequence.isEmpty else { throw GIFCoreError.noFrames }
        let partialURL = outputURL.deletingLastPathComponent()
            .appending(path: "." + outputURL.lastPathComponent + ".partial-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: partialURL) }
        try checkCancellation()

        let workItems: [(frame: GIFFrame, durationMicroseconds: Int64, sourceStartMicroseconds: Int64)]
        if document.annotations.isEmpty {
            workItems = try coalescedFrames(sequence).map { ($0.frame, $0.durationMicroseconds, 0) }
        } else {
            workItems = plan.entries.map {
                (document.frames[$0.sourceIndex], $0.durationMicroseconds, $0.sourceStartMicroseconds)
            }
        }
        var actualSize = CGSize.zero
        var encoder: GIFDeltaEncoder?
        for (index, item) in workItems.enumerated() {
            try checkCancellation()
            guard let source = CGImageSourceCreateWithURL(item.frame.sourceURL as CFURL, nil),
                  let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw GIFCoreError.imageReadFailed
            }
            let annotationText = document.annotations.filter {
                $0.range.startMicroseconds < item.sourceStartMicroseconds + item.durationMicroseconds
                    && $0.range.endMicroseconds > item.sourceStartMicroseconds
            }.map(\.text)
            let image = try transformed(sourceImage, settings: settings, annotationText: annotationText)
            actualSize = CGSize(width: image.width, height: image.height)
            if encoder == nil {
                encoder = try GIFDeltaEncoder(url: partialURL, width: image.width, height: image.height, settings: settings)
            }
            try encoder?.append(image, durationMicroseconds: item.durationMicroseconds)
            try failureInjector(.frameEncoded(index + 1))
        }
        try checkCancellation()
        guard let encoder else { throw GIFCoreError.imageWriteFailed }
        try encoder.finish()
        try checkCancellation()
        try failureInjector(.partialFinished(partialURL))
        guard let generated = CGImageSourceCreateWithURL(partialURL as CFURL, nil),
              CGImageSourceGetStatus(generated) == .statusComplete,
              CGImageSourceGetCount(generated) > 0
        else { throw GIFCoreError.imageWriteFailed }
        try failureInjector(.beforeAtomicCommit(partialURL))
        if FileManager.default.fileExists(atPath: outputURL.path) {
            _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: partialURL, backupItemName: nil, options: [])
        } else {
            try FileManager.default.moveItem(at: partialURL, to: outputURL)
        }
        let bytes = Int64((try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return GIFWriteMetadata(
            frameCount: workItems.count,
            durationMicroseconds: plan.durationMicroseconds,
            loop: settings.loop,
            imageIOLoopCount: settings.loop.imageIOLoopCount,
            outputSize: actualSize,
            byteCount: bytes,
            coalescedFrameCount: sequence.count - workItems.count,
            changedRegionFrameCount: encoder.statistics.changedRegionFrameCount
        )
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
        GIFCaptionRenderer.draw(annotationText, in: context, width: width, height: height)
        guard settings.paletteSize < 256 || settings.dither != .none else {
            guard let result = context.makeImage() else { throw GIFCoreError.imageWriteFailed }
            return result
        }
        quantize(context: context, width: width, height: height, paletteSize: settings.paletteSize, dither: settings.dither)
        guard let result = context.makeImage() else { throw GIFCoreError.imageWriteFailed }
        return result
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

nonisolated enum GIFCaptionRenderer {
    static func draw(_ captions: [String], in context: CGContext, width: Int, height: Int) {
        guard !captions.isEmpty, width > 0, height > 0 else { return }
        let count = CGFloat(captions.count)
        let fontSize = max(1, min(CGFloat(width) * 0.035, CGFloat(height) * 0.08,
                                  CGFloat(height) * 0.68 / count))
        let inset = max(4, CGFloat(width) * 0.04)
        let lineHeight = fontSize * 1.25
        let boxHeight = min(CGFloat(height), lineHeight * count + fontSize)
        let box = CGRect(x: 0, y: 0, width: CGFloat(width), height: boxHeight)
        context.setFillColor(CGColor(gray: 0, alpha: 0.78))
        context.fill(box)

        var alignment = CTTextAlignment.center
        var lineBreak = CTLineBreakMode.byWordWrapping
        let paragraph = withUnsafePointer(to: &alignment) { alignmentPointer in
            withUnsafePointer(to: &lineBreak) { lineBreakPointer in
                let settings = [
                    CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: alignmentPointer),
                    CTParagraphStyleSetting(spec: .lineBreakMode, valueSize: MemoryLayout<CTLineBreakMode>.size, value: lineBreakPointer),
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
        let attributed = NSAttributedString(string: captions.joined(separator: "\n"), attributes: [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil),
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 1, alpha: 1),
            kCTParagraphStyleAttributeName as NSAttributedString.Key: paragraph,
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: box.insetBy(dx: inset, dy: fontSize * 0.45), transform: nil)
        CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(), path, nil), context)
    }

    static func render(_ captions: [String], over image: CGImage) -> CGImage? {
        guard !captions.isEmpty else { return image }
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        draw(captions, in: context, width: image.width, height: image.height)
        return context.makeImage()
    }
}
