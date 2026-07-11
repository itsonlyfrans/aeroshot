import CoreGraphics

nonisolated enum MediaSourceGeometry {
    static func orientedRect(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> CGRect? {
        let values = [naturalSize.width, naturalSize.height,
                      preferredTransform.a, preferredTransform.b, preferredTransform.c,
                      preferredTransform.d, preferredTransform.tx, preferredTransform.ty]
        guard values.allSatisfy(\.isFinite), naturalSize.width > 0, naturalSize.height > 0 else { return nil }
        let rect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform).standardized
        guard [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite),
              rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }
}
