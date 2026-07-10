import SwiftUI

struct SettingsToggle: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool
    var symbol: String?

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var trackWidth: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var trackHeight: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var thumbSize: CGFloat = 18

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

                 ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? SettingsTheme.accent : Color.primary.opacity(0.12))
                        .frame(width: trackWidth, height: trackHeight)

                    Circle()
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                        .frame(width: thumbSize, height: thumbSize)
                        .padding(2)
                }
                .accessibilityHidden(true)
            }
            .padding(.horizontal, SettingsTheme.spacingS)
            .padding(.vertical, SettingsTheme.spacingS)
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: SettingsTheme.controlRadius - 2, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
