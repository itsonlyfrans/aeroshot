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
        // Keep the Atlas counts tied to the mockup's category model rather than
        // the legacy pane catalog (several Atlas territories share a pane).
        switch id {
        case .capture: 28
        case .quickAnnotation: 15
        case .screenRecording: 23
        case .gifRecording: 13
        case .screenshotEditor: 24
        case .videoEditor: 19
        case .mediaLibrary: 14
        case .export: 12
        case .sharingUploads: 4
        case .general: 17
        case .hotkeys: 19
        case .appearance: 15
        case .accessibility: 16
        case .privacy: 16
        case .advanced: 17
        }
    }

    var deepLink: String {
        let mockupID: String
        switch id {
        case .capture: mockupID = "capture"
        case .quickAnnotation: mockupID = "annot"
        case .screenRecording: mockupID = "rec"
        case .gifRecording: mockupID = "gif"
        case .screenshotEditor: mockupID = "editor"
        case .videoEditor: mockupID = "video"
        case .mediaLibrary: mockupID = "library"
        case .export: mockupID = "export"
        case .sharingUploads: mockupID = "share"
        case .general: mockupID = "general"
        case .hotkeys: mockupID = "keys"
        case .appearance: mockupID = "look"
        case .accessibility: mockupID = "access"
        case .privacy: mockupID = "privacy"
        case .advanced: mockupID = "adv"
        }
        return "aeroshot://settings/\(mockupID)"
    }

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

    var previewNote: String {
        switch id {
        case .capture: "The selection border is a control surface: drag edges to resize, type exact dimensions, or press A to annotate before release."
        case .quickAnnotation: "The ring attaches to the nearest free edge and flips side when it would cover content."
        case .screenRecording: "The recording bar stays keyboard reachable and collapses to a single dot after inactivity."
        case .gifRecording: "The budget meter is live: frame rate and width re-run the estimate against the current buffer."
        case .screenshotEditor: "Presentation backgrounds render at the real export size, so the thumbnail is literal."
        case .videoEditor: "Lanes are semantic: movement, clicks, speech, idle, and annotations. Idle is always the coral lane."
        case .mediaLibrary: "Folder structure is literal. The pattern chosen here is exactly what appears in Finder."
        case .export: "The filename preview updates as you type so token mistakes are visible before they hit disk."
        case .sharingUploads: "The upload card shows whether the configured webhook and automatic upload are enabled."
        case .general: "Startup preview shows the exact combination of menu bar, Dock, and first window configured."
        case .hotkeys: "Recording a shortcut checks macOS reserved keys, other running apps, and Aeroshot bindings."
        case .appearance: "The sample surface uses the same primitives as the real app, so radius and density are literal."
        case .accessibility: "The palette shown is the Okabe–Ito colour-blind-safe set used for annotations."
        case .privacy: "Detection runs entirely on device. Found regions are outlined until you accept the suggestion."
        case .advanced: "Cache and memory meters are live. Clearing cache never touches the library, only derived files."
        }
    }

    var nearby: [(SettingsAtlasCategoryID, String)] {
        switch id {
        case .capture: [(.hotkeys, "how you launch it"), (.quickAnnotation, "what happens before release")]
        case .quickAnnotation: [(.screenshotEditor, "full canvas defaults"), (.capture, "selection surface")]
        case .screenRecording: [(.videoEditor, "what happens after capture"), (.gifRecording, "looped exports")]
        case .gifRecording: [(.screenRecording, "source recording"), (.export, "render settings")]
        case .screenshotEditor: [(.appearance, "theme and motion"), (.privacy, "redaction defaults")]
        case .videoEditor: [(.screenRecording, "what produced this footage"), (.export, "render settings")]
        case .mediaLibrary: [(.export, "where files are written"), (.sharingUploads, "optional upload")]
        case .export: [(.sharingUploads, "optional upload"), (.mediaLibrary, "where files land")]
        case .sharingUploads: [(.privacy, "redaction before upload"), (.export, "what gets uploaded")]
        case .general: [(.hotkeys, "how you launch things"), (.appearance, "how it looks when it opens")]
        case .hotkeys: [(.capture, "what these shortcuts trigger"), (.accessibility, "keyboard-only operation")]
        case .appearance: [(.accessibility, "contrast and motion overrides"), (.screenshotEditor, "canvas appearance")]
        case .accessibility: [(.appearance, "theme and motion"), (.hotkeys, "keyboard-first operation")]
        case .privacy: [(.sharingUploads, "what leaves the machine"), (.advanced, "logging and diagnostics")]
        case .advanced: [(.privacy, "logging and data"), (.mediaLibrary, "derived cache files")]
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
            return [settings.uploadWebhookURL.isEmpty ? "No webhook" : "Webhook", settings.uploadAfterCapture ? "Auto-upload" : "Manual", settings.copyLinkAfterUpload ? "Copy link" : "Do not copy"]
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
            intro: "The moment between pressing the shortcut and having a picture. Every setting here shortens that gap or removes a decision from it.",
            chips: ["Region", "3s delay", "Retina @2x"]
        ),
        .init(
            id: .quickAnnotation,
            name: "Quick Annotation",
            band: .capture,
            pane: .editor,
            symbol: "pencil.tip.crop.circle",
            blurb: "The compact tool ring that lives on the capture itself.",
            intro: "The lightweight pass most captures need — an arrow, a box, a blur — without opening the full editor.",
            chips: ["7 tools", "Coral", "Follows cursor"]
        ),
        .init(
            id: .screenRecording,
            name: "Screen Recording",
            band: .capture,
            pane: .recording,
            symbol: "record.circle",
            blurb: "Video capture, audio sources, and on-screen input.",
            intro: "Recording settings are chosen once and then trusted for months, so every one of them shows its cost in file size or CPU right where you set it.",
            chips: ["1080p60", "H.265", "DND on"]
        ),
        .init(
            id: .gifRecording,
            name: "GIF Recording",
            band: .capture,
            pane: .recording,
            symbol: "film",
            blurb: "Loops with a hard size budget you set first.",
            intro: "A GIF is a negotiation between length, size, and colour. Set the budget first and every other control shows what it costs against it.",
            chips: ["12 fps", "640 px", "5 MB cap"]
        ),
        .init(
            id: .screenshotEditor,
            name: "Screenshot Editor",
            band: .craft,
            pane: .editor,
            symbol: "rectangle.and.pencil.and.ellipsis",
            blurb: "Canvas, guides, layers, and the intelligence layer.",
            intro: "The full canvas. Defaults here decide how a finished screenshot looks before you touch a single control.",
            chips: ["Dot grid", "Snap 8 pt", "OCR local"]
        ),
        .init(
            id: .videoEditor,
            name: "Video & GIF Editor",
            band: .craft,
            pane: .recording,
            symbol: "timeline.selection",
            blurb: "A timeline that separates motion, clicks, speech, and idle.",
            intro: "The timeline is the product. Every setting here changes what the lanes show you or how aggressively Aeroshot edits on your behalf.",
            chips: ["5 lanes", "Auto-zoom", "Proxy 540p"]
        ),
        .init(
            id: .mediaLibrary,
            name: "Media Library",
            band: .craft,
            pane: .output,
            symbol: "square.stack.3d.up",
            blurb: "Where everything lands and how long it stays.",
            intro: "The library is a folder on disk first and a database second — you should always be able to find your files without Aeroshot running.",
            chips: ["~/Pictures", "By month", "Trash 30d"]
        ),
        .init(
            id: .export,
            name: "Export",
            band: .deliver,
            pane: .output,
            symbol: "square.and.arrow.up",
            blurb: "Formats, naming, and destinations.",
            intro: "Export settings exist so that the export dialog can disappear. Configure once, then every share is a single keystroke.",
            chips: ["PNG", "{app} {date}", "Save folder"]
        ),
        .init(
            id: .sharingUploads,
            name: "Uploads",
            band: .deliver,
            pane: .output,
            symbol: "link",
            blurb: "Configure an optional HTTPS webhook for captured files.",
            intro: "Aeroshot can send captured files to one HTTPS webhook. Set the endpoint and choose whether to upload automatically.",
            chips: ["Webhook", "Auto-upload", "Copy link"]
        ),
        .init(
            id: .general,
            name: "General",
            band: .foundation,
            pane: .system,
            symbol: "gearshape",
            blurb: "Launch, presence, session, updates, notifications.",
            intro: "The settings a new user meets first and then never opens again. They should be right by default and obvious when they are not.",
            chips: ["Menu bar", "Autosave 30s", "Beta"]
        ),
        .init(
            id: .hotkeys,
            name: "Hotkeys",
            band: .foundation,
            pane: .shortcuts,
            symbol: "keyboard",
            blurb: "Global and app-only bindings with conflict detection.",
            intro: "Global shortcuts compete with the system and with every other app. Aeroshot tells you when you have lost that competition instead of failing silently.",
            chips: ["15 bound", "1 conflict", "⌘Space"]
        ),
        .init(
            id: .appearance,
            name: "Appearance",
            band: .foundation,
            pane: .system,
            symbol: "circle.lefthalf.filled",
            blurb: "Theme, accent, density, surfaces, and motion.",
            intro: "Everything here previews live in the panel beside it. Nothing needs saving, and nothing needs a restart.",
            chips: ["System", "Coral", "Regular"]
        ),
        .init(
            id: .accessibility,
            name: "Accessibility",
            band: .foundation,
            pane: .system,
            symbol: "accessibility",
            blurb: "Motion, contrast, targets, and keyboard-only use.",
            intro: "Custom controls are only defensible if they are as reachable as the system ones they replace. These settings are how that is proved.",
            chips: ["Contrast", "VoiceOver", "44 pt"]
        ),
        .init(
            id: .privacy,
            name: "Privacy & Security",
            band: .foundation,
            pane: .system,
            symbol: "lock.shield",
            blurb: "Redaction, detection, and capture permissions.",
            intro: "A capture tool sees everything on your screen. These controls describe capture permissions, redaction, and detection behavior.",
            chips: ["Auto-redact", "Permissions"]
        ),
        .init(
            id: .advanced,
            name: "Advanced",
            band: .foundation,
            pane: .system,
            symbol: "slider.horizontal.3",
            blurb: "Performance, diagnostics, automation, and reset.",
            intro: "Everything a power user needs and a casual user should never see. Nothing here changes behaviour silently.",
            chips: ["HW encode", "8 GB cache", "API on"]
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
