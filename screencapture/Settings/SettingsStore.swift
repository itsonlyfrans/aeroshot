import Combine
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @AppStorage("saveDirectoryPath") var saveDirectoryPath: String = SettingsStore.defaultSaveDirectory.path
    @AppStorage("imageFormatRaw") private var imageFormatRaw: String = ImageFormat.png.rawValue
    @AppStorage("jpegQuality") var jpegQuality: Double = 0.9
    @AppStorage("downscaleRetina") var downscaleRetina: Bool = false
    @AppStorage("copyToClipboardAfterCapture") var copyToClipboardAfterCapture: Bool = true
    @AppStorage("saveToDiskAfterCapture") var saveToDiskAfterCapture: Bool = true
    @AppStorage("showThumbnailAfterCapture") var showThumbnailAfterCapture: Bool = true
    @AppStorage("thumbnailDuration") var thumbnailDuration: Double = 6.0
    @AppStorage("playCaptureSound") var playCaptureSound: Bool = true
    @AppStorage("hotkeysJSON") private var hotkeysJSON: String = ""

    var imageFormat: ImageFormat {
        get { ImageFormat(rawValue: imageFormatRaw) ?? .png }
        set { imageFormatRaw = newValue.rawValue; objectWillChange.send() }
    }

    static var defaultSaveDirectory: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScreenCapture", isDirectory: true)
    }

    var saveDirectory: URL {
        let url = URL(fileURLWithPath: saveDirectoryPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Hotkeys

    func hotkeys() -> [HotkeyAction: Hotkey] {
        var result: [HotkeyAction: Hotkey] = [:]
        for action in HotkeyAction.allCases { result[action] = action.defaultHotkey }
        if let data = hotkeysJSON.data(using: .utf8),
           let stored = try? JSONDecoder().decode([String: Hotkey].self, from: data) {
            for (key, hk) in stored {
                guard let action = HotkeyAction(rawValue: key), hk.isValid else { continue }
                result[action] = hk
            }
        }
        return result
    }

    /// Drops stored bindings that are structurally invalid (e.g. no modifier key).
    func sanitizeStoredHotkeys() {
        guard let data = hotkeysJSON.data(using: .utf8),
              let stored = try? JSONDecoder().decode([String: Hotkey].self, from: data) else { return }
        let valid = stored.filter { $0.value.isValid }
        if valid.count == stored.count { return }
        if valid.isEmpty {
            hotkeysJSON = ""
        } else if let data = try? JSONEncoder().encode(valid),
                  let json = String(data: data, encoding: .utf8) {
            hotkeysJSON = json
        }
        objectWillChange.send()
    }

    func resetHotkeysToDefaults() {
        hotkeysJSON = ""
        objectWillChange.send()
    }

    func setHotkey(_ hotkey: Hotkey, for action: HotkeyAction) {
        guard hotkey.isValid else { return }
        var stored: [String: Hotkey] = [:]
        if let data = hotkeysJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: Hotkey].self, from: data) {
            stored = decoded
        }
        stored[action.rawValue] = hotkey
        if let data = try? JSONEncoder().encode(stored), let json = String(data: data, encoding: .utf8) {
            hotkeysJSON = json
        }
        objectWillChange.send()
    }

    func newFileURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "Screenshot \(formatter.string(from: Date())).\(imageFormat.fileExtension)"
        return saveDirectory.appendingPathComponent(name)
    }
}
