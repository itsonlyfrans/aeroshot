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
                    ForEach(SettingsPane.navGroups, id: \.title) { group in
                        if !group.title.isEmpty {
                            Text(group.title.uppercased())
                                .font(.caption2.weight(.semibold))
                                .tracking(0.8)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, SettingsTheme.spacingM + SettingsTheme.spacingS)
                                .padding(.top, SettingsTheme.spacingS + 2)
                        }
                        ForEach(group.panes) { pane in
                            navItem(pane)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if !isSearching {
                VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
                    permissionStatusPill

                    Text("⌘F search · ⌘1–8 · ⌘[ ⌘] sections")
                        .font(SettingsTheme.typeMicro(weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, SettingsTheme.spacingXS)
                }
                .padding(.horizontal, SettingsTheme.spacingM)
            }
        }
        .padding(.top, 32)
        .padding(.bottom, SettingsTheme.spacingM)
        .frame(width: 196)
    }

    private var permissionStatusPill: some View {
        let allGranted = SettingsPermissions.allGranted
        return Button {
            withAnimation(SettingsTheme.spring(reducedMotion: reduceMotion)) {
                selection = .system
            }
            SettingsTheme.performHaptic()
        } label: {
            HStack(spacing: SettingsTheme.spacingXS + 2) {
                Image(systemName: allGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(SettingsTheme.typeMicro(weight: .semibold))
                Text(allGranted ? "Ready to capture" : "Fix permissions")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(allGranted ? SettingsTheme.success : SettingsTheme.warning)
            .padding(.horizontal, SettingsTheme.spacingS)
            .padding(.vertical, SettingsTheme.spacingXS + 1)
            .background((allGranted ? SettingsTheme.success : SettingsTheme.warning).opacity(0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(allGranted ? "All permissions granted" : SettingsPermissions.healthLabel)
    }

    @ViewBuilder
    private func navItem(_ pane: SettingsPane) -> some View {
        SettingsNavItem(
            pane: pane,
            isSelected: selection == pane,
            namespace: navNamespace
        ) {
            withAnimation(SettingsTheme.spring(reducedMotion: reduceMotion)) {
                selection = pane
            }
            SettingsTheme.performHaptic()
        }
    }
}

private struct SettingsNavItem: View {
    let pane: SettingsPane
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let needsAttention = pane.needsPermissionAttention

        Button(action: action) {
            HStack(spacing: SettingsTheme.spacingS) {
                Image(systemName: pane.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? SettingsTheme.accent : pane.tint)

                Text(pane.title)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if needsAttention && !isSelected {
                    Circle()
                        .fill(SettingsTheme.warning)
                        .frame(width: 6, height: 6)
                }

                if !isSelected {
                    Text(pane.keyboardShortcut.character)
                        .font(SettingsTheme.typeMicro(weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, SettingsTheme.spacingM)
            .padding(.vertical, SettingsTheme.spacingS + 2)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                        .matchedGeometryEffect(id: "navSelection", in: namespace)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, SettingsTheme.spacingS)
        .onHover { hovering in
            SettingsTheme.animateHover(reducedMotion: reduceMotion) {
                isHovered = hovering
            }
        }
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
