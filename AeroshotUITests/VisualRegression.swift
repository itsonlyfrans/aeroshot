import CoreGraphics
import Foundation
import ImageIO

struct VisualRegressionManifest: Decodable {
    struct Fixture: Decodable {
        let file: String
        let masks: [PixelMask]
    }

    let schemaVersion: Int
    let approved: Bool
    let maxChannelDelta: UInt8
    let maxDifferingPixelRatio: Double
    let fixtures: [String: Fixture]

    static func load(from directory: URL) throws -> Self {
        let data = try Data(contentsOf: directory.appending(path: "manifest.json"))
        let manifest = try JSONDecoder().decode(Self.self, from: data)
        guard manifest.schemaVersion == 1, manifest.approved else {
            throw VisualRegressionError.unapprovedManifest
        }
        guard manifest.maxDifferingPixelRatio >= 0,
              manifest.maxDifferingPixelRatio <= 1 else {
            throw VisualRegressionError.invalidTolerance
        }
        return manifest
    }
}

struct PixelMask: Decodable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    func contains(x candidateX: Int, y candidateY: Int) -> Bool {
        width > 0 && height > 0
            && candidateX >= x && candidateX < x + width
            && candidateY >= y && candidateY < y + height
    }
}

struct VisualRegressionResult {
    let differingPixels: Int
    let comparedPixels: Int
    let maximumChannelDelta: UInt8

    var differingPixelRatio: Double {
        Double(differingPixels) / Double(comparedPixels)
    }
}

enum VisualRegressionError: LocalizedError {
    case unapprovedManifest
    case invalidTolerance
    case missingFixture(String)
    case unreadableImage(String)
    case sizeMismatch(actual: CGSize, baseline: CGSize)
    case emptyComparison

    var errorDescription: String? {
        switch self {
        case .unapprovedManifest:
            "The visual baseline manifest is not explicitly approved."
        case .invalidTolerance:
            "The visual baseline manifest has an invalid pixel tolerance."
        case let .missingFixture(name):
            "The visual baseline manifest does not define \(name)."
        case let .unreadableImage(path):
            "The visual comparison could not decode \(path)."
        case let .sizeMismatch(actual, baseline):
            "The screenshot size \(actual) does not match the baseline size \(baseline)."
        case .emptyComparison:
            "The visual mask excludes every pixel."
        }
    }
}

enum VisualRegressionComparator {
    static func compare(
        actualPNG: Data,
        fixtureName: String,
        baselineDirectory: URL,
        manifest: VisualRegressionManifest
    ) throws -> VisualRegressionResult {
        guard let fixture = manifest.fixtures[fixtureName] else {
            throw VisualRegressionError.missingFixture(fixtureName)
        }
        let baselineURL = baselineDirectory.appending(path: fixture.file)
        let actual = try rgbaPixels(from: actualPNG, path: "actual \(fixtureName)")
        let baseline = try rgbaPixels(from: Data(contentsOf: baselineURL), path: baselineURL.path)
        guard actual.width == baseline.width, actual.height == baseline.height else {
            throw VisualRegressionError.sizeMismatch(
                actual: CGSize(width: actual.width, height: actual.height),
                baseline: CGSize(width: baseline.width, height: baseline.height)
            )
        }

        var compared = 0
        var differing = 0
        var maximumDelta: UInt8 = 0
        for y in 0..<actual.height {
            for x in 0..<actual.width where !fixture.masks.contains(where: { $0.contains(x: x, y: y) }) {
                compared += 1
                let offset = (y * actual.width + x) * 4
                var pixelDiffers = false
                for channel in 0..<4 {
                    let delta = UInt8(abs(Int(actual.bytes[offset + channel]) - Int(baseline.bytes[offset + channel])))
                    maximumDelta = max(maximumDelta, delta)
                    pixelDiffers = pixelDiffers || delta > manifest.maxChannelDelta
                }
                differing += pixelDiffers ? 1 : 0
            }
        }
        guard compared > 0 else { throw VisualRegressionError.emptyComparison }
        return VisualRegressionResult(
            differingPixels: differing,
            comparedPixels: compared,
            maximumChannelDelta: maximumDelta
        )
    }

    private static func rgbaPixels(from data: Data, path: String) throws -> (bytes: [UInt8], width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw VisualRegressionError.unreadableImage(path)
        }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw VisualRegressionError.unreadableImage(path) }
        return (bytes, width, height)
    }
}
