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

    @AppStorage("recordingFormatRaw") private var recordingFormatRaw: String = RecordingFormat.mp4.rawValue
    @AppStorage("recordSystemAudio") var recordSystemAudio: Bool = false
    @AppStorage("highlightClicksDuringRecording") var highlightClicksDuringRecording: Bool = true
    @AppStorage("gifFPS") var gifFPS: Int = 10
    @AppStorage("gifMaxFrames") var gifMaxFrames: Int = 300
    @AppStorage("scrollingAutoScroll") var scrollingAutoScroll: Bool = false
    @AppStorage("scrollingAutoScrollPixels") var scrollingAutoScrollPixels: Int = 120
    @AppStorage("addOCRCapturesToHistory") var addOCRCapturesToHistory: Bool = false
    @AppStorage("addRecordingsToHistory") var addRecordingsToHistory: Bool = true

    @AppStorage("filenameTemplate") var filenameTemplate: String = "Screenshot {date} at {time}"
    @AppStorage("recordingFilenameTemplate") var recordingFilenameTemplate: String = "Screen Recording {date} at {time}"

    @AppStorage("openEditorAfterCapture") var openEditorAfterCapture: Bool = false
    @AppStorage("showThumbnailActionsAlways") var showThumbnailActionsAlways: Bool = false
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("activeCaptureProfileID") var activeCaptureProfileID: String = CaptureProfile.standard.id

    @AppStorage("beautifyEnabledDefault") var beautifyEnabledDefault: Bool = false
    @AppStorage("beautifyPadding") var beautifyPadding: Double = 64
    @AppStorage("beautifyCornerRadius") var beautifyCornerRadius: Double = 12
    @AppStorage("beautifyShadowRadius") var beautifyShadowRadius: Double = 30
    @AppStorage("beautifyShadowOpacity") var beautifyShadowOpacity: Double = 0.45
    @AppStorage("beautifyGradientRaw") private var beautifyGradientRaw: String = BeautifySettings.GradientPreset.indigo.rawValue
    @AppStorage("beautifyAspectRaw") private var beautifyAspectRaw: String = BeautifySettings.AspectPreset.auto.rawValue

    var recordingFormat: RecordingFormat {
        get { RecordingFormat(rawValue: recordingFormatRaw) ?? .mp4 }
        set { recordingFormatRaw = newValue.rawValue; objectWillChange.send() }
    }

    var imageFormat: ImageFormat {
        get { ImageFormat(rawValue: imageFormatRaw) ?? .png }
        set { imageFormatRaw = newValue.rawValue; objectWillChange.send() }
    }

    var beautifyGradientPreset: BeautifySettings.GradientPreset {
        get { BeautifySettings.GradientPreset(rawValue: beautifyGradientRaw) ?? .indigo }
        set { beautifyGradientRaw = newValue.rawValue; objectWillChange.send() }
    }

    var beautifyAspectPreset: BeautifySettings.AspectPreset {
        get { BeautifySettings.AspectPreset(rawValue: beautifyAspectRaw) ?? .auto }
        set { beautifyAspectRaw = newValue.rawValue; objectWillChange.send() }
    }

    var defaultBeautifySettings: BeautifySettings {
        BeautifySettings(
            enabled: beautifyEnabledDefault,
            padding: CGFloat(beautifyPadding),
            cornerRadius: CGFloat(beautifyCornerRadius),
            shadowRadius: CGFloat(beautifyShadowRadius),
            shadowOpacity: CGFloat(beautifyShadowOpacity),
            gradient: beautifyGradientPreset,
            aspectPreset: beautifyAspectPreset
        )
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
        for action in HotkeyAction.allCases {
            if let hotkey = stored[action.rawValue] {
                result[action] = hotkey
            } else {
                result[action] = action.defaultHotkey
            }
        }
        return result
    }

    /// Drops stored bindings that are invalid or duplicate another action.
    func sanitizeStoredHotkeys() {
        guard let data = hotkeysJSON.data(using: .utf8),
              let stored = try? JSONDecoder().decode([String: Hotkey].self, from: data) else { return }
        var resolved = Self.resolvedHotkeys(stored: stored)
        var valid: [String: Hotkey] = [:]
        for action in HotkeyAction.allCases {
            guard let hotkey = stored[action.rawValue] else { continue }
            let isDisabled = hotkey.keyCode == 0 && hotkey.modifiers == 0
            guard isDisabled || (hotkey.isValid && resolved.first(where: { $0.key != action && $0.value == hotkey }) == nil) else { continue }
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
        guard hotkey.isValid else { return }
        var stored: [String: Hotkey] = [:]
        if let data = hotkeysJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: Hotkey].self, from: data) {
            stored = decoded
        }

        let resolved = Self.resolvedHotkeys(stored: stored)
        for otherAction in HotkeyAction.allCases {
            if otherAction != action && resolved[otherAction] == hotkey {
                stored[otherAction.rawValue] = Hotkey(keyCode: 0, modifiers: 0)
            }
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
        let name = formattedFilename(
            template: filenameTemplate,
            typeLabel: "Screenshot",
            fileExtension: imageFormat.fileExtension
        )
        return saveDirectory.appendingPathComponent(name)
    }

    func newRecordingURL() -> URL {
        let prefix = recordingFormat == .gif ? "Recording" : "Screen Recording"
        let name = formattedFilename(
            template: recordingFilenameTemplate.isEmpty ? "\(prefix) {date} at {time}" : recordingFilenameTemplate,
            typeLabel: prefix,
            fileExtension: recordingFormat.fileExtension
        )
        return saveDirectory.appendingPathComponent(name)
    }

    func formattedFilename(template: String, typeLabel: String, fileExtension: String) -> String {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH.mm.ss"
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Screen"

        var base = template
            .replacingOccurrences(of: "{date}", with: dateFormatter.string(from: now))
            .replacingOccurrences(of: "{time}", with: timeFormatter.string(from: now))
            .replacingOccurrences(of: "{type}", with: typeLabel)
            .replacingOccurrences(of: "{app}", with: appName)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if base.isEmpty {
            base = "\(typeLabel) \(dateFormatter.string(from: now)) at \(timeFormatter.string(from: now))"
        }

        base = base.replacingOccurrences(of: "/", with: "-")
        base = base.replacingOccurrences(of: ":", with: ".")
        return "\(base).\(fileExtension)"
    }

    var activeCaptureProfile: CaptureProfile {
        CaptureProfile.profile(for: activeCaptureProfileID) ?? .standard
    }

    func applyCaptureProfile(_ profile: CaptureProfile) {
        activeCaptureProfileID = profile.id
        profile.apply(to: self)
        objectWillChange.send()
    }

    func resetAllToDefaults() {
        saveDirectoryPath = Self.defaultSaveDirectory.path
        imageFormatRaw = ImageFormat.png.rawValue
        jpegQuality = 0.9
        downscaleRetina = false
        copyToClipboardAfterCapture = true
        saveToDiskAfterCapture = true
        showThumbnailAfterCapture = true
        thumbnailDuration = 6.0
        playCaptureSound = true
        hotkeysJSON = ""
        recordingFormatRaw = RecordingFormat.mp4.rawValue
        recordSystemAudio = false
        highlightClicksDuringRecording = true
        gifFPS = 10
        gifMaxFrames = 300
        scrollingAutoScroll = false
        scrollingAutoScrollPixels = 120
        addOCRCapturesToHistory = false
        addRecordingsToHistory = true
        filenameTemplate = "Screenshot {date} at {time}"
        recordingFilenameTemplate = "Screen Recording {date} at {time}"
        openEditorAfterCapture = false
        showThumbnailActionsAlways = false
        beautifyEnabledDefault = false
        beautifyPadding = 64
        beautifyCornerRadius = 12
        beautifyShadowRadius = 30
        beautifyShadowOpacity = 0.45
        beautifyGradientRaw = BeautifySettings.GradientPreset.indigo.rawValue
        beautifyAspectRaw = BeautifySettings.AspectPreset.auto.rawValue
        activeCaptureProfileID = CaptureProfile.standard.id
        objectWillChange.send()
    }

    func exportProfile() -> Data? {
        let profile = SettingsProfile(from: self)
        return try? JSONEncoder().encode(profile)
    }

    func importProfile(from data: Data) throws {
        let profile = try JSONDecoder().decode(SettingsProfile.self, from: data)
        profile.apply(to: self)
        objectWillChange.send()
    }
}

