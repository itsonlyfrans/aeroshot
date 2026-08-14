import AppKit
import Testing
@testable import Aeroshot

@MainActor
struct FrozenWindowCompositorTests {
    @Test func spanningWindowCompositesEveryDisplayAtTheHighestScale() throws {
        let bottom = try solidImage(width: 100, height: 100, color: .blue)
        let top = try solidImage(width: 200, height: 200, color: .red)
        let result = try #require(FrozenWindowCompositor.compose(
            windowFrame: CGRect(x: 10, y: 50, width: 80, height: 100),
            fragments: [
                FrozenDisplayFragment(
                    frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                    image: bottom,
                    scale: 1
                ),
                FrozenDisplayFragment(
                    frame: CGRect(x: 0, y: 100, width: 100, height: 100),
                    image: top,
                    scale: 2
                ),
            ]
        ))

        #expect(result.image.width == 160)
        #expect(result.image.height == 200)
        #expect(result.sourceScale == 2)
        #expect(try pixel(result.image, x: 80, y: 20).red > 240)
        #expect(try pixel(result.image, x: 80, y: 180).blue > 240)
    }

    @Test func incompleteFrozenCoverageFallsBackToLiveCapture() throws {
        let image = try solidImage(width: 100, height: 100, color: .red)
        #expect(FrozenWindowCompositor.compose(
            windowFrame: CGRect(x: 0, y: 50, width: 100, height: 100),
            fragments: [FrozenDisplayFragment(
                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                image: image,
                scale: 1
            )]
        ) == nil)
    }

    private func solidImage(width: Int, height: Int, color: NSColor) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> (red: UInt8, blue: UInt8) {
        let data = try #require(image.dataProvider?.data)
        let bytes = CFDataGetBytePtr(data)!
        let offset = y * image.bytesPerRow + x * 4
        return (bytes[offset], bytes[offset + 2])
    }
}
