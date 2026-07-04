import AppKit
import SwiftUI


struct AboutSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // App Logo and Details
                VStack(spacing: 12) {
                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 72, height: 72)
                            .shadow(color: Color.black.opacity(0.18), radius: 6, y: 3)
                    }
                    
                    VStack(spacing: 4) {
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "ScreenCapture")
                            .font(.system(size: 18, weight: .bold))
                        Text("Version \(versionString)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("© \(Calendar.current.component(.year, from: Date())) ScreenCapture")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                
                SettingsSectionCard("System Permissions") {
                    PermissionRow(
                        title: "Screen Recording",
                        description: "Required to capture windows, areas, and video.",
                        granted: CGPreflightScreenCaptureAccess(),
                        openSettings: openScreenRecordingSettings
                    )
                    
                    Divider().padding(.vertical, 2)
                    
                    PermissionRow(
                        title: "Input Monitoring",
                        description: "Required for global keyboard shortcuts.",
                        granted: HotkeyManager.hasInputMonitoringAccess,
                        openSettings: { HotkeyManager.openInputMonitoringSettings() }
                    )
                    
                    Divider().padding(.vertical, 2)
                    
                    PermissionRow(
                        title: "Accessibility",
                        description: "Required for automatic scrolling captures.",
                        granted: ScrollEventPoster.hasAccessibilityAccess,
                        openSettings: { ScrollEventPoster.openAccessibilitySettings() }
                    )
                }
            }
            .padding(18)
        }
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
    let description: String
    let granted: Bool
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(granted ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Text(granted ? "Granted" : "Not Granted")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(granted ? Color.green : Color.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(granted ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                    )
                
                if !granted {
                    Button("Grant…") { openSettings() }
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
