import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ThumbnailModel: ObservableObject {
    let image: CGImage
    let fileURL: URL?
    let isPrivacyScanPending: Bool
    var visibleActions: [ThumbnailAction] = ThumbnailAction.defaultVisibleActions
    var availableActions: [ThumbnailAction] = ThumbnailAction.allCases

    var onAction: ((ThumbnailAction) -> Void)?
    var onClose: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    init(image: CGImage, fileURL: URL?, isPrivacyScanPending: Bool = false) {
        self.image = image
        self.fileURL = fileURL
        self.isPrivacyScanPending = isPrivacyScanPending
    }

    var nsImage: NSImage {
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

/// Slate & Coral after-capture overlay. The capture stays readable at rest;
/// hover reveals a compact action rail without obscuring the image.
struct FloatingThumbnailView: View {
    @ObservedObject var model: ThumbnailModel
    var showActionsAlways: Bool = false

    @State private var hovering = false
    @State private var hoveredAction: String?
    @State private var isShareSafeScanning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showActions: Bool {
        showActionsAlways || hovering
    }
    private var overflowActions: [ThumbnailAction] {
        model.availableActions.filter { !model.visibleActions.contains($0) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: AeroTokens.Spacing.small) {
            captureCard

            ZStack(alignment: .top) {
                Color.clear.frame(width: 34, height: 194)
                if showActions {
                    actionRail
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .leading)))
                }
            }
        }
        .padding(2)
        .onHover { isHovering in
            hovering = isHovering
            model.onHoverChanged?(isHovering)
        }
        .animation(
            AeroTokens.Motion.resolved(AeroTokens.Motion.spring, reduceMotion: reduceMotion),
            value: hovering
        )
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            ForEach(model.availableActions) { action in
                Button(action.title) { trigger(action) }
                    .disabled(model.isPrivacyScanPending)
            }
            Button("Dismiss") { model.onClose?() }
        }
    }

    private var captureCard: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.92)
                Image(nsImage: model.nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 260, height: 160)

                Text("\(model.image.width)×\(model.image.height)")
                    .font(AeroTokens.Typography.micro(weight: .semibold, design: .monospaced))
                    .foregroundStyle(SettingsTheme.accent.opacity(0.9))
                    .padding(.horizontal, AeroTokens.Spacing.small)
                    .padding(.vertical, AeroTokens.Spacing.xs)
                    .background(AeroTokens.ColorRole.onAccent.opacity(0.86), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(AeroTokens.Spacing.small)
            }

            HStack(spacing: AeroTokens.Spacing.small) {
                if model.isPrivacyScanPending {
                    ProgressView()
                        .controlSize(.small)
                        .tint(SettingsTheme.accent)
                    Text("Checking sensitive data…")
                        .font(AeroTokens.Typography.small(weight: .medium))
                } else {
                    Circle()
                        .fill(SettingsTheme.accent)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text("Area capture")
                        .font(AeroTokens.Typography.small(weight: .medium))
                }
                Spacer(minLength: AeroTokens.Spacing.small)
                Text(fileSummary)
                    .font(AeroTokens.Typography.micro(design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, AeroTokens.Spacing.medium)
            .frame(height: 34)
            .background(.regularMaterial)
        }
        .frame(width: 260, height: 194)
        .clipShape(RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous)
                .strokeBorder(SettingsTheme.accent.opacity(hovering ? 0.55 : 0.28), lineWidth: hovering ? 1 : 0.5)
        }
        .shadow(color: .black.opacity(0.42), radius: 18, y: 9)
    }

    private var actionRail: some View {
        VStack(spacing: AeroTokens.Spacing.xs) {
            ForEach(model.visibleActions) { action in
                actionButton(action)
            }

            Menu {
                ForEach(overflowActions) { action in
                    Button { trigger(action) } label: {
                        Label(action.title, systemImage: action.symbol)
                    }
                }
                if !overflowActions.isEmpty { Divider() }
                Button("Dismiss", systemImage: "xmark", role: .cancel) {
                    model.onClose?()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AeroTokens.ColorRole.onAccent)
                    .frame(width: 34, height: 34)
                    .background(SettingsTheme.accent, in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
            }
            .menuStyle(.button)
            .buttonStyle(AeroPressableStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(model.isPrivacyScanPending)
            .help("More actions")
            .accessibilityLabel("More thumbnail actions")
        }
        .padding(AeroTokens.Spacing.xs)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous)
                .strokeBorder(SettingsTheme.borderSubtle, lineWidth: AeroTokens.Stroke.hairlineWidth)
        }
        .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
    }

    private func actionButton(_ action: ThumbnailAction) -> some View {
        let actionID = action.rawValue
        return Button { trigger(action) } label: {
            Image(systemName: action.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(hoveredAction == actionID ? SettingsTheme.accent : Color.secondary)
                .frame(width: 34, height: 34)
                .background(
                    hoveredAction == actionID ? SettingsTheme.accent.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                )
        }
        .buttonStyle(AeroPressableStyle())
        .disabled(model.isPrivacyScanPending)
        .help(action.title)
        .accessibilityLabel(action.title)
        .onHover { over in
            withAnimation(AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion)) {
                hoveredAction = over ? actionID : nil
            }
        }
    }

    private var fileSummary: String {
        let ext = model.fileURL?.pathExtension.uppercased()
        let bytes = model.fileURL.flatMap {
            try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize
        }
        let size = bytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
        return [size, ext].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "PNG"
    }

    private func trigger(_ action: ThumbnailAction) {
        guard !model.isPrivacyScanPending else { return }
        guard model.availableActions.contains(action) else { return }
        guard action != .shareSafe || !isShareSafeScanning else { return }
        if action == .shareSafe {
            isShareSafeScanning = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isShareSafeScanning = false }
        }
        model.onAction?(action)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
