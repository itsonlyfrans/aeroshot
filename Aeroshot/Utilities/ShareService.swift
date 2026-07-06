import AppKit

enum ShareService {
    @MainActor
    static func share(items: [Any], from view: NSView?) {
        guard !items.isEmpty else { return }
        let picker = NSSharingServicePicker(items: items)
        if let view {
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            return
        }
        if let anchor = NSApp.keyWindow?.contentView {
            picker.show(relativeTo: .zero, of: anchor, preferredEdge: .minY)
        }
    }

    @MainActor
    static func shareFile(at url: URL, from view: NSView?) {
        share(items: [url], from: view)
    }

    @MainActor
    static func shareImage(_ image: CGImage, fileURL: URL?, from view: NSView?) {
        if let fileURL {
            share(items: [fileURL], from: view)
            return
        }
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        share(items: [nsImage], from: view)
    }

    @MainActor
    static func shareText(_ text: String, from view: NSView?) {
        share(items: [text], from: view)
    }
}
