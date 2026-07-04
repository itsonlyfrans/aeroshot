import AppKit
import SwiftUI

struct AboutSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 64, height: 64)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "ScreenCapture")
                            .font(.title2.weight(.semibold))
                        Text("Version \(versionString)")
                            .foregroundStyle(.secondary)
                        Text("© \(Calendar.current.component(.year, from: Date())) ScreenCapture")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Permissions") {
                PermissionRow(
                    title: "Screen Recording",
                    granted: CGPreflightScreenCaptureAccess(),
                    openSettings: openScreenRecordingSettings
                )
                PermissionRow(
                    title: "Input Monitoring",
                    granted: HotkeyManager.hasInputMonitoringAccess,
                    openSettings: { HotkeyManager.openInputMonitoringSettings() }
                )
                PermissionRow(
                    title: "Accessibility",
                    granted: ScrollEventPoster.hasAccessibilityAccess,
                    openSettings: { ScrollEventPoster.openAccessibilitySettings() }
                )
            }
        }
        .formStyle(.grouped)
    }

    private var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let granted: Bool
    let openSettings: () -> Void

    var body: some View {
        HStack {
            Circle()
                .fill(granted ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(title)
            Spacer()
            Text(granted ? "Granted" : "Not granted")
                .foregroundStyle(.secondary)
                .font(.caption)
            Button("Open Settings") { openSettings() }
                .controlSize(.small)
        }
    }
}
