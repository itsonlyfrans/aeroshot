import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Aeroshot

@MainActor
struct ImageExporterTests {
    @Test func sourceScaleControlsPointExportAndClipboardMetadata() throws {
        let image = try #require(CGContext(
            data: nil,
            width: 20,
            height: 10,
            bitsPerComponent: 8,
            bytesPerRow: 80,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage())
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ImageExporterTests-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        try ImageExporter.write(image, to: url, format: .png, scale: 2, downscaleToPoints: true)
        let downscaledSource = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let downscaled = try #require(CGImageSourceCreateImageAtIndex(downscaledSource, 0, nil))
        #expect(downscaled.width == 10)
        #expect(downscaled.height == 5)

        let data = try #require(ImageExporter.data(for: image, format: .png, scale: 2))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        #expect((properties[kCGImagePropertyDPIWidth] as? Double) == 144)
        #expect((properties[kCGImagePropertyDPIHeight] as? Double) == 144)
    }

    @Test func captureArtifactsReuseFullSizePNGAndKeepHistoryResolution() throws {
        let image = try #require(CGContext(
            data: nil,
            width: 20,
            height: 10,
            bitsPerComponent: 8,
            bytesPerRow: 80,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage())

        let fullSize = AppState.encodeCaptureArtifacts(
            image: image,
            sourceScale: 2,
            savedFormat: .png,
            jpegQuality: 0.9,
            downscaleToPoints: false
        )
        #expect(fullSize.savedData == fullSize.historyPNG)

        let pointSize = AppState.encodeCaptureArtifacts(
            image: image,
            sourceScale: 2,
            savedFormat: .png,
            jpegQuality: 0.9,
            downscaleToPoints: true
        )
        let historyData = try #require(pointSize.historyPNG)
        let savedData = try #require(pointSize.savedData)
        let historySource = try #require(CGImageSourceCreateWithData(historyData as CFData, nil))
        let savedSource = try #require(CGImageSourceCreateWithData(savedData as CFData, nil))
        #expect(try #require(CGImageSourceCreateImageAtIndex(historySource, 0, nil)).width == 20)
        #expect(try #require(CGImageSourceCreateImageAtIndex(savedSource, 0, nil)).width == 10)
    }
}
