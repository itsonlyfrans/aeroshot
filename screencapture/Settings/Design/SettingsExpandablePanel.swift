import SwiftUI

struct SettingsExpandablePanel<Content: View>: View {
    let title: String
    let subtitle: String?
    @Binding var isExpanded: Bool
    let content: Content

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
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isExpanded ? "Collapse section" : "Expand section")

            if isExpanded {
                content
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
