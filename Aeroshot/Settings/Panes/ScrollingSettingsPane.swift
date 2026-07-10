import SwiftUI

struct ScrollingSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsPaneLayout(pane: .scrolling) {
            VStack(alignment: .leading, spacing: SettingsTheme.spacingL) {
                SettingsHeroHeader(
                    "Scrolling",
                    symbol: "arrow.up.and.down.text.horizontal",
                    subtitle: "Capture long pages by stitching multiple frames as you scroll.",
                    chips: [
                        settings.scrollingAutoScroll ? "Auto-scroll on" : "Manual scroll",
                        ScrollEventPoster.hasAccessibilityAccess ? "Accessibility granted" : "Accessibility needed"
                    ]
                )

                SettingsPanel("Capture behavior", symbol: "arrow.up.and.down") {
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
                        tone: .warning,
                        buttonTitle: "Grant Access…"
                    ) {
                        SettingsPermissions.requestAccessibility()
                    }
                }

                SettingsFootnoteSection("Related") {
                    SettingsQuickLink(
                        title: "Keyboard shortcuts",
                        subtitle: "Launch scrolling capture from anywhere",
                        pane: .shortcuts
                    )
                    SettingsSeparator()
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
