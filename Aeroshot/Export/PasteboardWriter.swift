import AppKit
import UniformTypeIdentifiers

enum PasteboardWriter {
    /// Copies `image` to the general pasteboard as PNG/TIFF (and optionally a saved file URL).
    @discardableResult
    static func copy(
        image: CGImage,
        pngData: Data? = nil,
        fileURL: URL? = nil,
        sourceScale: CGFloat = 1,
        pasteboard: NSPasteboard = .general
    ) -> Bool {
        let scale = sourceScale.isFinite && sourceScale > 0 ? sourceScale : 1
        guard let pngData = pngData ?? ImageExporter.data(for: image, format: .png, scale: scale) else { return false }
        let bitmap = NSBitmapImageRep(cgImage: image)
        bitmap.size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let tiffData = bitmap.tiffRepresentation

        // Menu-bar (LSUIElement) apps must be active when publishing or paste targets won't see data.
        NSApp.activate(ignoringOtherApps: true)

        pasteboard.clearContents()

        var types: [NSPasteboard.PasteboardType] = [
            .png,
            NSPasteboard.PasteboardType(UTType.png.identifier),
            .tiff,
        ]
        if fileURL != nil {
            types.append(.fileURL)
        }
        pasteboard.declareTypes(types, owner: nil)

        var ok = pasteboard.setData(pngData, forType: .png)
        ok = pasteboard.setData(pngData, forType: NSPasteboard.PasteboardType(UTType.png.identifier)) || ok
        if let tiffData {
            ok = pasteboard.setData(tiffData, forType: .tiff) || ok
        }
        if let fileURL {
            ok = pasteboard.setData(fileURL.dataRepresentation, forType: .fileURL) || ok
        }

        return ok && pasteboard.data(forType: .png) != nil
    }

    static func copy(text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    static func copy(fileURL: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([fileURL as NSURL])
    }
}
