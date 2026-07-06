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
        SettingsPaneLayout {
            VStack(alignment: .leading, spacing: SettingsTheme.spacingL) {
                SettingsHeroHeader(
                    "Overview",
                    subtitle: "Your capture setup at a glance — adjust options in each section below.",
                    chips: SettingsPermissions.allGranted
                        ? [SettingsHeroHeader.Chip("All permissions granted", tone: .success)]
                        : [SettingsHeroHeader.Chip(SettingsPermissions.healthLabel, tone: .warning)]
                )

                HStack(spacing: SettingsTheme.spacingM) {
                    overviewStatCard(
                        title: "After capture",
                        value: workflowSummary,
                        symbol: "bolt.fill",
                        tint: .blue,
                        pane: .capture
                    )
                    overviewStatCard(
                        title: "Output format",
                        value: settings.imageFormat.displayName,
                        symbol: "doc.fill",
                        tint: .purple,
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
                        tint: SettingsPermissions.allGranted ? .green : .orange,
                        pane: .system
                    )
                }

                if !SettingsPermissions.allGranted {
                    SettingsInlineCallout(
                        symbol: "hand.raised.fill",
                        message: "Some permissions still need attention for full functionality.",
                        buttonTitle: "Set up permissions…"
                    ) {
                        navigate(.system)
                    }
                }

                VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
                    Text("Explore")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, SettingsTheme.spacingXS)

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
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
