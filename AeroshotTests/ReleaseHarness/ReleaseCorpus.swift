import AppKit
import AVFoundation
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

@testable import Aeroshot

@MainActor enum ReleaseCorpus {
    static let seed: UInt64 = 0xA3E0_5A07_2026_0710

    struct FixtureChecksums: Codable, Equatable {
        let srgbPNG: String
        let displayP3PNG: String
        let scrollingPNG: String
        let mp4WithAudio: String
        let timedGIF: String
        let corruptAsset: String
        let truncatedAsset: String
    }

    struct BuiltCorpus {
        let root: URL
        let srgbPNG: URL
        let displayP3PNG: URL
        let scrollingPNG: URL
        let mp4WithAudio: URL
        let timedGIF: URL
        let corruptAsset: URL
        let truncatedAsset: URL
        let annotations: [Annotation]
        let timeline: MediaCompositionModel
        let checksums: FixtureChecksums
    }

    static func build() throws -> BuiltCorpus {
        let root = FileManager.default.temporaryDirectory.appending(path: "Aeroshot-WP09-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let srgb = root.appending(path: "patches-srgb-2x.png")
        let p3 = root.appending(path: "patches-display-p3-1x.png")
        let scrolling = root.appending(path: "scrolling-page-3x.png")
        let mp4 = root.appending(path: "av-fixture.mp4")
        let gif = root.appending(path: "timing-loop.gif")
        let corrupt = root.appending(path: "corrupt.png")
        let truncated = root.appending(path: "truncated.gif")
        try writePatchPNG(to: srgb, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, scale: 2)
        try writePatchPNG(to: p3, colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!, scale: 1)
        try writeScrollingPNG(to: scrolling, scale: 3)
        try writeMP4WithAudio(to: mp4)
        try writeTimedGIF(to: gif)
        try Data([0x89, 0x50, 0x4e, 0x47, 0, 1, 2, 3]).write(to: corrupt)
        let gifData = try Data(contentsOf: gif)
        try gifData.prefix(min(10, gifData.count)).write(to: truncated)
        let annotations = makeAnnotations(count: 100)
        let timeline = try makeTimeline(sliceCount: 10_000)
        return BuiltCorpus(
            root: root, srgbPNG: srgb, displayP3PNG: p3, scrollingPNG: scrolling,
            mp4WithAudio: mp4, timedGIF: gif, corruptAsset: corrupt, truncatedAsset: truncated,
            annotations: annotations, timeline: timeline,
            checksums: FixtureChecksums(
                srgbPNG: try checksum(srgb), displayP3PNG: try checksum(p3), scrollingPNG: try checksum(scrolling),
                mp4WithAudio: try checksum(mp4), timedGIF: try checksum(gif), corruptAsset: try checksum(corrupt),
                truncatedAsset: try checksum(truncated)
            )
        )
    }

    static func remove(_ corpus: BuiltCorpus) { try? FileManager.default.removeItem(at: corpus.root) }

    static func makeAnnotations(count: Int) -> [Annotation] {
        (0..<count).map { index in
            let x = CGFloat((index * 37) % 900), y = CGFloat((index * 53) % 600)
            let kinds: [AnnotationKind] = [.rectangle, .ellipse, .line, .arrow, .freehand, .text, .step]
            let kind = kinds[index % kinds.count]
            let points = kind == .text || kind == .step ? [CGPoint(x: x, y: y)] : [CGPoint(x: x, y: y), CGPoint(x: x + 40, y: y + 25)]
            return Annotation(id: fixedID(index + 1), kind: kind, points: points, color: .systemRed,
                              lineWidth: CGFloat(1 + index % 8), text: "A\(index)", stepNumber: index + 1,
                              filled: index.isMultiple(of: 2))
        }
    }

    static func makeTimeline(sliceCount: Int) throws -> MediaCompositionModel {
        let assetID = fixedID(99_999)
        let duration = try RationalTime(Int64(sliceCount), 30)
        let asset = MediaSourceAsset(id: assetID, url: URL(fileURLWithPath: "/generated/wp09.mp4"), duration: duration)
        let slices = try (0..<sliceCount).map { index in
            MediaSlice(id: fixedID(100_000 + index), sourceAssetID: assetID,
                       sourceRange: try RationalTimeRange(start: RationalTime(Int64(index), 30), duration: RationalTime(1, 30)))
        }
        return MediaCompositionModel(assets: [asset], slices: slices)
    }

    private static func writePatchPNG(to url: URL, colorSpace: CGColorSpace, scale: Int) throws {
        let width = 64 * scale, height = 48 * scale
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CorpusError.generation }
        let colors: [[CGFloat]] = [[1,0,0,1], [0,1,0,1], [0,0,1,1], [1,1,1,1], [0.18,0.18,0.18,1], [0.9,0.3,0.7,1]]
        for (index, components) in colors.enumerated() {
            context.setFillColor(CGColor(colorSpace: colorSpace, components: components)!)
            context.fill(CGRect(x: (index % 3) * width / 3, y: (index / 3) * height / 2, width: width / 3, height: height / 2))
        }
        guard let image = context.makeImage() else { throw CorpusError.generation }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CorpusError.generation }
    }

    private static func writeScrollingPNG(to url: URL, scale: Int) throws {
        let width = 240 * scale, height = 2_000 * scale
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CorpusError.generation }
        context.setFillColor(CGColor(gray: 0.96, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for row in 0..<100 {
            context.setFillColor(CGColor(gray: row.isMultiple(of: 2) ? 0.2 : 0.55, alpha: 1))
            context.fill(CGRect(x: 24 * scale, y: row * 20 * scale, width: (120 + row % 7 * 10) * scale, height: 3 * scale))
        }
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { throw CorpusError.generation }
    }

    private static func writeTimedGIF(to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 3, nil) else { throw CorpusError.generation }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 4]] as CFDictionary)
        for (index, delay) in [0.02, 0.07, 0.13].enumerated() {
            let image = try solidImage(index: index, size: 24)
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw CorpusError.generation }
    }

    private static func writeMP4WithAudio(to url: URL) throws {
        var lastError: Error = CorpusError.generation
        for _ in 0..<3 {
            try? FileManager.default.removeItem(at: url)
            do {
                try writeMP4WithAudioAttempt(to: url)
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))
                return
            } catch {
                lastError = error
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
            }
        }
        throw lastError
    }

    private static func writeMP4WithAudioAttempt(to url: URL) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 120])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 120])
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000])
        guard writer.canAdd(video), writer.canAdd(audio) else { throw CorpusError.mp4("cannot add inputs") }
        writer.add(video); writer.add(audio)
        guard writer.startWriting() else { throw writer.error ?? CorpusError.generation }
        writer.startSession(atSourceTime: .zero)
        // Feed audio before video so neither input can apply back-pressure while
        // this deliberately synchronous fixture generator is filling the other.
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 17_640)!
        pcm.frameLength = 17_640
        memset(pcm.floatChannelData![0], 0, Int(pcm.frameLength) * MemoryLayout<Float>.size)
        let sample = try makePCMSample(pcmBuffer: pcm, presentationTime: .zero)
        guard audio.isReadyForMoreMediaData, audio.append(sample) else { throw writer.error ?? CorpusError.mp4("audio append") }
        audio.markAsFinished()
        for frame in 0..<12 {
            while !video.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.001) }
            var pixel: CVPixelBuffer?
            CVPixelBufferCreate(nil, 160, 120, kCVPixelFormatType_32BGRA, nil, &pixel)
            guard let pixel else { throw CorpusError.mp4("pixel allocation") }
            CVPixelBufferLockBaseAddress(pixel, []); memset(CVPixelBufferGetBaseAddress(pixel), Int32(frame * 17), CVPixelBufferGetDataSize(pixel)); CVPixelBufferUnlockBaseAddress(pixel, [])
            guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else { throw writer.error ?? CorpusError.mp4("video append") }
        }
        video.markAsFinished()
        nonisolated(unsafe) var finished = false
        writer.finishWriting { finished = true }
        while !finished {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        guard writer.status == .completed else { throw writer.error ?? CorpusError.generation }
    }

    private static func solidImage(index: Int, size: Int) throws -> CGImage {
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CorpusError.generation }
        context.setFillColor(CGColor(red: CGFloat(index) / 3, green: 0.4, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()!
    }

    static func checksum(_ url: URL) throws -> String { SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined() }
    static func fixedID(_ value: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))! }
    enum CorpusError: Error { case generation; case mp4(String) }

    private static func makePCMSample(pcmBuffer: AVAudioPCMBuffer, presentationTime: CMTime) throws -> CMSampleBuffer {
        var description: CMAudioFormatDescription?
        var asbd = pcmBuffer.format.streamDescription.pointee
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
                                             magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description) == noErr,
              let description else { throw ReleaseCorpus.CorpusError.mp4("audio description") }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 44_100), presentationTimeStamp: presentationTime, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        let frames = CMItemCount(pcmBuffer.frameLength)
        guard CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: true, makeDataReadyCallback: nil,
                                   refcon: nil, formatDescription: description, sampleCount: frames, sampleTimingEntryCount: 1,
                                   sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample) == noErr,
              let sample else { throw ReleaseCorpus.CorpusError.mp4("sample buffer") }
        let bytes = Int(pcmBuffer.frameLength) * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes,
                                                 blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                                                 dataLength: bytes, flags: 0, blockBufferOut: &block) == noErr, let block else { throw ReleaseCorpus.CorpusError.mp4("block buffer") }
        CMBlockBufferReplaceDataBytes(with: pcmBuffer.floatChannelData![0], blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
        CMSampleBufferSetDataBuffer(sample, newValue: block)
        return sample
    }
}
