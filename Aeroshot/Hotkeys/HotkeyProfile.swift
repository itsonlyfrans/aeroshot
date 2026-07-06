import Foundation

struct HotkeyProfile: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var bundleID: String?
    var hotkeys: [String: Hotkey]

    static let globalDefaultID = "global-default"

    static var globalDefault: HotkeyProfile {
        HotkeyProfile(
            id: globalDefaultID,
            name: "Default (all apps)",
            bundleID: nil,
            hotkeys: Dictionary(uniqueKeysWithValues: HotkeyAction.allCases.map { ($0.rawValue, $0.defaultHotkey) })
        )
    }

    func resolvedHotkeys(fallback: [HotkeyAction: Hotkey]) -> [HotkeyAction: Hotkey] {
        var result = fallback
        for action in HotkeyAction.allCases {
            if let hotkey = hotkeys[action.rawValue] {
                result[action] = hotkey
            }
        }
        return result
    }
}

enum HotkeyProfileStore {
    static func load(from json: String) -> [HotkeyProfile] {
        guard let data = json.data(using: .utf8),
              let profiles = try? JSONDecoder().decode([HotkeyProfile].self, from: data),
              !profiles.isEmpty else {
            return [HotkeyProfile.globalDefault]
        }
        return profiles
    }

    static func encode(_ profiles: [HotkeyProfile]) -> String {
        guard let data = try? JSONEncoder().encode(profiles),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }

    static func profile(for bundleID: String?, in profiles: [HotkeyProfile]) -> HotkeyProfile? {
        guard let bundleID else { return nil }
        return profiles.first { $0.bundleID == bundleID }
    }
}
