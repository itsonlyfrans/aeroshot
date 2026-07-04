import SwiftUI

struct SettingsToggle: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool
    var symbol: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var trackWidth: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var trackHeight: CGFloat = 26
    @ScaledMetric(relativeTo: .body) private var thumbSize: CGFloat = 20

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
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                        .frame(width: 24)
                        .symbolEffect(.bounce, value: isOn)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: SettingsTheme.spacingM)

                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? Color.accentColor : Color.primary.opacity(0.12))
                        .frame(width: trackWidth, height: trackHeight)

                    Circle()
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
                        .frame(width: thumbSize, height: thumbSize)
                        .padding(3)
                }
                .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(subtitle ?? "Double tap to toggle")
        .padding(.vertical, SettingsTheme.spacingXS)
    }
}
