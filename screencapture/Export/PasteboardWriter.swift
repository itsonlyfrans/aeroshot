import AppKit

enum PasteboardWriter {
    static func copy(image: CGImage) {
        let rep = NSBitmapImageRep(cgImage: image)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([nsImage])
    }

    static func copy(text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    static func copy(fileURL: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([fileURL as NSURL])
    }
}
