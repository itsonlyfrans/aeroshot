import AppKit
import SwiftUI

struct ShortcutsSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var hotkeys: [HotkeyAction: Hotkey] = [:]
    @State private var rowErrors: [HotkeyAction: String] = [:]
    @State private var showResetConfirmation = false

    private var configuredCount: Int {
        hotkeys.values.filter { $0.keyCode != 0 || $0.modifiers != 0 }.count
    }

    var body: some View {
        SettingsPaneLayout {
            VStack(alignment: .leading, spacing: SettingsTheme.spacingL) {
                SettingsHeroHeader(
                    "Shortcuts",
                    subtitle: "Global keyboard shortcuts work from any app.",
                    chips: [
                        SettingsHeroHeader.Chip("\(configuredCount) configured"),
                        SettingsHeroHeader.Chip(
                            HotkeyManager.hasInputMonitoringAccess ? "Monitoring enabled" : "Monitoring required",
                            tone: HotkeyManager.hasInputMonitoringAccess ? .success : .warning
                        )
                    ]
                )

                ForEach(HotkeySettingsSection.allCases, id: \.rawValue) { section in
                    SettingsPanel(section.rawValue) {
                        ForEach(Array(section.actions.enumerated()), id: \.element.id) { index, action in
                            if index > 0 {
                                Divider().opacity(0.5)
                            }
                            SettingsHotkeyRow(
                                action: action,
                                hotkey: Binding(
                                    get: { hotkeys[action] ?? action.defaultHotkey },
                                    set: { hotkeys[action] = $0 }
                                ),
                                errorMessage: rowErrors[action],
                                onChange: { new in
                                    settings.setHotkey(new, for: action)
                                    hotkeys = settings.hotkeys()
                                    rowErrors[action] = nil
                                    rebindHotkeys()
                                },
                                onValidationError: { message in
                                    if let message {
                                        rowErrors[action] = message
                                    } else {
                                        rowErrors.removeValue(forKey: action)
                                    }
                                },
                                onReset: {
                                    settings.setHotkey(action.defaultHotkey, for: action)
                                    hotkeys = settings.hotkeys()
                                    rowErrors[action] = nil
                                    rebindHotkeys()
                                }
                            )
                        }
                    }
                }

                if !HotkeyManager.hasInputMonitoringAccess {
                    SettingsInlineCallout(
                        symbol: "exclamationmark.triangle.fill",
                        message: "Enable Input Monitoring in System Settings for background shortcuts.",
                        buttonTitle: "Grant Access…"
                    ) {
                        HotkeyManager.openInputMonitoringSettings()
                    }
                }

                SettingsPanel("macOS Shortcuts") {
                    Text("Automate captures in the Shortcuts app — area, window, screen, scrolling, OCR, recording, and history.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Open Shortcuts") {
                        if let url = URL(string: "shortcuts://") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }

                SettingsFooterActions("Reset All to Defaults", destructive: true) {
                    showResetConfirmation = true
                }
            }
        }
        .onAppear {
            HotkeyManager.requestInputMonitoringAccess()
            HotkeyManager.shared.refreshMonitors()
            hotkeys = settings.hotkeys()
        }
        .alert("Reset all shortcuts?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                settings.resetHotkeysToDefaults()
                hotkeys = settings.hotkeys()
                rowErrors = [:]
                rebindHotkeys()
            }
        } message: {
            Text("All shortcuts will return to their default key combinations.")
        }
    }

    private func rebindHotkeys() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.rebindHotkeys()
        }
    }
}
