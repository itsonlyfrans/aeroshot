import AppKit
import Foundation
import ImageIO

nonisolated struct GIFPreviewKey: Hashable, Sendable {
    let sourceURL: URL
    let crop: GIFNormalizedCrop?
    let maximumPixelSize: Int
}

nonisolated struct GIFDecodedPreview: @unchecked Sendable {
    let image: CGImage
    let cost: Int
}

nonisolated struct GIFPreviewDecoder: Sendable {
    let decode: @Sendable (GIFPreviewKey) async -> GIFDecodedPreview?

    static let production = GIFPreviewDecoder { key in
        await Task.detached(priority: .userInitiated) {
            GIFPreviewCache.decode(key)
        }.value
    }
}

/// Explicit LRU storage makes the real decoded-frame bound observable and deterministic.
@MainActor
final class GIFPreviewCache {
    private struct Item {
        let image: NSImage
        let cost: Int
    }

    let countLimit: Int
    let costLimit: Int
    private var items: [GIFPreviewKey: Item] = [:]
    private var order: [GIFPreviewKey] = []
    private var totalCost = 0

    init(countLimit: Int, costLimit: Int) {
        self.countLimit = max(1, countLimit)
        self.costLimit = max(1, costLimit)
    }

    var count: Int { items.count }

    nonisolated static func decode(_ key: GIFPreviewKey) -> GIFDecodedPreview? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: key.maximumPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(key.sourceURL as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let displayed: CGImage
        if let crop = key.crop {
            let rect = CGRect(
                x: crop.x * Double(image.width), y: crop.y * Double(image.height),
                width: crop.width * Double(image.width), height: crop.height * Double(image.height)
            ).integral
            displayed = image.cropping(to: rect) ?? image
        } else {
            displayed = image
        }
        return .init(image: displayed, cost: displayed.bytesPerRow * displayed.height)
    }

    func image(for key: GIFPreviewKey) -> NSImage? {
        guard let item = items[key] else { return nil }
        touch(key)
        return item.image
    }

    func insert(_ image: NSImage, for key: GIFPreviewKey, cost: Int) {
        if let prior = items.removeValue(forKey: key) {
            totalCost -= prior.cost
            order.removeAll { $0 == key }
        }
        let boundedCost = max(1, min(cost, costLimit))
        items[key] = .init(image: image, cost: boundedCost)
        order.append(key)
        totalCost += boundedCost
        while items.count > countLimit || (totalCost > costLimit && items.count > 1) {
            guard let oldest = order.first else { break }
            order.removeFirst()
            if let removed = items.removeValue(forKey: oldest) { totalCost -= removed.cost }
        }
    }

    func removeAll() {
        items.removeAll()
        order.removeAll()
        totalCost = 0
    }

    @discardableResult
    func evictLeastRecentlyUsed() -> Bool {
        guard let oldest = order.first else { return false }
        order.removeFirst()
        if let removed = items.removeValue(forKey: oldest) {
            totalCost -= removed.cost
            return true
        }
        return false
    }

    private func touch(_ key: GIFPreviewKey) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
