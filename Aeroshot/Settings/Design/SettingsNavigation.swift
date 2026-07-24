import AppKit
import AVFoundation
import SwiftUI

enum SettingsPermissions {
    static let totalCount = 4

    static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }
    static var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    static var cameraGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    static var grantedCount: Int {
        [screenRecordingGranted, accessibilityGranted, microphoneGranted, cameraGranted]
            .filter { $0 }
            .count
    }

    static var allGranted: Bool { grantedCount == totalCount }

    static var healthLabel: String { "\(grantedCount) of \(totalCount) granted" }

    /// Triggers the system TCC prompt so Aeroshot appears in Privacy settings, then opens the pane.
    static func requestScreenRecording(showSettingsIfNeeded: Bool = true) {
        if !screenRecordingGranted {
            _ = CGRequestScreenCaptureAccess()
        }
        if showSettingsIfNeeded, !screenRecordingGranted {
            openScreenRecordingSettings()
        }
    }

    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Triggers the system TCC prompt so Aeroshot appears in Accessibility, then opens the pane.
    static func requestAccessibility(showSettingsIfNeeded: Bool = true) {
        HotkeyManager.requestGlobalHotkeyAccess()
        ScrollEventPoster.requestAccessibilityAccess()
        Task { @MainActor in
            HotkeyManager.shared.refreshMonitors()
            guard showSettingsIfNeeded, !accessibilityGranted else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard !accessibilityGranted else { return }
                ScrollEventPoster.openAccessibilitySettings()
            }
        }
    }

    @MainActor
    @discardableResult
    static func requestMicrophone() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            return await RecordingController.requestMicrophoneAccess()
        } else if !microphoneGranted {
            openPrivacySettings("Privacy_Microphone")
        }
        return microphoneGranted
    }

    @MainActor
    @discardableResult
    static func requestCamera() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            return await RecordingController.requestCameraAccess()
        } else if !cameraGranted {
            openPrivacySettings("Privacy_Camera")
        }
        return cameraGranted
    }

    private static func openPrivacySettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct SettingsNavigateKey: EnvironmentKey {
    static let defaultValue: (SettingsPane) -> Void = { _ in }
}

extension EnvironmentValues {
    var settingsNavigate: (SettingsPane) -> Void {
        get { self[SettingsNavigateKey.self] }
        set { self[SettingsNavigateKey.self] = newValue }
    }
}

