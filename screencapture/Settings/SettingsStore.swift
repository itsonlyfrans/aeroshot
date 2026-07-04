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

    // Recording (plan "Later" features)
    @AppStorage("recordingFormatRaw") private var recordingFormatRaw: String = RecordingFormat.mp4.rawValue
    @AppStorage("recordSystemAudio") var recordSystemAudio: Bool = false
    @AppStorage("highlightClicksDuringRecording") var highlightClicksDuringRecording: Bool = true
    @AppStorage("gifFPS") var gifFPS: Int = 10
    @AppStorage("gifMaxFrames") var gifMaxFrames: Int = 300
    @AppStorage("scrollingAutoScroll") var scrollingAutoScroll: Bool = false
    @AppStorage("scrollingAutoScrollPixels") var scrollingAutoScrollPixels: Int = 120

    var recordingFormat: RecordingFormat {
        get { RecordingFormat(rawValue: recordingFormatRaw) ?? .mp4 }
        set { recordingFormatRaw = newValue.rawValue; objectWillChange.send() }
    }

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
        if let data = hotkeysJSON.data(using: .utf8),
           let stored = try? JSONDecoder().decode([String: Hotkey].self, from: data) {
            return Self.resolvedHotkeys(stored: stored)
        }
        return Self.resolvedHotkeys(stored: [:])
    }

    static func resolvedHotkeys(stored: [String: Hotkey]) -> [HotkeyAction: Hotkey] {
        var result: [HotkeyAction: Hotkey] = [:]
        for action in HotkeyAction.allCases { result[action] = action.defaultHotkey }
        for action in HotkeyAction.allCases {
            guard let hotkey = stored[action.rawValue],
                  hotkey.isValid,
                  result.first(where: { $0.key != action && $0.value == hotkey }) == nil
            else { continue }
            result[action] = hotkey
        }
        return result
    }

    /// Drops stored bindings that are invalid or duplicate another action.
    func sanitizeStoredHotkeys() {
        guard let data = hotkeysJSON.data(using: .utf8),
              let stored = try? JSONDecoder().decode([String: Hotkey].self, from: data) else { return }
        var resolved = Self.resolvedHotkeys(stored: [:])
        var valid: [String: Hotkey] = [:]
        for action in HotkeyAction.allCases {
            guard let hotkey = stored[action.rawValue],
                  hotkey.isValid,
                  resolved.first(where: { $0.key != action && $0.value == hotkey }) == nil
            else { continue }
            resolved[action] = hotkey
            valid[action.rawValue] = hotkey
        }
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
        guard hotkey.isValid,
              conflictingAction(for: hotkey, excluding: action) == nil
        else { return }
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

    func conflictingAction(for hotkey: Hotkey, excluding action: HotkeyAction) -> HotkeyAction? {
        hotkeys().first { $0.key != action && $0.value == hotkey }?.key
    }

    func newFileURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "Screenshot \(formatter.string(from: Date())).\(imageFormat.fileExtension)"
        return saveDirectory.appendingPathComponent(name)
    }

    func newRecordingURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let ext = recordingFormat.fileExtension
        let prefix = recordingFormat == .gif ? "Recording" : "Screen Recording"
        let name = "\(prefix) \(formatter.string(from: Date())).\(ext)"
        return saveDirectory.appendingPathComponent(name)
    }
}

enum RecordingFormat: String, Codable, CaseIterable, Identifiable {
    case mp4, gif

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mp4: return "MP4 Video"
        case .gif: return "Animated GIF"
        }
    }

    var fileExtension: String {
        switch self {
        case .mp4: return "mp4"
        case .gif: return "gif"
        }
    }
}