private struct SettingsProfile: Codable {
    var saveDirectoryPath: String
    var imageFormatRaw: String
    var jpegQuality: Double
    var downscaleRetina: Bool
    var copyToClipboardAfterCapture: Bool
    var saveToDiskAfterCapture: Bool
    var showThumbnailAfterCapture: Bool
    var thumbnailDuration: Double
    var playCaptureSound: Bool
    var hotkeysJSON: String
    var recordingFormatRaw: String
    var recordSystemAudio: Bool
    var highlightClicksDuringRecording: Bool
    var gifFPS: Int
    var gifMaxFrames: Int
    var scrollingAutoScroll: Bool
    var scrollingAutoScrollPixels: Int
    var addOCRCapturesToHistory: Bool
    var addRecordingsToHistory: Bool
    var filenameTemplate: String
    var recordingFilenameTemplate: String
    var openEditorAfterCapture: Bool
    var showThumbnailActionsAlways: Bool
    var beautifyEnabledDefault: Bool
    var beautifyPadding: Double
    var beautifyCornerRadius: Double
    var beautifyShadowRadius: Double
    var beautifyShadowOpacity: Double
    var beautifyGradientRaw: String
    var beautifyAspectRaw: String
    var activeCaptureProfileID: String

    init(from store: SettingsStore) {
        saveDirectoryPath = store.saveDirectoryPath
        imageFormatRaw = store.imageFormat.rawValue
        jpegQuality = store.jpegQuality
        downscaleRetina = store.downscaleRetina
        copyToClipboardAfterCapture = store.copyToClipboardAfterCapture
        saveToDiskAfterCapture = store.saveToDiskAfterCapture
        showThumbnailAfterCapture = store.showThumbnailAfterCapture
        thumbnailDuration = store.thumbnailDuration
        playCaptureSound = store.playCaptureSound
        hotkeysJSON = UserDefaults.standard.string(forKey: "hotkeysJSON") ?? ""
        recordingFormatRaw = store.recordingFormat.rawValue
        recordSystemAudio = store.recordSystemAudio
        highlightClicksDuringRecording = store.highlightClicksDuringRecording
        gifFPS = store.gifFPS
        gifMaxFrames = store.gifMaxFrames
        scrollingAutoScroll = store.scrollingAutoScroll
        scrollingAutoScrollPixels = store.scrollingAutoScrollPixels
        addOCRCapturesToHistory = store.addOCRCapturesToHistory
        addRecordingsToHistory = store.addRecordingsToHistory
        filenameTemplate = store.filenameTemplate
        recordingFilenameTemplate = store.recordingFilenameTemplate
        openEditorAfterCapture = store.openEditorAfterCapture
        showThumbnailActionsAlways = store.showThumbnailActionsAlways
        beautifyEnabledDefault = store.beautifyEnabledDefault
        beautifyPadding = store.beautifyPadding
        beautifyCornerRadius = store.beautifyCornerRadius
        beautifyShadowRadius = store.beautifyShadowRadius
        beautifyShadowOpacity = store.beautifyShadowOpacity
        beautifyGradientRaw = store.beautifyGradientPreset.rawValue
        beautifyAspectRaw = store.beautifyAspectPreset.rawValue
        activeCaptureProfileID = store.activeCaptureProfileID
    }

