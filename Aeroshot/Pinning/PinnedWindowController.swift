import AppKit

/// Manages "pinned" screenshots: borderless floating panels that stay above
/// everything, draggable anywhere, scroll to resize, ⌥scroll for opacity,
/// ⌘W / Esc / double-click to close.
@MainActor
final class PinnedWindowController {
    private var pins: [PinPanel] = []

    func pin(image: CGImage) {
        let panel = PinPanel(image: image)
        panel.onClose = { [weak self, weak panel] in
            guard let panel else { return }
            self?.pins.removeAll { $0 === panel }
        }
        pins.append(panel)
        panel.orderFrontRegardless()
    }
}

final class PinPanel: NSPanel {
    var onClose: (() -> Void)?

    private let image: CGImage
    private let aspect: CGFloat
    private var currentOpacity: CGFloat = 1.0

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(image: CGImage) {
        self.image = image
        self.aspect = CGFloat(image.height) / CGFloat(image.width)

        // Start at half the pixel size, capped to 60% of the screen.
        let screen = NSScreen.main
        let scale = screen?.backingScaleFactor ?? 2
        var width = CGFloat(image.width) / scale
        var height = CGFloat(image.height) / scale
        if let vf = screen?.visibleFrame {
            let maxW = vf.width * 0.6, maxH = vf.height * 0.6
            let ratio = min(1, maxW / width, maxH / height)
            width *= ratio
            height *= ratio
        }
        let origin = screen.map { NSPoint(x: $0.visibleFrame.midX - width / 2, y: $0.visibleFrame.midY - height / 2) } ?? .zero
        super.init(contentRect: CGRect(origin: origin, size: CGSize(width: width, height: height)),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let imageView = NSImageView()
        imageView.image = NSImage(cgImage: image, size: NSSize(width: width, height: height))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 1
        imageView.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        contentView = imageView
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            currentOpacity = min(1, max(0.15, currentOpacity + event.scrollingDeltaY * 0.01))
            alphaValue = currentOpacity
        } else {
            let factor = 1 + event.scrollingDeltaY * 0.005
            var f = frame
            let newWidth = min(max(f.width * factor, 80), 4000)
            let newHeight = newWidth * aspect
            // Resize around the center.
            f.origin.x -= (newWidth - f.width) / 2
            f.origin.y -= (newHeight - f.height) / 2
            f.size = CGSize(width: newWidth, height: newHeight)
            setFrame(f, display: true)
        }
    }

    override func keyDown(with event: NSEvent) {
        let isCmdW = event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "w"
        if event.keyCode == 53 || isCmdW {
            closePin()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            closePin()
            return
        }
        super.mouseDown(with: event)
    }

    private func closePin() {
        orderOut(nil)
        onClose?()
    }
}
