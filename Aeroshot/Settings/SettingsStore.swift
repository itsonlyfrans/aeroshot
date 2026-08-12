import Combine
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    static let quieterCaptureDefaultsMigrationKey = "didMigrateQuieterCaptureDefaultsV1"

    /// URLs handed to an export or recording during this app session. Keeping these
    /// reservations prevents two quick actions with the same timestamped name from
    /// targeting the same file before either writer has created it on disk.
    private var reservedOutputPaths = Set<String>()

    @AppStorage("saveDirectoryPath") var saveDirectoryPath: String = SettingsStore.defaultSaveDirectory.path
    @AppStorage("imageFormatRaw") private var imageFormatRaw: String = ImageFormat.png.rawValue
    @AppStorage("jpegQuality") var jpegQuality: Double = 0.9
    @AppStorage("downscaleRetina") var downscaleRetina: Bool = false
    @AppStorage("copyToClipboardAfterCapture") var copyToClipboardAfterCapture: Bool = false
    @AppStorage("saveToDiskAfterCapture") var saveToDiskAfterCapture: Bool = true
    @AppStorage("showThumbnailAfterCapture") var showThumbnailAfterCapture: Bool = true
    @AppStorage("thumbnailDuration") var thumbnailDuration: Double = 6.0
    @AppStorage("playCaptureSound") var playCaptureSound: Bool = true
    @AppStorage("selectedCaptureSound") var selectedCaptureSound: String = "aeroshot_soft_bloop"
    @AppStorage("hotkeysJSON") private var hotkeysJSON: String = ""

    struct SoundOption: Identifiable, Hashable {
        var id: String { filename }
        let filename: String
        let displayName: String
    }

    let availableSounds: [SoundOption] = [
        SoundOption(filename: "snug_click", displayName: "Snug Click"),
        SoundOption(filename: "cove_echo", displayName: "Cove Echo"),
        SoundOption(filename: "latch_tap", displayName: "Latch Tap"),
        SoundOption(filename: "nook_sweep", displayName: "Nook Sweep"),
        SoundOption(filename: "grip_whoosh", displayName: "Grip Whoosh"),
        SoundOption(filename: "cabin_wood", displayName: "Cabin Wood"),
        SoundOption(filename: "tuck_drop", displayName: "Tuck Drop"),
        SoundOption(filename: "pluck_string", displayName: "Pluck String"),
        SoundOption(filename: "shed_slide", displayName: "Shed Slide"),
        SoundOption(filename: "lull_chime", displayName: "Lull Chime"),
        SoundOption(filename: "hearth_success", displayName: "Hearth Success"),
        SoundOption(filename: "nest_collect", displayName: "Nest Double-Bloop"),
        SoundOption(filename: "keep_slide", displayName: "Keep Slide"),
        SoundOption(filename: "wisp_puff", displayName: "Wisp Puff"),
        SoundOption(filename: "pebble_tap", displayName: "Pebble Tap"),
        SoundOption(filename: "glint_rhodes", displayName: "Glint Rhodes"),
        SoundOption(filename: "aeroshot_soft_bloop", displayName: "Soft Bloop"),
        SoundOption(filename: "aeroshot_warm_hug", displayName: "Warm Hug"),
        SoundOption(filename: "aeroshot_soft_breeze", displayName: "Soft Breeze"),
        SoundOption(filename: "aeroshot_velvet_tap", displayName: "Velvet Tap"),
        SoundOption(filename: "capture_bubble", displayName: "Bubble Pop"),
        SoundOption(filename: "capture_chime", displayName: "Warm Chime")
    ]

    init() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.quieterCaptureDefaultsMigrationKey) else { return }
        copyToClipboardAfterCapture = false
        showThumbnailActionsAlways = false
        copyLinkAfterUpload = false
        defaults.set(true, forKey: Self.quieterCaptureDefaultsMigrationKey)
    }

    func playSelectedSound() {
        guard playCaptureSound else { return }
        if let url = Bundle.main.url(forResource: selectedCaptureSound, withExtension: "flac") {
            NSSound(contentsOf: url, byReference: false)?.play()
        } else {
            NSSound(named: "Pop")?.play()
        }
    }


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
    @AppStorage("thumbnailVisibleActionsJSON") private var thumbnailVisibleActionsJSON: String = ""
    @AppStorage("thumbnailSwipeBindingsJSON") private var thumbnailSwipeBindingsJSON: String = ""
    @Published var thumbnailSwipeFingerCount: ThumbnailSwipeFingerCount = .two
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("hasDismissedInputMonitoringGuide") var hasDismissedInputMonitoringGuide: Bool = false
    @AppStorage("activeCaptureProfileID") var activeCaptureProfileID: String = CaptureProfile.standard.id
    @AppStorage("captureDelaySeconds") var captureDelaySeconds: Int = 0
    @AppStorage("freezeScreenDuringCapture") var freezeScreenDuringCapture: Bool = false
    @AppStorage("recallLastRegionEnabled") var recallLastRegionEnabled: Bool = true
    @AppStorage("allInOneCaptureImmediately") var allInOneCaptureImmediately: Bool = false
    @AppStorage("lastCaptureIntentKey") var lastCaptureIntentKey: String = CaptureIntent.area.storageKey
    @AppStorage("selectionAspectLockRaw") private var selectionAspectLockRaw: String = SelectionAspectLock.auto.rawValue
    @AppStorage("recordMicrophone") var recordMicrophone: Bool = false
    @AppStorage("recordingMicrophoneDeviceID") var recordingMicrophoneDeviceID: String = ""
    @AppStorage("showWebcamOverlay") var showWebcamOverlay: Bool = false
    @AppStorage("uploadWebhookURL") var uploadWebhookURL: String = ""
    @AppStorage("uploadAfterCapture") var uploadAfterCapture: Bool = false
    @AppStorage("copyLinkAfterUpload") var copyLinkAfterUpload: Bool = false
    @AppStorage("hotkeyProfilesJSON") private var hotkeyProfilesJSON: String = ""
    @AppStorage("showInMenuBar") var showInMenuBar: Bool = true
    @AppStorage("showInDock") var showInDock: Bool = false
    @AppStorage("shareSafeRedactionStyleRaw") private var shareSafeRedactionStyleRaw: String = ShareSafeRedactionStyle.blur.rawValue
    @AppStorage("shareSafeSmartScan") var shareSafeSmartScan: Bool = false
    @AppStorage("shareSafePrivacyFilter") var shareSafePrivacyFilter: Bool = false
    @AppStorage("shareSafeRedactBeforeSharing") var shareSafeRedactBeforeSharing: Bool = true
    @AppStorage("shareSafeAutoRedactAfterCapture") var shareSafeAutoRedactAfterCapture: Bool = false

    var shareSafeRedactionStyle: ShareSafeRedactionStyle {
        get { ShareSafeRedactionStyle(rawValue: shareSafeRedactionStyleRaw) ?? .blur }
        set { shareSafeRedactionStyleRaw = newValue.rawValue; objectWillChange.send() }
    }

    var thumbnailVisibleActions: [ThumbnailAction] {
        get {
            guard let data = thumbnailVisibleActionsJSON.data(using: .utf8),
                  let actions = try? JSONDecoder().decode([ThumbnailAction].self, from: data)
            else { return ThumbnailAction.defaultVisibleActions }
            return ThumbnailAction.normalized(actions)
        }
        set {
            let normalized = ThumbnailAction.normalized(newValue)
            guard let data = try? JSONEncoder().encode(normalized),
                  let json = String(data: data, encoding: .utf8)
            else { return }
            thumbnailVisibleActionsJSON = json
            objectWillChange.send()
        }
    }

    func setThumbnailAction(_ action: ThumbnailAction, visible: Bool) {
        var actions = thumbnailVisibleActions
        if visible {
            guard !actions.contains(action), actions.count < 4 else { return }
            actions.append(action)
        } else {
            actions.removeAll { $0 == action }
        }
        thumbnailVisibleActions = actions
    }

    var thumbnailSwipeBindings: ThumbnailSwipeBindings {
        get {
            guard let data = thumbnailSwipeBindingsJSON.data(using: .utf8),
                  let bindings = try? JSONDecoder().decode(ThumbnailSwipeBindings.self, from: data)
            else { return .defaults }
            return bindings
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8)
            else { return }
            thumbnailSwipeBindingsJSON = json
            objectWillChange.send()
        }
    }

    func setThumbnailSwipeAction(
        _ action: ThumbnailGestureAction,
        fingers: ThumbnailSwipeFingerCount,
        direction: ThumbnailSwipeDirection
    ) {
        var bindings = thumbnailSwipeBindings
        bindings.set(action, for: fingers, direction: direction)
        thumbnailSwipeBindings = bindings
    }

    func resetThumbnailSwipeBindings() {
        thumbnailSwipeBindingsJSON = ""
        objectWillChange.send()
    }

    func resetThumbnailSettings() {
        thumbnailVisibleActions = ThumbnailAction.defaultVisibleActions
        showThumbnailActionsAlways = false
        thumbnailDuration = 6.0
        thumbnailSwipeBindings = .defaults
    }

    @AppStorage("lastRegionCocoaX") private var lastRegionCocoaX: Double = 0
    @AppStorage("lastRegionCocoaY") private var lastRegionCocoaY: Double = 0
    @AppStorage("lastRegionCocoaWidth") private var lastRegionCocoaWidth: Double = 0
    @AppStorage("lastRegionCocoaHeight") private var lastRegionCocoaHeight: Double = 0
    @AppStorage("lastRegionDisplayID") private var lastRegionDisplayIDRaw: Int = 0
    @AppStorage("hasLastCaptureRegion") private var hasLastCaptureRegion: Bool = false

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
            .appendingPathComponent("Aeroshot", isDirectory: true)
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

    /// Stored bindings that duplicate another action's hotkey (stored or default) are
    /// dropped so two actions never resolve to the same chord; disabled bindings are kept.
    static func resolvedHotkeys(stored: [String: Hotkey]) -> [HotkeyAction: Hotkey] {
        var result: [HotkeyAction: Hotkey] = [:]
        for action in HotkeyAction.allCases {
            guard let hotkey = stored[action.rawValue] else { continue }
            if hotkey.keyCode == 0 && hotkey.modifiers == 0 {
                result[action] = hotkey
                continue
            }
            let claimedByEarlierStored = result.values.contains { $0 == hotkey }
            let claimedByDefault = HotkeyAction.allCases.contains { other in
                other != action && stored[other.rawValue] == nil && other.defaultHotkey == hotkey
            }
            if !claimedByEarlierStored && !claimedByDefault {
                result[action] = hotkey
            }
        }
        for action in HotkeyAction.allCases where result[action] == nil {
            result[action] = action.defaultHotkey
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
        return reserveUniqueOutputURL(filename: name, in: saveDirectory)
    }

    func newRecordingURL() -> URL {
        let prefix = recordingFormat == .gif ? "Recording" : "Screen Recording"
        let name = formattedFilename(
            template: recordingFilenameTemplate.isEmpty ? "\(prefix) {date} at {time}" : recordingFilenameTemplate,
            typeLabel: prefix,
            fileExtension: recordingFormat.fileExtension
        )
        return reserveUniqueOutputURL(filename: name, in: saveDirectory)
    }

    private func reserveUniqueOutputURL(filename: String, in directory: URL) -> URL {
        let url = Self.uniqueOutputURL(
            filename: filename,
            in: directory,
            reservedPaths: reservedOutputPaths
        )
        reservedOutputPaths.insert(url.path)
        return url
    }

    /// Finds a non-overwriting output URL, appending `-1`, `-2`, and so on when
    /// the template has already produced a name used on disk or in this session.
    static func uniqueOutputURL(filename: String, in directory: URL, reservedPaths: Set<String>) -> URL {
        let candidate = directory.appendingPathComponent(filename)
        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension

        var index = 0
        while true {
            let suffix = index == 0 ? "" : "-\(index)"
            let name = ext.isEmpty ? "\(base)\(suffix)" : "\(base)\(suffix).\(ext)"
            let url = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path), !reservedPaths.contains(url.path) {
                return url
            }
            index += 1
        }
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

    var selectionAspectLock: SelectionAspectLock {
        get { SelectionAspectLock(rawValue: selectionAspectLockRaw) ?? .auto }
        set { selectionAspectLockRaw = newValue.rawValue; objectWillChange.send() }
    }

    func hotkeyProfiles() -> [HotkeyProfile] {
        HotkeyProfileStore.load(from: hotkeyProfilesJSON)
    }

    func setHotkeyProfiles(_ profiles: [HotkeyProfile]) {
        hotkeyProfilesJSON = HotkeyProfileStore.encode(profiles)
        objectWillChange.send()
    }

    func effectiveHotkeys(for bundleID: String?) -> [HotkeyAction: Hotkey] {
        let base = hotkeys()
        guard let bundleID,
              let profile = HotkeyProfileStore.profile(for: bundleID, in: hotkeyProfiles()) else {
            return base
        }
        return profile.resolvedHotkeys(fallback: base)
    }

    var activeCaptureProfile: CaptureProfile {
        CaptureProfile.profile(for: activeCaptureProfileID) ?? .standard
    }

    var runsHeadless: Bool {
        !showInMenuBar && !showInDock
    }

    var appPresenceSummary: String {
        switch (showInMenuBar, showInDock) {
        case (true, true): return "Menu bar and Dock"
        case (true, false): return "Menu bar only"
        case (false, true): return "Dock only"
        case (false, false): return "Background only"
        }
    }

    func applyCaptureProfile(_ profile: CaptureProfile) {
        activeCaptureProfileID = profile.id
        profile.apply(to: self)
        objectWillChange.send()
    }

    func saveLastCaptureRegion(cocoaRect: CGRect, displayID: CGDirectDisplayID) {
        lastRegionCocoaX = cocoaRect.origin.x
        lastRegionCocoaY = cocoaRect.origin.y
        lastRegionCocoaWidth = cocoaRect.width
        lastRegionCocoaHeight = cocoaRect.height
        lastRegionDisplayIDRaw = Int(displayID)
        hasLastCaptureRegion = true
    }

    func clearLastCaptureRegion() {
        hasLastCaptureRegion = false
    }

    func lastCaptureRegion(matching displays: [DisplayInfo]) -> (cocoaRect: CGRect, display: DisplayInfo)? {
        guard hasLastCaptureRegion, lastRegionCocoaWidth >= 2, lastRegionCocoaHeight >= 2 else { return nil }
        let rect = CGRect(
            x: lastRegionCocoaX,
            y: lastRegionCocoaY,
            width: lastRegionCocoaWidth,
            height: lastRegionCocoaHeight
        )
        guard let display = displays.first(where: { $0.displayID == CGDirectDisplayID(lastRegionDisplayIDRaw) }) else {
            return nil
        }
        return (rect, display)
    }

    func resetAllToDefaults() {
        saveDirectoryPath = Self.defaultSaveDirectory.path
        imageFormatRaw = ImageFormat.png.rawValue
        jpegQuality = 0.9
        downscaleRetina = false
        copyToClipboardAfterCapture = false
        saveToDiskAfterCapture = true
        showThumbnailAfterCapture = true
        playCaptureSound = true
        selectedCaptureSound = "aeroshot_soft_bloop"
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
        resetThumbnailSettings()
        beautifyEnabledDefault = false
        beautifyPadding = 64
        beautifyCornerRadius = 12
        beautifyShadowRadius = 30
        beautifyShadowOpacity = 0.45
        beautifyGradientRaw = BeautifySettings.GradientPreset.indigo.rawValue
        beautifyAspectRaw = BeautifySettings.AspectPreset.auto.rawValue
        activeCaptureProfileID = CaptureProfile.standard.id
        captureDelaySeconds = 0
        freezeScreenDuringCapture = false
        recallLastRegionEnabled = true
        allInOneCaptureImmediately = false
        lastCaptureIntentKey = CaptureIntent.area.storageKey
        selectionAspectLockRaw = SelectionAspectLock.auto.rawValue
        recordMicrophone = false
        recordingMicrophoneDeviceID = ""
        showWebcamOverlay = false
        uploadWebhookURL = ""
        uploadAfterCapture = false
        copyLinkAfterUpload = false
        hotkeyProfilesJSON = ""
        showInMenuBar = true
        showInDock = false
        hasCompletedOnboarding = false
        hasDismissedInputMonitoringGuide = false
        shareSafeRedactionStyleRaw = ShareSafeRedactionStyle.blur.rawValue
        shareSafeSmartScan = false
        shareSafePrivacyFilter = false
        shareSafeRedactBeforeSharing = true
        shareSafeAutoRedactAfterCapture = false
        hasLastCaptureRegion = false
        lastRegionCocoaX = 0
        lastRegionCocoaY = 0
        lastRegionCocoaWidth = 0
        lastRegionCocoaHeight = 0
        lastRegionDisplayIDRaw = 0
        objectWillChange.send()
    }

    func exportProfile() -> Data? {
        let profile = SettingsProfile(from: self)
        return try? JSONEncoder().encode(profile)
    }

    func importProfile(from data: Data) throws {
        // Merge an older, partial profile over the current schema before decoding.
        // This lets profiles survive newly added settings without discarding the
        // user's existing values for fields that did not exist at export time.
        let incoming = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let incoming else { throw CocoaError(.fileReadCorruptFile) }
        guard let currentData = exportProfile(),
              var merged = try JSONSerialization.jsonObject(with: currentData) as? [String: Any]
        else { throw CocoaError(.coderInvalidValue) }
        for (key, value) in incoming { merged[key] = value }
        // The privacy filter is an opt-in download-backed capability. Older
        // profiles must never turn it on merely because the importing machine
        // happens to have it enabled already.
        if incoming["shareSafePrivacyFilter"] == nil {
            merged.removeValue(forKey: "shareSafePrivacyFilter")
        }
        let mergedData = try JSONSerialization.data(withJSONObject: merged)
        let profile = try JSONDecoder().decode(SettingsProfile.self, from: mergedData)
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
    var selectedCaptureSound: String
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
    var thumbnailVisibleActions: [ThumbnailAction]
    var thumbnailSwipeBindings: ThumbnailSwipeBindings
    var beautifyEnabledDefault: Bool
    var beautifyPadding: Double
    var beautifyCornerRadius: Double
    var beautifyShadowRadius: Double
    var beautifyShadowOpacity: Double
    var beautifyGradientRaw: String
    var beautifyAspectRaw: String
    var activeCaptureProfileID: String
    var captureDelaySeconds: Int
    var freezeScreenDuringCapture: Bool?
    var recallLastRegionEnabled: Bool
    var lastCaptureIntentKey: String
    var selectionAspectLockRaw: String
    var recordMicrophone: Bool
    var recordingMicrophoneDeviceID: String?
    var showWebcamOverlay: Bool
    var hotkeyProfilesJSON: String
    var showInMenuBar: Bool
    var showInDock: Bool
    var shareSafeRedactionStyleRaw: String
    var shareSafeSmartScan: Bool
    var shareSafePrivacyFilter: Bool?
    var shareSafeRedactBeforeSharing: Bool
    var shareSafeAutoRedactAfterCapture: Bool
    var hasLastCaptureRegion: Bool
    var lastRegionCocoaX: Double
    var lastRegionCocoaY: Double
    var lastRegionCocoaWidth: Double
    var lastRegionCocoaHeight: Double
    var lastRegionDisplayID: UInt32

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
        selectedCaptureSound = store.selectedCaptureSound
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
        thumbnailVisibleActions = store.thumbnailVisibleActions
        thumbnailSwipeBindings = store.thumbnailSwipeBindings
        beautifyEnabledDefault = store.beautifyEnabledDefault
        beautifyPadding = store.beautifyPadding
        beautifyCornerRadius = store.beautifyCornerRadius
        beautifyShadowRadius = store.beautifyShadowRadius
        beautifyShadowOpacity = store.beautifyShadowOpacity
        beautifyGradientRaw = store.beautifyGradientPreset.rawValue
        beautifyAspectRaw = store.beautifyAspectPreset.rawValue
        activeCaptureProfileID = store.activeCaptureProfileID
        captureDelaySeconds = store.captureDelaySeconds
        freezeScreenDuringCapture = store.freezeScreenDuringCapture
        recallLastRegionEnabled = store.recallLastRegionEnabled
        lastCaptureIntentKey = store.lastCaptureIntentKey
        selectionAspectLockRaw = store.selectionAspectLock.rawValue
        recordMicrophone = store.recordMicrophone
        recordingMicrophoneDeviceID = store.recordingMicrophoneDeviceID.isEmpty ? nil : store.recordingMicrophoneDeviceID
        showWebcamOverlay = store.showWebcamOverlay
        hotkeyProfilesJSON = UserDefaults.standard.string(forKey: "hotkeyProfilesJSON") ?? ""
        showInMenuBar = store.showInMenuBar
        showInDock = store.showInDock
        shareSafeRedactionStyleRaw = store.shareSafeRedactionStyle.rawValue
        shareSafeSmartScan = store.shareSafeSmartScan
        shareSafePrivacyFilter = store.shareSafePrivacyFilter
        shareSafeRedactBeforeSharing = store.shareSafeRedactBeforeSharing
        shareSafeAutoRedactAfterCapture = store.shareSafeAutoRedactAfterCapture
        let defaults = UserDefaults.standard
        hasLastCaptureRegion = defaults.bool(forKey: "hasLastCaptureRegion")
        lastRegionCocoaX = defaults.double(forKey: "lastRegionCocoaX")
        lastRegionCocoaY = defaults.double(forKey: "lastRegionCocoaY")
        lastRegionCocoaWidth = defaults.double(forKey: "lastRegionCocoaWidth")
        lastRegionCocoaHeight = defaults.double(forKey: "lastRegionCocoaHeight")
        lastRegionDisplayID = UInt32(defaults.integer(forKey: "lastRegionDisplayID"))
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
        store.selectedCaptureSound = selectedCaptureSound
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
        store.thumbnailVisibleActions = thumbnailVisibleActions
        store.thumbnailSwipeBindings = thumbnailSwipeBindings
        store.beautifyEnabledDefault = beautifyEnabledDefault
        store.beautifyPadding = beautifyPadding
        store.beautifyCornerRadius = beautifyCornerRadius
        store.beautifyShadowRadius = beautifyShadowRadius
        store.beautifyShadowOpacity = beautifyShadowOpacity
        store.beautifyGradientPreset = BeautifySettings.GradientPreset(rawValue: beautifyGradientRaw) ?? .indigo
        store.beautifyAspectPreset = BeautifySettings.AspectPreset(rawValue: beautifyAspectRaw) ?? .auto
        store.activeCaptureProfileID = activeCaptureProfileID
        store.captureDelaySeconds = captureDelaySeconds
        store.freezeScreenDuringCapture = freezeScreenDuringCapture ?? false
        store.recallLastRegionEnabled = recallLastRegionEnabled
        store.lastCaptureIntentKey = lastCaptureIntentKey
        store.selectionAspectLock = SelectionAspectLock(rawValue: selectionAspectLockRaw) ?? .auto
        store.recordMicrophone = recordMicrophone
        store.recordingMicrophoneDeviceID = recordingMicrophoneDeviceID ?? ""
        store.showWebcamOverlay = showWebcamOverlay
        UserDefaults.standard.set(hotkeyProfilesJSON, forKey: "hotkeyProfilesJSON")
        store.showInMenuBar = showInMenuBar
        store.showInDock = showInDock
        store.shareSafeRedactionStyle = ShareSafeRedactionStyle(rawValue: shareSafeRedactionStyleRaw) ?? .blur
        store.shareSafeSmartScan = shareSafeSmartScan
        store.shareSafePrivacyFilter = shareSafePrivacyFilter ?? false
        store.shareSafeRedactBeforeSharing = shareSafeRedactBeforeSharing
        store.shareSafeAutoRedactAfterCapture = shareSafeAutoRedactAfterCapture
        if hasLastCaptureRegion {
            store.saveLastCaptureRegion(
                cocoaRect: CGRect(x: lastRegionCocoaX, y: lastRegionCocoaY, width: lastRegionCocoaWidth, height: lastRegionCocoaHeight),
                displayID: lastRegionDisplayID
            )
        } else {
            store.clearLastCaptureRegion()
        }
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
