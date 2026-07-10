import SwiftUI

/// A compact summary row with a status pill that discloses its content —
/// used to collapse healthy groups (e.g. Permissions) into one calm line.
struct SettingsDisclosureRow<Content: View>: View {
    let title: String
    let subtitle: String?
    let badgeText: String
    let badgeTone: SettingsStatusBadge.Tone
    @Binding var isExpanded: Bool
    let content: Content

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        subtitle: String? = nil,
        badgeText: String,
        badgeTone: SettingsStatusBadge.Tone,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.badgeText = badgeText
        self.badgeTone = badgeTone
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.spacingM) {
            Button {
                withAnimation(SettingsTheme.spring(reducedMotion: reduceMotion)) {
                    isExpanded.toggle()
                }
                SettingsTheme.performHaptic()
            } label: {
                HStack(spacing: SettingsTheme.spacingM) {
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

                    SettingsStatusBadge(text: badgeText, tone: badgeTone)

                    Image(systemName: "chevron.right")
                        .font(SettingsTheme.typeSmall(weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
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
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(title), \(badgeText)")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .onHover { hovering in
                SettingsTheme.animateHover(reducedMotion: reduceMotion) {
                    isHovered = hovering
                }
            }

            if isExpanded {
                content
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
