import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ThumbnailModel: ObservableObject {
    let image: CGImage
    let fileURL: URL?
    var visibleActions: [ThumbnailAction] = ThumbnailAction.defaultVisibleActions
    var availableActions: [ThumbnailAction] = ThumbnailAction.allCases

    var onAction: ((ThumbnailAction) -> Void)?
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
    var showActionsAlways: Bool = false
    @State private var hovering = false
    @State private var hoveredAction: String? = nil
    @State private var isShareSafeScanning = false
    @State private var dragOffset: CGSize = .zero

    private var showActions: Bool {
        showActionsAlways || hovering
    }

    private var overflowActions: [ThumbnailAction] {
        model.availableActions.filter { !model.visibleActions.contains($0) }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: model.nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 260, maxHeight: 180)
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

            if showActions {
                Button { model.onClose?() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(.black.opacity(0.66), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(7)
                .help("Dismiss thumbnail")
                .accessibilityLabel("Dismiss thumbnail")

                VStack {
                    Spacer(minLength: 0)
                    HStack(spacing: 3) {
                        ForEach(model.visibleActions) { action in actionButton(action) }
                        if !overflowActions.isEmpty {
                            Menu {
                                ForEach(overflowActions) { action in
                                    Button { trigger(action) } label: { Label(action.title, systemImage: action.symbol) }
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(hoveredAction == "overflow" ? Color.white : Color.primary.opacity(0.78))
                                    .frame(width: 30, height: 28)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(hoveredAction == "overflow" ? Color.accentColor : Color.clear)
                                    )
                            }
                            .menuStyle(.button)
                            .buttonStyle(.plain)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .help("More actions")
                            .accessibilityLabel("More thumbnail actions")
                            .onHover { hoveredAction = $0 ? "overflow" : nil }
                        }
                    }
                    .padding(3)
                    .background(.black.opacity(0.66), in: Capsule())
                    .padding(7)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AeroTheme.strokeHairline, lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.32), radius: 12, x: 0, y: 6)
        .offset(dragOffset)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    dragOffset = CGSize(width: value.translation.width, height: value.translation.height * 0.15)
                }
                .onEnded { value in
                    if abs(value.translation.width) > 88 {
                        model.onClose?()
                    }
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                        dragOffset = .zero
                    }
                }
        )
        .onHover { h in
            hovering = h
            model.onHoverChanged?(h)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: hovering)
    }

    private func actionButton(_ action: ThumbnailAction) -> some View {
        let actionID = action.rawValue
        return Button { trigger(action) } label: {
            Image(systemName: action.symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(hoveredAction == actionID ? Color.white : (action == .edit ? Color.accentColor : Color.primary.opacity(0.78)))
                .frame(width: 32, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hoveredAction == actionID ? Color.accentColor : (action == .edit ? Color.accentColor.opacity(0.12) : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .help(action.title)
        .accessibilityLabel(action.title)
        .onHover { over in
            hoveredAction = over ? actionID : nil
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: hoveredAction)
    }

    private func trigger(_ action: ThumbnailAction) {
        guard action != .shareSafe || !isShareSafeScanning else { return }
        if action == .shareSafe {
            isShareSafeScanning = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isShareSafeScanning = false }
        }
        model.onAction?(action)
    }
}
