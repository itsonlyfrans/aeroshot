import SwiftUI

/// Window-level chrome behind the nav rail. Native adaptive surfaces only —
/// no painted gradients or tinted washes, so the shell tracks the system
/// appearance (including Increase Contrast) for free.
struct SettingsShellBackground: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
    }
}

/// Raised content surface behind the active pane. Sits one level above the
/// shell so the pane reads as the document, the rail as chrome.
struct SettingsPaneSurface: View {
    var body: some View {
        RoundedRectangle(cornerRadius: SettingsTheme.panelRadius, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: SettingsTheme.panelRadius, style: .continuous)
                    .strokeBorder(AeroTheme.strokeHairline.opacity(0.6), lineWidth: 1)
            }
    }
}
