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
                        isHovered ? SettingsTheme.borderHover : SettingsTheme.borderSubtle,
                        lineWidth: AeroTokens.Stroke.hairlineWidth
                    )
            }
            .shadow(
                color: Color.black.opacity(AeroTokens.Elevation.card.opacity),
                radius: AeroTokens.Elevation.card.radius,
                x: AeroTokens.Elevation.card.x,
                y: AeroTokens.Elevation.card.y
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

/// Flat hairline separator — one border language app-wide, no gradients.
struct SettingsSeparator: View {
    var body: some View {
        Rectangle()
            .fill(SettingsTheme.borderSubtle)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}
