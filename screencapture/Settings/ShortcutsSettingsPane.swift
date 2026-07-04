import AppKit
import SwiftUI

struct ShortcutsSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var hotkeys: [HotkeyAction: Hotkey] = [:]
    @State private var rowErrors: [HotkeyAction: String] = [:]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(HotkeySettingsSection.allCases, id: \.rawValue) { section in
                    SettingsSectionCard(section.rawValue) {
                        VStack(spacing: 8) {
                            ForEach(section.actions) { action in
                                hotkeyRow(for: action)
                                if action != section.actions.last {
                                    Divider().padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }

                VStack(spacing: 12) {
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
                        .controlSize(.small)
                    }
                    
                    if !HotkeyManager.hasInputMonitoringAccess {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.system(size: 11))
                            Text("Enable Input Monitoring in System Settings for background shortcuts.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Grant Access…") { HotkeyManager.openInputMonitoringSettings() }
                                .controlSize(.small)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.2), lineWidth: 0.5))
                    }
                }
                .padding(.top, 4)
            }
            .padding(18)
        }
        .onAppear {
            HotkeyManager.requestInputMonitoringAccess()
            HotkeyManager.shared.refreshMonitors()
            hotkeys = settings.hotkeys()
        }
    }

    @ViewBuilder
    private func hotkeyRow(for action: HotkeyAction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                Label {
                    Text(action.displayName)
                        .font(.system(size: 12))
                } icon: {
                    Image(systemName: action.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
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
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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
                .frame(width: 130, height: 20)
            }
            if let error = rowErrors[action] {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .padding(.leading, 18)
            }
        }
    }
}
