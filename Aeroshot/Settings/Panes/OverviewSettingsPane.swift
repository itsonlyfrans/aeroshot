import SwiftUI

struct OverviewSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.settingsNavigate) private var navigate

    private var workflowCount: Int {
        [
            settings.copyToClipboardAfterCapture,
            settings.saveToDiskAfterCapture,
            settings.showThumbnailAfterCapture,
            settings.playCaptureSound
        ].filter { $0 }.count
    }

    private var workflowSummary: String {
        "\(workflowCount) of 4 active"
    }

    var body: some View {
        SettingsPaneLayout(pane: .overview) {
            VStack(alignment: .leading, spacing: SettingsTheme.spacingL) {
                SettingsHeroHeader(
                    "Overview",
                    symbol: "square.grid.2x2",
                    subtitle: "Your capture setup at a glance — adjust options in each section below.",
                    chips: SettingsPermissions.allGranted
                        ? [SettingsHeroHeader.Chip("All permissions granted", tone: .success)]
                        : [SettingsHeroHeader.Chip(SettingsPermissions.healthLabel, tone: .warning)]
                )

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: SettingsTheme.spacingM), GridItem(.flexible(), spacing: SettingsTheme.spacingM)],
                    spacing: SettingsTheme.spacingM
                ) {
                    overviewStatCard(
                        title: "After capture",
                        value: workflowSummary,
                        symbol: "bolt.fill",
                        tint: SettingsTheme.accent,
                        pane: .capture
                    )
                    overviewStatCard(
                        title: "Output format",
                        value: settings.imageFormat.displayName,
                        symbol: "doc.fill",
                        tint: .secondary,
                        pane: .output
                    )
                    overviewStatCard(
                        title: "Recording",
                        value: settings.recordingFormat.displayName,
                        symbol: "record.circle",
                        tint: .red,
                        pane: .recording
                    )
                    overviewStatCard(
                        title: "Permissions",
                        value: SettingsPermissions.healthLabel,
                        symbol: SettingsPermissions.allGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                        tint: SettingsPermissions.allGranted ? SettingsTheme.success : SettingsTheme.warning,
                        pane: .system
                    )
                }

                if !SettingsPermissions.allGranted {
                    SettingsInlineCallout(
                        symbol: "hand.raised.fill",
                        message: "Some permissions still need attention for full functionality.",
                        tone: .warning,
                        buttonTitle: "Set up permissions…"
                    ) {
                        navigate(.system)
                    }
                }

                SettingsPanel("Shortcuts at a glance", symbol: "keyboard") {
                    let hotkeys = settings.hotkeys()
                    ForEach(Array(overviewShortcuts.enumerated()), id: \.element.id) { index, action in
                        if index > 0 {
                            SettingsSeparator()
                        }
                        SettingsShortcutRow(
                            symbol: action.symbol,
                            title: action.displayName,
                            keycap: (hotkeys[action] ?? action.defaultHotkey).displayString
                        )
                    }

                    SettingsSeparator()

                    SettingsQuickLink(
                        title: "Customize shortcuts",
                        subtitle: "Rebind any action, add per-app overrides",
                        pane: .shortcuts
                    )
                }
 
                VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
                    SettingsSectionLabel(title: "Explore", symbol: "square.grid.2x2")

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: SettingsTheme.spacingM), GridItem(.flexible(), spacing: SettingsTheme.spacingM)],
                        spacing: SettingsTheme.spacingM
                    ) {
                        ForEach(SettingsPane.exploreSections) { section in
                            SettingsJumpCard(pane: section) {
                                SettingsTheme.performHaptic()
                                navigate(section)
                            }
                        }
                    }
                }
            }
        }
    }

    private var overviewShortcuts: [HotkeyAction] {
        [.allInOne, .captureArea, .recordArea, .captureOCR]
    }

    private func overviewStatCard(
        title: String,
        value: String,
        symbol: String,
        tint: Color,
        pane: SettingsPane
    ) -> some View {
        Button {
            SettingsTheme.performHaptic()
            navigate(pane)
        } label: {
            SettingsStatCard(title: title, value: value, symbol: symbol, tint: tint)
        }
        .buttonStyle(.plain)
        .help("Open \(pane.title) settings")
    }
}
