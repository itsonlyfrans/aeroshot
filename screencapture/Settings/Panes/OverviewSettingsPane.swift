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
                    subtitle: "Everything about your capture setup in one place.",
                    chips: SettingsPermissions.allGranted
                        ? [SettingsHeroHeader.Chip("All permissions granted", tone: .success)]
                        : [SettingsHeroHeader.Chip(SettingsPermissions.healthLabel, tone: .warning)]
                )

                HStack(spacing: SettingsTheme.spacingM) {
                    SettingsStatCard(
                        title: "After capture",
                        value: workflowSummary,
                        symbol: "bolt.fill",
                        tint: .blue
                    )
                    SettingsStatCard(
                        title: "Output format",
                        value: settings.imageFormat.displayName,
                        symbol: "doc.fill",
                        tint: .purple
                    )
                    SettingsStatCard(
                        title: "Permissions",
                        value: SettingsPermissions.healthLabel,
                        symbol: SettingsPermissions.allGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                        tint: SettingsPermissions.allGranted ? .green : .orange
                    )
                }

                SettingsPanel("Quick controls") {
                    SettingsToggle(
                        title: "Copy to clipboard",
                        subtitle: nil,
                        isOn: $settings.copyToClipboardAfterCapture,
                        symbol: "doc.on.clipboard"
                    )
                    SettingsToggle(
                        title: "Save to disk",
                        subtitle: nil,
                        isOn: $settings.saveToDiskAfterCapture,
                        symbol: "externaldrive"
                    )
                    SettingsToggle(
                        title: "Quick-access thumbnail",
                        subtitle: nil,
                        isOn: $settings.showThumbnailAfterCapture,
                        symbol: "photo.on.rectangle.angled"
                    )
                }

                if !SettingsPermissions.allGranted {
                    SettingsInlineCallout(
                        symbol: "hand.raised.fill",
                        message: "Some permissions still need attention for full functionality.",
                        buttonTitle: "Review…"
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
}
