import AppKit
import SwiftUI

struct ShortcutsSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var hotkeys: [HotkeyAction: Hotkey] = [:]
    @State private var rowErrors: [HotkeyAction: String] = [:]

    var body: some View {
        Form {
            ForEach(HotkeySettingsSection.allCases, id: \.rawValue) { section in
                Section(section.rawValue) {
                    ForEach(section.actions) { action in
                        hotkeyRow(for: action)
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset All to Defaults") {
                        settings.resetHotkeysToDefaults()
                        hotkeys = settings.hotkeys()
                        rowErrors = [:]
                        if let delegate = NSApp.delegate as? AppDelegate {
                            delegate.rebindHotkeys()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            HotkeyManager.requestInputMonitoringAccess()
            HotkeyManager.shared.refreshMonitors()
            hotkeys = settings.hotkeys()
        }
        .safeAreaInset(edge: .bottom) {
            if !HotkeyManager.hasInputMonitoringAccess {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Enable Input Monitoring in System Settings for background shortcuts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open…") { HotkeyManager.openInputMonitoringSettings() }
                        .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private func hotkeyRow(for action: HotkeyAction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(action.displayName, systemImage: action.symbol)
                Spacer()
                Button {
                    settings.setHotkey(action.defaultHotkey, for: action)
                    hotkeys = settings.hotkeys()
                    rowErrors[action] = nil
                    if let delegate = NSApp.delegate as? AppDelegate {
                        delegate.rebindHotkeys()
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset to default")
                HotkeyRecorderView(
                    action: action,
                    hotkey: Binding(
                        get: { hotkeys[action] ?? action.defaultHotkey },
                        set: { hotkeys[action] = $0 }
                    ),
                    validationMessage: { new in
                        settings.conflictingAction(for: new, excluding: action).map {
                            "Used by \($0.displayName)"
                        }
                    },
                    onChange: { new in
                        settings.setHotkey(new, for: action)
                        hotkeys = settings.hotkeys()
                        rowErrors[action] = nil
                        if let delegate = NSApp.delegate as? AppDelegate {
                            delegate.rebindHotkeys()
                        }
                    },
                    onValidationError: { message in
                        rowErrors[action] = message
                    }
                )
                .frame(width: 130, height: 24)
            }
            if let error = rowErrors[action] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