struct SettingsSearchEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let pane: SettingsPane
    let keywords: [String]

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return false }
        if title.lowercased().contains(q) { return true }
        if detail.lowercased().contains(q) { return true }
        if pane.title.lowercased().contains(q) { return true }
        return keywords.contains { $0.lowercased().contains(q) }
    }

    static let catalog: [SettingsSearchEntry] = [
        .init(id: "capture-delay", title: "Capture delay", detail: "Self-timer countdown", pane: .capture, keywords: ["timer", "delay", "countdown", "seconds"]),
        .init(id: "last-region", title: "Recall last region", detail: "Repeat previous crop", pane: .capture, keywords: ["last region", "repeat", "recall"]),
        .init(id: "aspect-lock", title: "Selection aspect lock", detail: "16:9 or 1:1 area crop", pane: .capture, keywords: ["aspect", "ratio", "16:9", "1:1", "square"]),
        .init(id: "capture-profile", title: "Capture profile", detail: "Bug Report, Social, Docs presets", pane: .capture, keywords: ["preset", "workflow", "profile", "bug report", "social"]),
        .init(id: "shortcuts-app", title: "macOS Shortcuts", detail: "Automate captures", pane: .shortcuts, keywords: ["shortcuts app", "siri", "automation", "intent"]),
        .init(id: "clipboard", title: "Copy to clipboard", detail: "After capture", pane: .capture, keywords: ["paste", "pasteboard"]),
        .init(id: "save-disk", title: "Save to disk", detail: "After capture", pane: .capture, keywords: ["file", "write", "auto save"]),
        .init(id: "thumbnail", title: "Quick-access thumbnail", detail: "After capture", pane: .capture, keywords: ["preview", "floating", "corner"]),
        .init(id: "sound", title: "Play capture sound", detail: "After capture", pane: .capture, keywords: ["audio", "shutter"]),
        .init(id: "thumb-duration", title: "Thumbnail duration", detail: "Preview timing", pane: .capture, keywords: ["seconds", "timer", "dismiss"]),
        .init(id: "thumbnail-swipes", title: "Thumbnail swipe gestures", detail: "Two- and three-finger actions", pane: .capture, keywords: ["trackpad", "gesture", "dismiss", "tuck", "hide", "pin", "keep", "left", "right", "up", "down"]),
        .init(id: "save-folder", title: "Save location", detail: "Output folder", pane: .output, keywords: ["directory", "path", "pictures"]),
        .init(id: "format", title: "Image format", detail: "PNG, JPEG, HEIC", pane: .output, keywords: ["png", "jpeg", "heic", "export"]),
        .init(id: "jpeg-quality", title: "JPEG compression quality", detail: "Output quality", pane: .output, keywords: ["compression", "quality"]),
        .init(id: "retina", title: "Downscale Retina captures", detail: "1× export", pane: .output, keywords: ["2x", "resolution", "scale"]),
        .init(id: "filename-template", title: "Filename template", detail: "Screenshot naming", pane: .output, keywords: ["name", "pattern", "date", "time", "app"]),
        .init(id: "cloud-upload", title: "Cloud upload", detail: "Webhook after capture", pane: .output, keywords: ["upload", "webhook", "link", "share", "cloud"]),
        .init(id: "hotkeys", title: "Keyboard shortcuts", detail: "Global shortcuts", pane: .shortcuts, keywords: ["keyboard", "binding", "hotkey"]),
        .init(id: "per-app-hotkeys", title: "Per-app overrides", detail: "App-specific shortcuts", pane: .shortcuts, keywords: ["profile", "bundle", "frontmost", "app"]),
        .init(id: "reset-hotkeys", title: "Reset shortcuts", detail: "Restore defaults", pane: .shortcuts, keywords: ["default", "restore"]),
        .init(id: "recording-format", title: "Recording format", detail: "MP4 or GIF", pane: .recording, keywords: ["video", "mp4", "gif", "animated"]),
        .init(id: "system-audio", title: "Record system audio", detail: "Recording options", pane: .recording, keywords: ["sound", "audio", "mp4"]),
        .init(id: "microphone", title: "Record microphone", detail: "Voice in recordings", pane: .recording, keywords: ["mic", "voice", "audio"]),
        .init(id: "webcam-overlay", title: "Webcam overlay", detail: "Picture-in-picture bubble", pane: .recording, keywords: ["camera", "pip", "face", "webcam"]),
        .init(id: "click-highlight", title: "Highlight clicks", detail: "Recording options", pane: .recording, keywords: ["mouse", "ripple", "cursor"]),
        .init(id: "scrolling", title: "Scrolling capture", detail: "Auto-scroll", pane: .scrolling, keywords: ["scroll", "long page", "stitch"]),
        .init(id: "gif-fps", title: "GIF frame rate", detail: "Advanced GIF", pane: .recording, keywords: ["fps", "frames"]),
        .init(id: "editor-open", title: "Open editor after capture", detail: "Editor workflow", pane: .editor, keywords: ["annotate", "edit", "automatic"]),
        .init(id: "editor-ruler", title: "Pixel ruler", detail: "Editor measurement guides", pane: .editor, keywords: ["ruler", "pixels", "measure"]),
        .init(id: "editor-templates", title: "Annotation templates", detail: "Bug report and callout presets", pane: .editor, keywords: ["template", "callout", "bug report", "steps"]),
        .init(id: "beautify-default", title: "Beautify defaults", detail: "Editor presets", pane: .editor, keywords: ["gradient", "shadow", "frame", "sparkles"]),
        .init(id: "permissions", title: "System permissions", detail: "Privacy & access", pane: .system, keywords: ["screen recording", "accessibility", "shortcuts"]),
        .init(id: "menu-bar-presence", title: "Show in menu bar", detail: "App presence", pane: .system, keywords: ["menubar", "status item", "icon", "hidden"]),
        .init(id: "dock-presence", title: "Show in Dock", detail: "App presence", pane: .system, keywords: ["dock", "icon", "background", "headless"]),
        .init(id: "reset-settings", title: "Reset settings", detail: "Restore defaults", pane: .system, keywords: ["default", "restore", "export", "import"]),
        .init(id: "ocr-history", title: "OCR history", detail: "Advanced", pane: .system, keywords: ["text", "ocr", "history"]),
    ]

    static func results(for query: String) -> [SettingsSearchEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return catalog.filter { $0.matches(q) }
    }
}
