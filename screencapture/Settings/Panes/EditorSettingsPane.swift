import SwiftUI

struct EditorSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsPaneLayout {
            VStack(alignment: .leading, spacing: SettingsTheme.spacingL) {
                SettingsHeroHeader(
                    "Editor",
                    subtitle: "Defaults applied when you annotate and beautify captures.",
                    chips: [
                        settings.openEditorAfterCapture ? "Opens after capture" : "Manual open",
                        settings.defaultBeautifySettings.enabled ? "Beautify on" : "Beautify off"
                    ]
                )

                SettingsPanel("Workflow") {
                    SettingsToggle(
                        title: "Open editor after capture",
                        subtitle: "Jump straight into annotate mode when a screenshot completes",
                        isOn: $settings.openEditorAfterCapture,
                        symbol: "pencil.tip.crop.circle"
                    )
                }

                SettingsPanel("Beautify defaults") {
                    SettingsToggle(
                        title: "Enable beautify by default",
                        subtitle: "Apply frame, shadow, and gradient when the editor opens",
                        isOn: $settings.beautifyEnabledDefault,
                        symbol: "sparkles"
                    )

                    if settings.beautifyEnabledDefault {
                        SettingsSegmentedControl(
                            options: BeautifySettings.GradientPreset.allCases,
                            selection: Binding(
                                get: { settings.beautifyGradientPreset },
                                set: { settings.beautifyGradientPreset = $0 }
                            ),
                            label: { $0.displayName }
                        )

                        SettingsSegmentedControl(
                            options: BeautifySettings.AspectPreset.allCases,
                            selection: Binding(
                                get: { settings.beautifyAspectPreset },
                                set: { settings.beautifyAspectPreset = $0 }
                            ),
                            label: { $0.displayName }
                        )

                        SettingsValueSlider(
                            title: "Padding",
                            value: $settings.beautifyPadding,
                            in: 16...128,
                            step: 8,
                            valueLabel: { "\(Int($0)) pt" }
                        )

                        SettingsValueSlider(
                            title: "Corner radius",
                            value: $settings.beautifyCornerRadius,
                            in: 0...32,
                            step: 2,
                            valueLabel: { "\(Int($0)) pt" }
                        )
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(SettingsTheme.spring(reducedMotion: reduceMotion), value: settings.beautifyEnabledDefault)

                SettingsPanel("Related") {
                    SettingsQuickLink(
                        title: "Output format",
                        subtitle: "PNG, JPEG, or HEIC for saved files",
                        pane: .output
                    )
                }
            }
        }
    }
}
