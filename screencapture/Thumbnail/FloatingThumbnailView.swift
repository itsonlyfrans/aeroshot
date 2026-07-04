import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ThumbnailModel: ObservableObject {
    let image: CGImage
    let fileURL: URL?

    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onEdit: (() -> Void)?
    var onPin: (() -> Void)?
    var onOCR: (() -> Void)?
    var onClose: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    init(image: CGImage, fileURL: URL?) {
        self.image = image
        self.fileURL = fileURL
    }

    var nsImage: NSImage {
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

struct FloatingThumbnailView: View {
    @ObservedObject var model: ThumbnailModel
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: model.nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 260, maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.3), lineWidth: 1))
                    .onDrag {
                        if let url = model.fileURL {
                            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
                        }
                        let provider = NSItemProvider()
                        if let data = ImageExporter.data(for: model.image, format: .png) {
                            provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                                completion(data, nil)
                                return nil
                            }
                        }
                        return provider
                    }
                if hovering {
                    Button(action: { model.onClose?() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                }
            }
            if hovering {
                HStack(spacing: 10) {
                    actionButton("doc.on.doc", "Copy") { model.onCopy?() }
                    actionButton("square.and.arrow.down", "Save") { model.onSave?() }
                    actionButton("pencil.tip.crop.circle", "Edit") { model.onEdit?() }
                    actionButton("pin", "Pin") { model.onPin?() }
                    actionButton("text.viewfinder", "OCR") { model.onOCR?() }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onHover { h in
            hovering = h
            model.onHoverChanged?(h)
        }
        .animation(.easeInOut(duration: 0.15), value: hovering)
    }

    private func actionButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.bordered)
        .help(help)
    }
}
