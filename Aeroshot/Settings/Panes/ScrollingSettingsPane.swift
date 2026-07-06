import SwiftUI

struct ScrollingSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsPaneLayout {
            VStack(alignment: .leading, spacing: SettingsTheme.spacingL) {
                SettingsHeroHeader(
                    "Scrolling",
                    subtitle: "Capture long pages by stitching multiple frames as you scroll.",
                    chips: [
                        settings.scrollingAutoScroll ? "Auto-scroll on" : "Manual scroll",
                        ScrollEventPoster.hasAccessibilityAccess ? "Accessibility granted" : "Accessibility needed"
                    ]
                )

                SettingsPanel("Capture behavior") {
                    SettingsToggle(
                        title: "Auto-scroll trigger",
                        subtitle: "Start scrolling automatically in scrolling capture mode",
                        isOn: $settings.scrollingAutoScroll,
                        symbol: "arrow.up.and.down"
                    )

                    if settings.scrollingAutoScroll {
                        SettingsValueSlider(
                            title: "Scroll speed step",
                            subtitle: "Pixels moved per auto-scroll step",
                            value: Binding(
                                get: { Double(settings.scrollingAutoScrollPixels) },
                                set: { settings.scrollingAutoScrollPixels = Int($0) }
                            ),
                            in: 40...400,
                            step: 20,
                            valueLabel: { "\(Int($0)) px" }
                        )
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    }
                }

                if !ScrollEventPoster.hasAccessibilityAccess {
                    SettingsInlineCallout(
                        symbol: "exclamationmark.triangle.fill",
                        message: "Auto-scroll requires Accessibility permission so Aeroshot can send scroll events.",
                        buttonTitle: "Grant Access…"
                    ) {
                        SettingsPermissions.requestAccessibility()
                    }
                }

                SettingsPanel("Related") {
                    SettingsQuickLink(
                        title: "Keyboard shortcuts",
                        subtitle: "Launch scrolling capture from anywhere",
                        pane: .shortcuts
                    )
                    Divider().opacity(0.5)
                    SettingsQuickLink(
                        title: "System permissions",
                        subtitle: "Review all privacy settings",
                        pane: .system
                    )
                }
            }
            .animation(SettingsTheme.spring(reducedMotion: reduceMotion), value: settings.scrollingAutoScroll)
        }
    }
}
