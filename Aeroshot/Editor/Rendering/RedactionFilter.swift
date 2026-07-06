import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Produces blurred / pixelated variants of the base image for redaction
/// annotations. Results are cached — computing them on a 5K image is costly.
final class RedactionFilter {
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private var cachedBlur: CGImage?
    private var cachedPixelate: CGImage?
    private let baseImage: CGImage

    init(baseImage: CGImage) {
        self.baseImage = baseImage
    }

    func blurredImage() -> CGImage? {
        if let cachedBlur { return cachedBlur }
        let input = CIImage(cgImage: baseImage)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = input.clampedToExtent()
        filter.radius = 18
        guard let output = filter.outputImage else { return nil }
        let result = context.createCGImage(output.cropped(to: input.extent), from: input.extent)
        cachedBlur = result
        return result
    }

    func pixelatedImage() -> CGImage? {
        if let cachedPixelate { return cachedPixelate }
        let input = CIImage(cgImage: baseImage)
        let filter = CIFilter.pixellate()
        filter.inputImage = input.clampedToExtent()
        filter.scale = Float(max(12, baseImage.width / 100))
        filter.center = CGPoint(x: input.extent.midX, y: input.extent.midY)
        guard let output = filter.outputImage else { return nil }
        let result = context.createCGImage(output.cropped(to: input.extent), from: input.extent)
        cachedPixelate = result
        return result
    }
}
