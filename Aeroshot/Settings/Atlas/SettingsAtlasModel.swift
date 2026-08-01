import SwiftUI

enum SettingsAtlasBand: String, CaseIterable, Identifiable {
    case capture
    case craft
    case deliver
    case foundation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture: "CAPTURE"
        case .craft: "CRAFT"
        case .deliver: "DELIVER"
        case .foundation: "FOUNDATION"
        }
    }

    var blurb: String {
        switch self {
        case .capture: "Getting pixels off the screen."
        case .craft: "Shaping what you captured."
        case .deliver: "Getting it to someone else."
        case .foundation: "The rules everything else runs on."
        }
    }
}

enum SettingsAtlasCategoryID: String, CaseIterable, Identifiable {
    case capture
    case quickAnnotation
    case screenRecording
    case gifRecording
    case screenshotEditor
    case videoEditor
    case mediaLibrary
    case export
    case sharingUploads
    case general
    case hotkeys
    case appearance
    case accessibility
    case privacy
    case advanced

    var id: String { rawValue }
}

struct SettingsAtlasCategory: Identifiable {
    let id: SettingsAtlasCategoryID
    let name: String
    let band: SettingsAtlasBand
    let pane: SettingsPane
    let symbol: String
    let blurb: String
    let intro: String
    let chips: [String]

    var settingCount: Int {
        max(1, SettingsSearchEntry.catalog.filter { $0.pane == pane }.count)
    }

    var deepLink: String { "aeroshot://settings/\(id.rawValue)" }

    var needsAttention: Bool {
        switch id {
        case .screenRecording, .privacy:
            !SettingsPermissions.screenRecordingGranted
        case .hotkeys:
            !SettingsPermissions.accessibilityGranted
        default:
            false
        }
    }

    @MainActor
    func liveChips(settings: SettingsStore) -> [String] {
        switch id {
        case .capture:
            let delay = settings.captureDelaySeconds == 0 ? "Instant" : "\(settings.captureDelaySeconds)s delay"
            return [settings.activeCaptureProfile.name, delay, settings.downscaleRetina ? "Retina @1x" : "Retina @2x"]
        case .quickAnnotation:
            return [settings.shareSafeRedactionStyle.displayName, settings.beautifyEnabledDefault ? "Beautify on" : "Plain canvas", "Local"]
        case .screenRecording:
            return [settings.recordingFormat.displayName, settings.recordSystemAudio ? "System audio" : "Mic optional", settings.highlightClicksDuringRecording ? "Click halo" : "Clean cursor"]
        case .gifRecording:
            return ["\(settings.gifFPS) fps", "\(settings.gifMaxFrames) frames", settings.recordingFormat.displayName]
        case .screenshotEditor:
            return [settings.beautifyAspectPreset.displayName, "\(Int(settings.beautifyPadding)) pt padding", settings.beautifyEnabledDefault ? "Beautify" : "Raw"]
        case .videoEditor:
            return [settings.recordingFormat.displayName, settings.addRecordingsToHistory ? "History" : "No history", "Native"]
        case .mediaLibrary:
            return [settings.saveDirectory.lastPathComponent, settings.addOCRCapturesToHistory ? "OCR indexed" : "Images only", "Local files"]
        case .export:
            return [settings.imageFormat.displayName, settings.saveToDiskAfterCapture ? "Auto-save" : "Manual save", settings.filenameTemplate]
        case .sharingUploads:
            return [settings.uploadAfterCapture ? "Auto-upload" : "On demand", settings.copyLinkAfterUpload ? "Auto-copy" : "Review link", settings.uploadWebhookURL.isEmpty ? "No service" : "Webhook"]
        case .general:
            return [settings.showInMenuBar ? "Menu bar" : "Hidden", settings.showInDock ? "Dock" : "Background", settings.appPresenceSummary]
        case .hotkeys:
            let bound = settings.hotkeys().values.filter { $0.keyCode != 0 || $0.modifiers != 0 }.count
            return ["\(bound) bound", "Global", settings.hotkeys()[.allInOne]?.displayString ?? "⌘Space"]
        case .appearance:
            return ["System", "Coral", "Regular density"]
        case .accessibility:
            return ["44 pt targets", "VoiceOver", "Reduce motion"]
        case .privacy:
            return [settings.shareSafeRedactBeforeSharing ? "Redact before share" : "Review before share", settings.shareSafeSmartScan ? "Smart scan" : "On-device", SettingsPermissions.healthLabel]
        case .advanced:
            return ["Native", "Local diagnostics", "Profiles"]
        }
    }
}

