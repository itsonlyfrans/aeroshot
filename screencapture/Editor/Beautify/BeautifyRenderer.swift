import AppKit

/// Composites an image onto a gradient background with padding, rounded
/// corners, and a drop shadow. Non-destructive: applied only at render time.
enum BeautifyRenderer {

    static func render(image: CGImage, settings: BeautifySettings) -> CGImage? {
        guard settings.enabled else { return image }

        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)
        let pad = settings.padding

        var canvasW = imgW + pad * 2
        var canvasH = imgH + pad * 2
        if let ratio = settings.aspectPreset.ratio {
            if canvasW / canvasH > ratio {
                canvasH = canvasW / ratio
            } else {
                canvasW = canvasH * ratio
            }
        }

        guard let ctx = CGContext(data: nil,
                                  width: Int(canvasW.rounded()), height: Int(canvasH.rounded()),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // Gradient background (diagonal).
        let (c1, c2) = settings.gradient.colors
        let colors = [c1.cgColor, c2.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: canvasH),
                                   end: CGPoint(x: canvasW, y: 0),
                                   options: [])
        }

        let imageRect = CGRect(x: (canvasW - imgW) / 2, y: (canvasH - imgH) / 2, width: imgW, height: imgH)

        // Shadow + rounded-corner clip.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -settings.shadowRadius / 3),
                      blur: settings.shadowRadius,
                      color: NSColor.black.withAlphaComponent(settings.shadowOpacity).cgColor)
        let path = CGPath(roundedRect: imageRect,
                          cornerWidth: settings.cornerRadius, cornerHeight: settings.cornerRadius,
                          transform: nil)
        // Draw a fill first so the shadow follows the rounded shape.
        ctx.addPath(path)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.draw(image, in: imageRect)
        ctx.restoreGState()

        return ctx.makeImage()
    }
}
