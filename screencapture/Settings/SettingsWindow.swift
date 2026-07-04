import SwiftUI

struct SettingsWindow: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var pane: SettingsPane = .overview
    @State private var searchQuery = ""
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            SettingsNavRail(
                selection: $pane,
                searchQuery: $searchQuery,
                searchFocus: $searchFocused
            )

            Divider()
                .padding(.vertical, SettingsTheme.spacingM)

            ZStack(alignment: .top) {
                SettingsShellBackground()

                paneContent
                    .id(pane)
                    .transition(paneTransition)
            }
            .clipShape(RoundedRectangle(cornerRadius: SettingsTheme.panelRadius, style: .continuous))
        }
        .padding(SettingsTheme.spacingL)
        .padding(.top, 4)
        .background(SettingsShellBackground())
        .environment(\.settingsNavigate) { target in
            withAnimation(SettingsTheme.spring(reducedMotion: reduceMotion)) {
                pane = target
            }
        }
        .animation(SettingsTheme.spring(reducedMotion: reduceMotion), value: pane)
        .background { keyboardShortcutButtons }
    }

    @ViewBuilder
    private var paneContent: some View {
        switch pane {
        case .overview:
            OverviewSettingsPane()
        case .capture:
            CaptureSettingsPane()
        case .output:
            OutputSettingsPane()
        case .shortcuts:
            ShortcutsSettingsPane()
        case .recording:
            RecordingSettingsPane()
        case .system:
            SystemSettingsPane()
        }
    }

    private var paneTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)),
            removal: .opacity.combined(with: .offset(y: -8))
        )
    }

    @ViewBuilder
    private var keyboardShortcutButtons: some View {
        Group {
            Button("") { pane = .overview }
                .keyboardShortcut("1", modifiers: .command)
            Button("") { pane = .capture }
                .keyboardShortcut("2", modifiers: .command)
            Button("") { pane = .output }
                .keyboardShortcut("3", modifiers: .command)
            Button("") { pane = .shortcuts }
                .keyboardShortcut("4", modifiers: .command)
            Button("") { pane = .recording }
                .keyboardShortcut("5", modifiers: .command)
            Button("") { pane = .system }
                .keyboardShortcut("6", modifiers: .command)
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
        }
        .hidden()
        .frame(width: 0, height: 0)
    }
}
