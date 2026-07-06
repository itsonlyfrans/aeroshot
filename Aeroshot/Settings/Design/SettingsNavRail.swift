import SwiftUI

struct SettingsNavRail: View {
    @Binding var selection: SettingsPane
    @Binding var searchQuery: String
    var searchFocus: FocusState<Bool>.Binding

    @Namespace private var navNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var searchResults: [SettingsSearchEntry] {
        SettingsSearchEntry.results(for: searchQuery)
    }

    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.spacingM) {
            VStack(alignment: .leading, spacing: SettingsTheme.spacingXS) {
                Text("Aeroshot")
                    .font(.headline.weight(.semibold))
                    .padding(.horizontal, SettingsTheme.spacingM)
                Text("Settings")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, SettingsTheme.spacingM)
            }

            SettingsSearchField(query: $searchQuery, focusBinding: searchFocus)
                .padding(.horizontal, SettingsTheme.spacingS)

            if isSearching {
                SettingsSearchResultsList(results: searchResults) { entry in
                    withAnimation(SettingsTheme.spring(reducedMotion: reduceMotion)) {
                        selection = entry.pane
                        searchQuery = ""
                        searchFocus.wrappedValue = false
                    }
                    SettingsTheme.performHaptic()
                }
                .padding(.horizontal, SettingsTheme.spacingS)
            } else {
                VStack(alignment: .leading, spacing: SettingsTheme.spacingXS) {
                    ForEach(SettingsPane.allCases) { pane in
                        navItem(pane)
                    }
                }
            }

            Spacer(minLength: 0)

            if !isSearching {
                Text("⌘F search · ⌘1–8 sections")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, SettingsTheme.spacingM)
            }
        }
        .padding(.top, 28)
        .padding(.bottom, SettingsTheme.spacingM)
        .frame(width: 196)
    }

    @ViewBuilder
    private func navItem(_ pane: SettingsPane) -> some View {
        let isSelected = selection == pane
        let needsAttention = pane.needsPermissionAttention

        Button {
            withAnimation(SettingsTheme.spring(reducedMotion: reduceMotion)) {
                selection = pane
            }
            SettingsTheme.performHaptic()
        } label: {
            HStack(spacing: SettingsTheme.spacingS) {
                Image(systemName: pane.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)

                Text(pane.title)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.85))

                Spacer(minLength: 0)

                if needsAttention && !isSelected {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }

                if !isSelected {
                    Text(pane.keyboardShortcut.character)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, SettingsTheme.spacingM)
            .padding(.vertical, SettingsTheme.spacingS + 2)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .matchedGeometryEffect(id: "navSelection", in: navNamespace)
                        .shadow(color: Color.accentColor.opacity(0.25), radius: 4, x: 0, y: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, SettingsTheme.spacingS)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(needsAttention ? "Attention needed" : pane.subtitle)
    }
}

private extension KeyEquivalent {
    var character: String {
        switch self {
        case "1": return "⌘1"
        case "2": return "⌘2"
        case "3": return "⌘3"
        case "4": return "⌘4"
        case "5": return "⌘5"
        case "6": return "⌘6"
        case "7": return "⌘7"
        case "8": return "⌘8"
        default: return ""
        }
    }
}
