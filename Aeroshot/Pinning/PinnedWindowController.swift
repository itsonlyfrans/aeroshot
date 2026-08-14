import AppKit

/// Manages "pinned" screenshots: borderless floating panels that stay above
/// everything, draggable anywhere, scroll to resize, ⌥scroll for opacity,
/// ⌘W / Esc / double-click to close.
@MainActor
final class PinnedWindowController {
    private var pins: [PinPanel] = []

    func pin(image: CGImage, sourceScale: CGFloat = 1) {
        addPin(PinPanel(image: image, sourceScale: sourceScale, placement: .centered))
    }

    func pinThumbnailInCorner(image: CGImage, sourceScale: CGFloat = 1) {
        addPin(PinPanel(image: image, sourceScale: sourceScale, placement: .thumbnailCorner))
    }

    private func addPin(_ panel: PinPanel) {
        panel.onClose = { [weak self, weak panel] in
            guard let panel else { return }
            self?.pins.removeAll { $0 === panel }
        }
        pins.append(panel)
        panel.orderFrontRegardless()
    }
}

final class PinPanel: NSPanel {
    enum Placement: Equatable {
        case centered
        case thumbnailCorner
    }

    var onClose: (() -> Void)?

    private let image: CGImage
    private let aspect: CGFloat
    private var currentOpacity: CGFloat = 1.0

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(image: CGImage, sourceScale: CGFloat = 1, placement: Placement = .centered) {
        self.image = image
        self.aspect = CGFloat(image.height) / CGFloat(image.width)

        let mouse = NSEvent.mouseLocation
        let screen = placement == .thumbnailCorner
            ? (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main)
            : NSScreen.main
        let scale = sourceScale.isFinite && sourceScale > 0 ? sourceScale : 1
        var width = CGFloat(image.width) / scale
        var height = CGFloat(image.height) / scale
        if let vf = screen?.visibleFrame {
            let maxW = placement == .thumbnailCorner ? min(260, vf.width * 0.32) : vf.width * 0.6
            let maxH = placement == .thumbnailCorner ? min(194, vf.height * 0.32) : vf.height * 0.6
            let ratio = min(1, maxW / width, maxH / height)
            width *= ratio
            height *= ratio
        }
        let origin = screen.map { screen in
            switch placement {
            case .centered:
                return NSPoint(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.midY - height / 2)
            case .thumbnailCorner:
                return NSPoint(x: screen.visibleFrame.minX + 20, y: screen.visibleFrame.minY + 20)
            }
        } ?? .zero
        super.init(contentRect: CGRect(origin: origin, size: CGSize(width: width, height: height)),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let imageView = PinImageView(frame: .zero)
        imageView.onClose = { [weak self] in self?.closePin() }
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

private final class PinImageView: NSImageView {
    var onClose: (() -> Void)?

    private lazy var closeButton: NSButton = {
        let button = NSButton(
            image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close pinned image") ?? NSImage(),
            target: self,
            action: #selector(closePressed)
        )
        button.isBordered = false
        button.contentTintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        button.toolTip = "Close pinned image"
        return button
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { true }

    @objc private func closePressed() {
        onClose?()
    }
}
