import SwiftUI

/// Full toggle row (icon, title, subtitle, switch) with row hover.
/// Shared app-wide; the bare switch is `AeroSwitchKnob`.
struct AeroToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool
    var symbol: String?

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(SettingsTheme.spring(reducedMotion: reduceMotion)) {
                isOn.toggle()
            }
            SettingsTheme.performHaptic()
        } label: {
            HStack(alignment: .center, spacing: SettingsTheme.spacingM) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                        .symbolEffect(.bounce, value: isOn)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: SettingsTheme.spacingM)

                AeroSwitchKnob(isOn: isOn)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, SettingsTheme.spacingS)
            .padding(.vertical, SettingsTheme.spacingS)
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: AeroTokens.Radius.small, style: .continuous)
                        .fill(SettingsTheme.fillHover)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(AeroPressableStyle())
        .padding(.horizontal, -SettingsTheme.spacingS)
        .onHover { hovering in
            SettingsTheme.animateHover(reducedMotion: reduceMotion) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(subtitle ?? "Double tap to toggle")
    }
}

typealias SettingsToggle = AeroToggleRow