    func apply(to store: SettingsStore) {
        store.saveDirectoryPath = saveDirectoryPath
        store.imageFormat = ImageFormat(rawValue: imageFormatRaw) ?? .png
        store.jpegQuality = jpegQuality
        store.downscaleRetina = downscaleRetina
        store.copyToClipboardAfterCapture = copyToClipboardAfterCapture
        store.saveToDiskAfterCapture = saveToDiskAfterCapture
        store.showThumbnailAfterCapture = showThumbnailAfterCapture
        store.thumbnailDuration = thumbnailDuration
        store.playCaptureSound = playCaptureSound
        UserDefaults.standard.set(hotkeysJSON, forKey: "hotkeysJSON")
        store.recordingFormat = RecordingFormat(rawValue: recordingFormatRaw) ?? .mp4
        store.recordSystemAudio = recordSystemAudio
        store.highlightClicksDuringRecording = highlightClicksDuringRecording
        store.gifFPS = gifFPS
        store.gifMaxFrames = gifMaxFrames
        store.scrollingAutoScroll = scrollingAutoScroll
        store.scrollingAutoScrollPixels = scrollingAutoScrollPixels
        store.addOCRCapturesToHistory = addOCRCapturesToHistory
        store.addRecordingsToHistory = addRecordingsToHistory
        store.filenameTemplate = filenameTemplate
        store.recordingFilenameTemplate = recordingFilenameTemplate
        store.openEditorAfterCapture = openEditorAfterCapture
        store.showThumbnailActionsAlways = showThumbnailActionsAlways
        store.beautifyEnabledDefault = beautifyEnabledDefault
        store.beautifyPadding = beautifyPadding
        store.beautifyCornerRadius = beautifyCornerRadius
        store.beautifyShadowRadius = beautifyShadowRadius
        store.beautifyShadowOpacity = beautifyShadowOpacity
        store.beautifyGradientPreset = BeautifySettings.GradientPreset(rawValue: beautifyGradientRaw) ?? .indigo
        store.beautifyAspectPreset = BeautifySettings.AspectPreset(rawValue: beautifyAspectRaw) ?? .auto
        store.activeCaptureProfileID = activeCaptureProfileID
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
