import AppKit
import SwiftUI

enum SettingsPermissions {
    static let totalCount = 3

    static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }
    static var inputMonitoringGranted: Bool { HotkeyManager.hasInputMonitoringAccess }
    static var accessibilityGranted: Bool { ScrollEventPoster.hasAccessibilityAccess }

    static var grantedCount: Int {
        [screenRecordingGranted, inputMonitoringGranted, accessibilityGranted].filter { $0 }.count
    }

    static var allGranted: Bool { grantedCount == totalCount }

    static var healthLabel: String { "\(grantedCount) of \(totalCount) granted" }
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
        .init(id: "clipboard", title: "Copy to clipboard", detail: "After capture", pane: .capture, keywords: ["paste", "pasteboard"]),
        .init(id: "save-disk", title: "Save to disk", detail: "After capture", pane: .capture, keywords: ["file", "write", "auto save"]),
        .init(id: "thumbnail", title: "Quick-access thumbnail", detail: "After capture", pane: .capture, keywords: ["preview", "floating", "corner"]),
        .init(id: "sound", title: "Play capture sound", detail: "After capture", pane: .capture, keywords: ["audio", "shutter"]),
        .init(id: "thumb-duration", title: "Thumbnail duration", detail: "Preview timing", pane: .capture, keywords: ["seconds", "timer", "dismiss"]),
        .init(id: "save-folder", title: "Save location", detail: "Output folder", pane: .output, keywords: ["directory", "path", "pictures"]),
        .init(id: "format", title: "Image format", detail: "PNG, JPEG, HEIC", pane: .output, keywords: ["png", "jpeg", "heic", "export"]),
        .init(id: "jpeg-quality", title: "JPEG compression quality", detail: "Output quality", pane: .output, keywords: ["compression", "quality"]),
        .init(id: "retina", title: "Downscale Retina captures", detail: "1× export", pane: .output, keywords: ["2x", "resolution", "scale"]),
        .init(id: "hotkeys", title: "Keyboard shortcuts", detail: "Global shortcuts", pane: .shortcuts, keywords: ["keyboard", "binding", "hotkey"]),
        .init(id: "reset-hotkeys", title: "Reset shortcuts", detail: "Restore defaults", pane: .shortcuts, keywords: ["default", "restore"]),
        .init(id: "recording-format", title: "Recording format", detail: "MP4 or GIF", pane: .recording, keywords: ["video", "mp4", "gif", "animated"]),
        .init(id: "system-audio", title: "Record system audio", detail: "Recording options", pane: .recording, keywords: ["sound", "audio", "mp4"]),
        .init(id: "click-highlight", title: "Highlight clicks", detail: "Recording options", pane: .recording, keywords: ["mouse", "ripple", "cursor"]),
        .init(id: "scrolling", title: "Scrolling capture", detail: "Auto-scroll", pane: .recording, keywords: ["scroll", "long page", "stitch"]),
        .init(id: "gif-fps", title: "GIF frame rate", detail: "Advanced GIF", pane: .recording, keywords: ["fps", "frames"]),
        .init(id: "permissions", title: "System permissions", detail: "Privacy & access", pane: .system, keywords: ["screen recording", "input monitoring", "accessibility"]),
        .init(id: "ocr-history", title: "OCR history", detail: "Advanced", pane: .system, keywords: ["text", "ocr", "history"]),
    ]

    static func results(for query: String) -> [SettingsSearchEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return catalog.filter { $0.matches(q) }
    }
}
