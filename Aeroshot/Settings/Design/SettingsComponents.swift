import SwiftUI

// MARK: - Section labels

/// Outside-panel section label matching SettingsPanel header styling.
struct SettingsSectionLabel: View {
    let title: String
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: SettingsTheme.spacingXS + 2) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: SettingsTheme.iconSizeSmall, weight: .semibold))
                    .foregroundStyle(SettingsTheme.accent)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, SettingsTheme.spacingXS + 2)
    }
}

/// In-panel subsection title with optional description.
struct SettingsSubsectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(compact ? .subheadline.weight(.medium) : .headline)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Badges & keycaps

struct SettingsStatusBadge: View {
    enum Tone {
        case success, warning, accent

        var color: Color {
            switch self {
            case .success: return SettingsTheme.success
            case .warning: return SettingsTheme.warning
            case .accent: return SettingsTheme.accent
            }
        }
    }

    let text: String
    var tone: Tone = .accent

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(tone.color)
            .padding(.horizontal, SettingsTheme.spacingS)
            .padding(.vertical, SettingsTheme.spacingXS)
            .background(tone.color.opacity(0.12), in: Capsule())
    }
}

/// Keyboard shortcut badge used in settings and onboarding.
struct SettingsKeycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(SettingsTheme.typeSmall(weight: .semibold, design: .rounded))
            .foregroundStyle(.primary.opacity(0.8))
            .padding(.horizontal, SettingsTheme.spacingS)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
    }
}

typealias OnboardingKeycap = SettingsKeycap

// MARK: - Rows

struct SettingsShortcutRow: View {
    let symbol: String
    let title: String
    let keycap: String

    var body: some View {
        HStack(spacing: SettingsTheme.spacingM) {
            Image(systemName: symbol)
                .font(.system(size: SettingsTheme.iconSizeMedium, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: SettingsTheme.iconColumnWidth)

            Text(title)
                .font(.body.weight(.medium))

            Spacer(minLength: 0)

            SettingsKeycap(text: keycap)
        }
        .padding(.vertical, SettingsTheme.spacingXS)
    }
}

// MARK: - Selection cards

struct SettingsSelectionCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
                Image(systemName: symbol)
                    .font(.title2.weight(.medium))
                    .foregroundStyle(SettingsTheme.accent)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(SettingsTheme.spacingM)
            .frame(maxWidth: .infinity, minHeight: SettingsTheme.selectionCardMinHeight, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous)
                    .fill(
                        Color.primary.opacity(isSelected ? 0.08 : (isHovered ? 0.06 : 0.04))
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? SettingsTheme.accent.opacity(0.6) : SettingsTheme.borderSubtle,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            }
            .scaleEffect(isHovered && !isSelected && !reduceMotion ? 1.01 : 1)
            .animation(SettingsTheme.spring(reducedMotion: reduceMotion), value: isHovered)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .onHover { hovering in
            SettingsTheme.animateHover(reducedMotion: reduceMotion) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Surfaces

struct SettingsMaterialCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(SettingsTheme.spacingM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous)
                    .strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5)
            }
    }
}

struct SettingsLinkButton: View {
    let title: String
    var symbol: String? = nil
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: SettingsTheme.spacingXS + 2) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: SettingsTheme.iconSizeSmall, weight: .semibold))
                }
                Text(title)
                    .font(.callout.weight(.medium))
            }
            .foregroundStyle(SettingsTheme.accent.opacity(isHovered ? 1 : 0.85))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            SettingsTheme.animateHover(reducedMotion: reduceMotion) {
                isHovered = hovering
            }
        }
    }
}