extension SettingsAtlasCategory {
    static let all: [SettingsAtlasCategory] = [
        .init(
            id: .capture,
            name: "Capture",
            band: .capture,
            pane: .capture,
            symbol: "camera.viewfinder",
            blurb: "Modes, timing, and what the selection surface does.",
            intro: "The moment between pressing the shortcut and having a picture. These controls shorten that gap or remove a decision from it.",
            chips: ["Region", "Delay", "Retina"]
        ),
        .init(
            id: .quickAnnotation,
            name: "Quick Annotation",
            band: .capture,
            pane: .editor,
            symbol: "pencil.tip.crop.circle",
            blurb: "The compact tool ring that lives on the capture itself.",
            intro: "The lightweight pass most captures need—an arrow, a box, a text note, or a blur—without losing the capture context.",
            chips: ["7 tools", "Coral", "Local"]
        ),
        .init(
            id: .screenRecording,
            name: "Screen Recording",
            band: .capture,
            pane: .recording,
            symbol: "record.circle",
            blurb: "Video capture, audio sources, and on-screen input.",
            intro: "Recording settings are chosen once and trusted for months, so the live controls stay explicit about their cost in quality, time, and file size.",
            chips: ["MP4", "Audio", "Cursor"]
        ),
        .init(
            id: .gifRecording,
            name: "GIF Recording",
            band: .capture,
            pane: .recording,
            symbol: "film",
            blurb: "Loops with a hard frame and size budget.",
            intro: "A GIF is a negotiation between length, frame rate, and size. Set the budget first and the rest of the workflow follows it.",
            chips: ["FPS", "Frames", "Bounded"]
        ),
        .init(
            id: .screenshotEditor,
            name: "Screenshot Editor",
            band: .craft,
            pane: .editor,
            symbol: "rectangle.and.pencil.and.ellipsis",
            blurb: "Canvas, guides, layers, and the intelligence layer.",
            intro: "The full canvas. These defaults decide how a finished screenshot looks before you touch a single annotation.",
            chips: ["Canvas", "Guides", "OCR"]
        ),
        .init(
            id: .videoEditor,
            name: "Video & GIF Editor",
            band: .craft,
            pane: .recording,
            symbol: "timeline.selection",
            blurb: "A timeline that separates motion, clicks, speech, and idle.",
            intro: "The timeline is the product. These settings keep playback, recovery, and media history predictable.",
            chips: ["Timeline", "Recovery", "Native"]
        ),
        .init(
            id: .mediaLibrary,
            name: "Media Library",
            band: .craft,
            pane: .output,
            symbol: "square.stack.3d.up",
            blurb: "Where everything lands and how long it stays.",
            intro: "The library is a folder on disk first and a history index second. You should always be able to find files without Aeroshot running.",
            chips: ["Local", "History", "OCR"]
        ),
        .init(
            id: .export,
            name: "Export",
            band: .deliver,
            pane: .output,
            symbol: "square.and.arrow.up",
            blurb: "Formats, naming, destinations, and presets.",
            intro: "Export settings exist so the export dialog can disappear. Configure once, then keep every share one keystroke away.",
            chips: ["PNG", "Naming", "Presets"]
        ),
        .init(
            id: .sharingUploads,
            name: "Sharing & Uploads",
            band: .deliver,
            pane: .output,
            symbol: "link",
            blurb: "Links, expiry, and where uploads go.",
            intro: "Sharing is an explicit handoff. Destinations, returned links, and privacy checks stay visible at the point of delivery.",
            chips: ["Webhook", "Copy link", "Review"]
        ),
        .init(
            id: .general,
            name: "General",
            band: .foundation,
            pane: .system,
            symbol: "gearshape",
            blurb: "Launch, presence, session, and profiles.",
            intro: "The rules for how Aeroshot starts, stays visible, and remembers the way you work.",
            chips: ["Menu bar", "Profiles", "Session"]
        ),
        .init(
            id: .hotkeys,
            name: "Hotkeys",
            band: .foundation,
            pane: .shortcuts,
            symbol: "keyboard",
            blurb: "Global and app-specific bindings.",
            intro: "Shortcuts are the fastest route through Aeroshot. Conflicts stay visible and every action remains reachable from the keyboard.",
            chips: ["Global", "Per-app", "Conflicts"]
        ),
        .init(
            id: .appearance,
            name: "Appearance",
            band: .foundation,
            pane: .system,
            symbol: "circle.lefthalf.filled",
            blurb: "Theme, accent, density, surfaces, and motion.",
            intro: "Choose how much chrome you want around the work. The settings window follows the system unless you choose a fixed appearance.",
            chips: ["System", "Coral", "Motion"]
        ),
        .init(
            id: .accessibility,
            name: "Accessibility",
            band: .foundation,
            pane: .system,
            symbol: "accessibility",
            blurb: "Motion, contrast, targets, and keyboard-only use.",
            intro: "Every visual shortcut has a readable alternative. These controls keep capture and settings usable with VoiceOver, contrast, and reduced motion.",
            chips: ["Contrast", "VoiceOver", "44 pt"]
        ),
        .init(
            id: .privacy,
            name: "Privacy & Security",
            band: .foundation,
            pane: .system,
            symbol: "lock.shield",
            blurb: "Local-only mode, redaction, exclusions, and permissions.",
            intro: "Sensitive content is handled before it leaves the Mac. Permission state and sharing safeguards are never hidden behind a secondary screen.",
            chips: ["Local-only", "Redaction", "Permissions"]
        ),
        .init(
            id: .advanced,
            name: "Advanced",
            band: .foundation,
            pane: .system,
            symbol: "slider.horizontal.3",
            blurb: "Performance, diagnostics, automation, and reset.",
            intro: "Power-user controls belong here: diagnostics, exported profiles, automation behavior, and safe reset paths.",
            chips: ["Diagnostics", "Automation", "Reset"]
        )
    ]

    static func categories(in band: SettingsAtlasBand) -> [SettingsAtlasCategory] {
        all.filter { $0.band == band }
    }

    static func category(for id: SettingsAtlasCategoryID) -> SettingsAtlasCategory {
        all.first { $0.id == id } ?? all[0]
    }
}

enum SettingsAtlasRoute: Equatable {
    case atlas
    case category(SettingsAtlasCategoryID)
}

struct SettingsAtlasPaletteItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let categoryID: SettingsAtlasCategoryID
    let value: String?
    let isToggleable: Bool
}

enum SettingsAtlasAppearance: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var label: String {
        rawValue.uppercased()
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }
}
