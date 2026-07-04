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
    @State private var hoveredAction: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: model.nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 260, maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
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
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.15)) {
                            model.onClose?()
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Color.black.opacity(0.65), in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            
            if hovering {
                HStack(spacing: 8) {
                    actionButton("doc.on.doc", "Copy", actionID: "copy") { model.onCopy?() }
                    actionButton("square.and.arrow.down", "Save", actionID: "save") { model.onSave?() }
                    actionButton("pencil.tip.crop.circle", "Edit", actionID: "edit") { model.onEdit?() }
                    actionButton("pin", "Pin", actionID: "pin") { model.onPin?() }
                    actionButton("text.viewfinder", "OCR", actionID: "ocr") { model.onOCR?() }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(.regularMaterial)
                        .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
                        .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1.5)
                )
                .padding(.bottom, 2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                )
        )
        .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 5)
        .onHover { h in
            hovering = h
            model.onHoverChanged?(h)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: hovering)
    }

    private func actionButton(_ symbol: String, _ help: String, actionID: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(hoveredAction == actionID ? Color.white : Color.primary.opacity(0.8))
                .frame(width: 32, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hoveredAction == actionID ? Color.accentColor : Color.clear)
                )
                .scaleEffect(hoveredAction == actionID ? 1.08 : 1.0)
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { over in
            hoveredAction = over ? actionID : nil
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: hoveredAction)
    }
}
