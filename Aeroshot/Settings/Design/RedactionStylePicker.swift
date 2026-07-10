import SwiftUI

/// Three preview cards for the Share Safe redaction style, each rendering its
/// effect on a tiny mock screenshot so the tradeoff is visible at a glance.
struct RedactionStylePicker: View {
    @Binding var selection: ShareSafeRedactionStyle

    var body: some View {
        HStack(spacing: SettingsTheme.spacingM) {
            ForEach(ShareSafeRedactionStyle.allCases) { style in
                RedactionStyleCard(
                    style: style,
                    isSelected: selection == style
                ) {
                    selection = style
                    SettingsTheme.performHaptic()
                }
            }
        }
    }
}

private extension ShareSafeRedactionStyle {
    var caption: String {
        switch self {
        case .blur: return "Reversible-looking, softest"
        case .pixelate: return "Obscures while keeping shape"
        case .solid: return "Solid black, cannot be recovered"
        }
    }
}

private struct RedactionStyleCard: View {
    let style: ShareSafeRedactionStyle
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
                RedactionPreviewMock(style: style)
                    .frame(maxWidth: .infinity)

                Text(style.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(style.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(SettingsTheme.spacingM)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous)
                    .fill(isSelected || isHovered ? SettingsTheme.fillHover : SettingsTheme.fillRest)
            }
            .overlay {
                RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? SettingsTheme.borderAccentSelected : SettingsTheme.borderSubtle,
                        lineWidth: isSelected ? AeroTokens.Stroke.accentSelectedWidth : 0.5
                    )
            }
            .scaleEffect(isHovered && !isSelected && !reduceMotion ? 1.01 : 1)
            .animation(SettingsTheme.spring(reducedMotion: reduceMotion), value: isHovered)
            .animation(SettingsTheme.spring(reducedMotion: reduceMotion), value: isSelected)
        }
        .buttonStyle(AeroPressableStyle())
        .accessibilityLabel("\(style.displayName), \(style.caption)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .onHover { hovering in
            SettingsTheme.animateHover(reducedMotion: reduceMotion) {
                isHovered = hovering
            }
        }
    }
}

/// A tiny mock screenshot: two plain "text lines" plus one sensitive line
/// drawn with the given redaction effect. Pure shapes, so it adapts to both
/// color schemes via `.primary` opacities.
private struct RedactionPreviewMock: View {
    let style: ShareSafeRedactionStyle

    private let lineHeight: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            textLine(widthFraction: 0.85)
            sensitiveLine
            textLine(widthFraction: 0.6)
        }
        .padding(10)
        .frame(width: 96, height: 56, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: AeroTokens.Radius.small, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: AeroTokens.Radius.small, style: .continuous)
                .strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private func textLine(widthFraction: CGFloat) -> some View {
        Capsule()
            .fill(Color.primary.opacity(0.22))
            .frame(width: 76 * widthFraction, height: lineHeight)
    }

    @ViewBuilder
    private var sensitiveLine: some View {
        switch style {
        case .blur:
            Capsule()
                .fill(SettingsTheme.warning.opacity(0.8))
                .frame(width: 56, height: lineHeight)
                .blur(radius: 3)
        case .pixelate:
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(SettingsTheme.warning.opacity(index.isMultiple(of: 2) ? 0.75 : 0.45))
                        .frame(width: lineHeight, height: lineHeight)
                }
            }
        case .solid:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.black)
                .frame(width: 56, height: lineHeight)
        }
    }
}
