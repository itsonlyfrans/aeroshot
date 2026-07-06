import SwiftUI

struct SettingsPaneLayout<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SettingsTheme.spacingL)
        }
        .scrollIndicators(.automatic)
    }
}

struct SettingsStatCard: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(SettingsTheme.spacingM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
    }
}

struct SettingsJumpCard: View {
    let pane: SettingsPane
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: SettingsTheme.spacingM) {
                Image(systemName: pane.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(pane.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(pane.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .offset(x: isHovered ? 2 : 0)
            }
            .padding(SettingsTheme.spacingM)
            .background {
                RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.05) : Color.primary.opacity(0.025))
            }
            .overlay {
                RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.10 : 0.06), lineWidth: 0.5)
            }
            .scaleEffect(isHovered && !reduceMotion ? 1.01 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct SettingsQuickLink: View {
    let title: String
    let subtitle: String
    let pane: SettingsPane

    @Environment(\.settingsNavigate) private var navigate
    @State private var isHovered = false

    var body: some View {
        Button {
            SettingsTheme.performHaptic()
            navigate(pane)
        } label: {
            HStack(spacing: SettingsTheme.spacingM) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text(pane.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
                .opacity(isHovered ? 1 : 0.7)
            }
            .padding(.vertical, SettingsTheme.spacingXS)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
