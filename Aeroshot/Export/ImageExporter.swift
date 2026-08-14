import AppKit
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ImageFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case png, jpeg, heic

    var id: String { rawValue }
    var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        }
    }
    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        }
    }
    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        }
    }
}

nonisolated enum ImageExporter {

    enum ExportError: Error { case destinationFailed, finalizeFailed }

    /// Write `image` to `url`. If `downscaleToPoints` is true the image is
    /// resampled to 1x (half size for a 2x capture) before writing.
    static func write(_ image: CGImage,
                      to url: URL,
                      format: ImageFormat,
                      jpegQuality: Double = 0.9,
                      scale: CGFloat = 1.0,
                      downscaleToPoints: Bool = false) throws {
        try encodedData(
            for: image,
            format: format,
            jpegQuality: jpegQuality,
            scale: scale,
            downscaleToPoints: downscaleToPoints
        ).write(to: url, options: .atomic)
    }

    static func encodedData(
        for image: CGImage,
        format: ImageFormat,
        jpegQuality: Double = 0.9,
        scale: CGFloat = 1,
        downscaleToPoints: Bool = false
    ) throws -> Data {
        let scale = scale.isFinite && scale > 0 ? scale : 1
        var output = image
        if downscaleToPoints, scale > 1 {
            output = resample(image, by: 1.0 / scale) ?? image
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else {
            throw ExportError.destinationFailed
        }
        var properties: [CFString: Any] = [:]
        if format == .jpeg || format == .heic {
            properties[kCGImageDestinationLossyCompressionQuality] = jpegQuality
        }
        // Embed DPI so retina PNGs open at the right point size.
        if !downscaleToPoints, scale > 1 {
            properties[kCGImagePropertyDPIWidth] = 72.0 * scale
            properties[kCGImagePropertyDPIHeight] = 72.0 * scale
        }
        CGImageDestinationAddImage(dest, output, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ExportError.finalizeFailed }
        return data as Data
    }

    static func data(
        for image: CGImage,
        format: ImageFormat,
        jpegQuality: Double = 0.9,
        scale: CGFloat = 1,
        downscaleToPoints: Bool = false
    ) -> Data? {
        try? encodedData(
            for: image,
            format: format,
            jpegQuality: jpegQuality,
            scale: scale,
            downscaleToPoints: downscaleToPoints
        )
    }

    static func resample(_ image: CGImage, by factor: CGFloat) -> CGImage? {
        let w = Int((CGFloat(image.width) * factor).rounded())
        let h = Int((CGFloat(image.height) * factor).rounded())
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}
