import SwiftUI

private struct SettingsAtlasEmbeddedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var settingsAtlasEmbedded: Bool {
        get { self[SettingsAtlasEmbeddedKey.self] }
        set { self[SettingsAtlasEmbeddedKey.self] = newValue }
    }
}
