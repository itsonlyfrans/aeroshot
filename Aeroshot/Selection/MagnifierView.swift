import AppKit

/// Pixel loupe shown only while a region is actively being dragged.
final class MagnifierView: NSView {
    private let frozenImage: CGImage?
    private let display: DisplayInfo
    private let loupeSize: CGFloat = 100
    private let zoom: CGFloat = 8
    private var samplePixel: CGPoint = .zero

    init(frozenImage: CGImage?, display: DisplayInfo) {
        self.frozenImage = frozenImage
        self.display = display
        super.init(frame: CGRect(x: 0, y: 0, width: loupeSize, height: loupeSize))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(cursorLocal: NSPoint, in parent: NSView) {
        guard frozenImage != nil else { return }
        samplePixel = CGPoint(
            x: cursorLocal.x * display.scale,
            y: (parent.bounds.height - cursorLocal.y) * display.scale
        )

        var origin = NSPoint(x: cursorLocal.x + 20, y: cursorLocal.y + 20)
        if origin.x + frame.width > parent.bounds.width { origin.x = cursorLocal.x - frame.width - 20 }
        if origin.y + frame.height > parent.bounds.height { origin.y = cursorLocal.y - frame.height - 20 }
        setFrameOrigin(origin)
        isHidden = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let frozenImage else { return }
        let loupeRect = bounds
        let clip = CGPath(ellipseIn: loupeRect, transform: nil)

        context.saveGState()
        context.addPath(clip)
        context.clip()
        context.setFillColor(NSColor.black.cgColor)
        context.fill(loupeRect)

        let side = loupeSize / zoom * display.scale
        let sample = CGRect(x: samplePixel.x - side / 2, y: samplePixel.y - side / 2, width: side, height: side)
        if let cropped = frozenImage.cropping(to: sample.integral) {
            context.interpolationQuality = .none
            // ScreenCaptureKit's image orientation already matches this AppKit
            // context. Flipping here inverts the loupe vertically.
            context.draw(cropped, in: loupeRect)
        }
        context.restoreGState()

        // Mark the exact sampled pixel with a device-pixel crosshair. The dark
        // under-stroke keeps the white marker legible over bright pixels.
        let devicePixel = 1 / (window?.backingScaleFactor ?? display.scale)
        let center = CGPoint(x: loupeRect.midX, y: loupeRect.midY)
        let arm: CGFloat = 7
        let marker = CGMutablePath()
        marker.move(to: CGPoint(x: center.x - arm, y: center.y))
        marker.addLine(to: CGPoint(x: center.x + arm, y: center.y))
        marker.move(to: CGPoint(x: center.x, y: center.y - arm))
        marker.addLine(to: CGPoint(x: center.x, y: center.y + arm))

        context.saveGState()
        context.addPath(marker)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(devicePixel * 3)
        context.strokePath()
        context.addPath(marker)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(devicePixel)
        context.strokePath()
        context.restoreGState()

        context.saveGState()
        context.addPath(clip)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(2)
        context.strokePath()
        context.restoreGState()
    }
}
