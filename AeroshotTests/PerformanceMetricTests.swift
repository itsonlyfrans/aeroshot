import CoreGraphics
import XCTest
@testable import Aeroshot

/// Instruments-compatible Phase 7 baselines. These metrics intentionally avoid
/// oldest-hardware pass/fail thresholds; the product owner deferred that gate.
final class PerformanceMetricTests: XCTestCase {
    @MainActor
    func testSyntheticCaptureToCanvasLatency() throws {
        let image = try XCTUnwrap(CGContext(data: nil, width: 1_920, height: 1_080,
            bitsPerComponent: 8, bytesPerRow: 1_920 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            let document = EditorDocument(image: image)
            _ = document.renderFinal()
        }
    }

    @MainActor
    func testLongTimelineCPUAndMemory() throws {
        let assetID = UUID()
        let asset = MediaSourceAsset(id: assetID, url: URL(fileURLWithPath: "/benchmark/source.mp4"),
            duration: try RationalTime(10_000, 30), hasVideo: true, hasAudio: false)
        let slices = try (0..<10_000).map { index in
            MediaSlice(sourceAssetID: assetID, sourceRange: try RationalTimeRange(
                start: RationalTime(Int64(index), 30), duration: RationalTime(1, 30)))
        }
        let model = MediaCompositionModel(assets: [asset], slices: slices)
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            XCTAssertTrue(model.validate().isEmpty)
            XCTAssertEqual(model.duration, try? RationalTime(10_000, 30))
        }
    }
}
