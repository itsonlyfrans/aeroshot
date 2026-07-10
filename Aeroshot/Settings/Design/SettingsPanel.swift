import SwiftUI

struct SettingsPanel<Content: View>: View {
    let title: String?
    let symbol: String?
    let tint: Color
    let content: Content

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        _ title: String? = nil,
        symbol: String? = nil,
        tint: Color = Color.secondary,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
            if title != nil || symbol != nil {
                header
            }

            VStack(alignment: .leading, spacing: SettingsTheme.spacingM) {
                content
            }
            .padding(.horizontal, SettingsTheme.spacingL)
            .padding(.vertical, SettingsTheme.spacingM)
            .background {
                RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.primary.opacity(isHovered ? 0.14 : 0.10),
                                Color.primary.opacity(isHovered ? 0.06 : 0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(
                color: Color.black.opacity(isHovered ? 0.05 : 0.03),
                radius: isHovered ? 12 : 8,
                x: 0,
                y: isHovered ? 6 : 4
            )
        }
        .onHover { hovering in
            SettingsTheme.animateHover(reducedMotion: reduceMotion) {
                isHovered = hovering
            }
        }
    }

    /// Quiet section label that lives outside the well, like macOS grouped settings.
    @ViewBuilder
    private var header: some View {
        HStack(spacing: SettingsTheme.spacingXS + 2) {
            if let symbol {
                Image(systemName: symbol)
                    .font(SettingsTheme.typeSmall(weight: .semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }

            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, SettingsTheme.spacingXS + 2)
    }
}

/// Chromeless section for meta-content (tips, related links) that shouldn't
/// carry the visual weight of a settings card.
struct SettingsFootnoteSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.tertiary)

            content
        }
        .padding(.horizontal, SettingsTheme.spacingS)
    }
}

/// Single lightweight tip line for footnote sections.
struct SettingsTipRow: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsTheme.spacingS) {
            Image(systemName: symbol)
                .font(SettingsTheme.typeSmall(weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Hairline separator that fades out toward the trailing edge.
struct SettingsSeparator: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.primary.opacity(0.10),
                Color.primary.opacity(0.02)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
        .accessibilityHidden(true)
    }
}
