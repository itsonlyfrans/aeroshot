import AppKit

/// Pixel loupe that samples the frozen pre-capture image so what the user
/// sees magnified is exactly what will be captured.
final class MagnifierView: NSView {

    private let frozenImage: CGImage?
    private let display: DisplayInfo
    private let loupeSize: CGFloat = 120
    private let zoom: CGFloat = 8

    private var samplePixel: CGPoint = .zero  // pixel coords in frozen image (top-left origin)

    init(frozenImage: CGImage?, display: DisplayInfo) {
        self.frozenImage = frozenImage
        self.display = display
        super.init(frame: CGRect(x: 0, y: 0, width: loupeSize, height: loupeSize + 18))
        wantsLayer = true
        isHidden = frozenImage == nil
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `cursorLocal` is in the parent overlay view's coordinates
    /// (bottom-left origin, one view per screen covering the whole screen).
    func update(cursorLocal: NSPoint, in parent: NSView) {
        guard frozenImage != nil else { return }
        // Frozen image is the full display at pixel resolution, top-left origin.
        let px = cursorLocal.x * display.scale
        let py = (parent.bounds.height - cursorLocal.y) * display.scale
        samplePixel = CGPoint(x: px, y: py)

        // Position the loupe near the cursor, flipping to stay on screen.
        var origin = NSPoint(x: cursorLocal.x + 20, y: cursorLocal.y + 20)
        if origin.x + frame.width > parent.bounds.width { origin.x = cursorLocal.x - frame.width - 20 }
        if origin.y + frame.height > parent.bounds.height { origin.y = cursorLocal.y - frame.height - 20 }
        setFrameOrigin(origin)
        isHidden = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let frozenImage else { return }

        let loupeRect = CGRect(x: 0, y: 18, width: loupeSize, height: loupeSize)
        let clip = CGPath(ellipseIn: loupeRect, transform: nil)

        ctx.saveGState()
        ctx.addPath(clip)
        ctx.clip()
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(loupeRect)

        // Sample region in image pixels centered on the cursor.
        let sidePx = loupeSize / zoom * display.scale
        let sample = CGRect(x: samplePixel.x - sidePx / 2, y: samplePixel.y - sidePx / 2,
                            width: sidePx, height: sidePx)
        if let cropped = frozenImage.cropping(to: sample.integral) {
            ctx.interpolationQuality = .none
            // Flip vertically: CG image is top-left origin, view is bottom-left.
            ctx.saveGState()
            ctx.translateBy(x: 0, y: loupeRect.maxY + loupeRect.minY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cropped, in: loupeRect)
            ctx.restoreGState()
        }

        // Center pixel crosshair.
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
        ctx.setLineWidth(0.5)
        ctx.strokeLineSegments(between: [
            CGPoint(x: loupeRect.midX - 14, y: loupeRect.midY), CGPoint(x: loupeRect.midX + 14, y: loupeRect.midY),
            CGPoint(x: loupeRect.midX, y: loupeRect.midY - 14), CGPoint(x: loupeRect.midX, y: loupeRect.midY + 14)
        ])

        ctx.setStrokeColor(NSColor.systemYellow.cgColor)
        ctx.setLineWidth(1)
        let c = CGPoint(x: loupeRect.midX, y: loupeRect.midY)
        let ps = zoom / display.scale
        ctx.stroke(CGRect(x: c.x - ps / 2, y: c.y - ps / 2, width: ps, height: ps))
        ctx.restoreGState()

        // Bezel ring outline
        ctx.saveGState()
        ctx.addPath(clip)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2.5)
        ctx.strokePath()
        
        let clipInset = CGPath(ellipseIn: loupeRect.insetBy(dx: 1.25, dy: 1.25), transform: nil)
        ctx.addPath(clipInset)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.12).cgColor)
        ctx.setLineWidth(0.75)
        ctx.strokePath()
        ctx.restoreGState()

        // Coordinate readout in custom translucent capsule
        let text = "\(Int(samplePixel.x)) × \(Int(samplePixel.y))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let labelOrigin = NSPoint(x: (bounds.width - size.width) / 2, y: 2)
        let labelBg = CGRect(x: labelOrigin.x - 8, y: labelOrigin.y - 2.5, width: size.width + 16, height: size.height + 5)
        
        ctx.saveGState()
        ctx.setFillColor(NSColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 0.85).cgColor)
        ctx.addPath(CGPath(roundedRect: labelBg, cornerWidth: 5, cornerHeight: 5, transform: nil))
        ctx.fillPath()
        
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.15).cgColor)
        ctx.setLineWidth(0.5)
        ctx.addPath(CGPath(roundedRect: labelBg.insetBy(dx: 0.25, dy: 0.25), cornerWidth: 5, cornerHeight: 5, transform: nil))
        ctx.strokePath()
        ctx.restoreGState()
        
        str.draw(at: labelOrigin)
    }
}
