import AppKit
import SwiftUI

struct ShortcutsSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var hotkeys: [HotkeyAction: Hotkey] = [:]
    @State private var rowErrors: [HotkeyAction: String] = [:]
    @State private var showResetConfirmation = false
    @State private var appProfiles: [HotkeyProfile] = []
    @State private var expandedProfileID: String?

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

                SettingsPanel("Per-app overrides") {
                    Text("When a listed app is frontmost, its shortcut bindings replace the global defaults above.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if appProfiles.isEmpty {
                        Text("No per-app profiles yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appProfiles) { profile in
                            PerAppHotkeyProfileRow(
                                profile: profile,
                                isExpanded: expandedProfileID == profile.id,
                                globalHotkeys: hotkeys,
                                onToggleExpanded: {
                                    expandedProfileID = expandedProfileID == profile.id ? nil : profile.id
                                },
                                onUpdate: { updated in
                                    replaceProfile(updated)
                                },
                                onDelete: {
                                    deleteProfile(profile)
                                }
                            )
                            if profile.id != appProfiles.last?.id {
                                Divider().opacity(0.5)
                            }
                        }
                    }

                    Button("Add override for \(frontmostAppName)") {
                        addProfileForFrontmostApp()
                    }
                    .controlSize(.small)
                    .disabled(frontmostBundleID == nil)
                }

                SettingsFooterActions("Reset All to Defaults", destructive: true) {
                    showResetConfirmation = true
                }
            }
        }
        .onAppear {
            HotkeyManager.shared.refreshMonitors()
            hotkeys = settings.hotkeys()
            reloadAppProfiles()
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

    private var frontmostBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private var frontmostAppName: String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "frontmost app"
    }

    private func reloadAppProfiles() {
        appProfiles = settings.hotkeyProfiles().filter { $0.bundleID != nil }
    }

    private func persistAppProfiles() {
        settings.setHotkeyProfiles(appProfiles)
        reloadAppProfiles()
        rebindHotkeys()
    }

    private func addProfileForFrontmostApp() {
        guard let bundleID = frontmostBundleID else { return }
        guard !appProfiles.contains(where: { $0.bundleID == bundleID }) else { return }
        let profile = HotkeyProfile(
            id: UUID().uuidString,
            name: frontmostAppName,
            bundleID: bundleID,
            hotkeys: [:]
        )
        appProfiles.append(profile)
        expandedProfileID = profile.id
        persistAppProfiles()
    }

    private func replaceProfile(_ profile: HotkeyProfile) {
        guard let index = appProfiles.firstIndex(where: { $0.id == profile.id }) else { return }
        appProfiles[index] = profile
        persistAppProfiles()
    }

    private func deleteProfile(_ profile: HotkeyProfile) {
        appProfiles.removeAll { $0.id == profile.id }
        if expandedProfileID == profile.id {
            expandedProfileID = nil
        }
        persistAppProfiles()
    }
}

private struct PerAppHotkeyProfileRow: View {
    let profile: HotkeyProfile
    let isExpanded: Bool
    let globalHotkeys: [HotkeyAction: Hotkey]
    let onToggleExpanded: () -> Void
    let onUpdate: (HotkeyProfile) -> Void
    let onDelete: () -> Void

    @State private var profileHotkeys: [HotkeyAction: Hotkey] = [:]
    @State private var rowErrors: [HotkeyAction: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.subheadline.weight(.semibold))
                    if let bundleID = profile.bundleID {
                        Text(bundleID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(isExpanded ? "Hide" : "Edit") { onToggleExpanded() }
                    .controlSize(.small)
                Button("Remove", role: .destructive) { onDelete() }
                    .controlSize(.small)
            }

            if isExpanded {
                ForEach(HotkeyAction.allCases) { action in
                    SettingsHotkeyRow(
                        action: action,
                        hotkey: Binding(
                            get: { profileHotkeys[action] ?? globalHotkeys[action] ?? action.defaultHotkey },
                            set: { profileHotkeys[action] = $0 }
                        ),
                        errorMessage: rowErrors[action],
                        onChange: { newHotkey in
                            var updated = profile
                            updated.hotkeys[action.rawValue] = newHotkey
                            onUpdate(updated)
                            profileHotkeys[action] = newHotkey
                            rowErrors[action] = nil
                        },
                        onValidationError: { message in
                            if let message {
                                rowErrors[action] = message
                            } else {
                                rowErrors.removeValue(forKey: action)
                            }
                        },
                        onReset: {
                            var updated = profile
                            updated.hotkeys.removeValue(forKey: action.rawValue)
                            onUpdate(updated)
                            profileHotkeys.removeValue(forKey: action)
                            rowErrors.removeValue(forKey: action)
                        }
                    )
                    if action != HotkeyAction.allCases.last {
                        Divider().opacity(0.5)
                    }
                }
            }
        }
        .onAppear {
            profileHotkeys = Dictionary(uniqueKeysWithValues: profile.hotkeys.compactMap { key, value in
                guard let action = HotkeyAction(rawValue: key) else { return nil }
                return (action, value)
            })
        }
        .onChange(of: profile.id) { _, _ in
            profileHotkeys = Dictionary(uniqueKeysWithValues: profile.hotkeys.compactMap { key, value in
                guard let action = HotkeyAction(rawValue: key) else { return nil }
                return (action, value)
            })
        }
    }
}
