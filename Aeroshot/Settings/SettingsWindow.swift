import SwiftUI

/// Native settings entry point. The Atlas surface replaces the previous rail
/// while keeping every existing pane and SettingsStore binding alive underneath.
struct SettingsWindow: View {
    var body: some View {
        SettingsAtlasWindow()
    }
}
