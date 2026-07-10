import SwiftUI

struct SettingsExpandablePanel<Content: View>: View {
    let title: String
    let subtitle: String?
    @Binding var isExpanded: Bool
    let content: Content

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        _ title: String,
        subtitle: String? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        SettingsPanel {
            Button {
                withAnimation(SettingsTheme.spring(reducedMotion: reduceMotion)) {
                    isExpanded.toggle()
                }
                SettingsTheme.performHaptic()
            } label: {
                HStack(spacing: SettingsTheme.spacingS) {
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
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(SettingsTheme.typeSmall(weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, SettingsTheme.spacingXS)
                .padding(.vertical, SettingsTheme.spacingXS)
                .background {
                    if isHovered {
                        RoundedRectangle(cornerRadius: AeroTokens.Radius.small, style: .continuous)
                            .fill(SettingsTheme.fillHover)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(AeroPressableStyle())
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isExpanded ? "Collapse section" : "Expand section")
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
