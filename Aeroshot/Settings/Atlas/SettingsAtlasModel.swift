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
        case .capture: "Capture settings."
        case .craft: "Editor settings."
        case .deliver: "Output settings."
        case .foundation: "App settings."
        }
    }
}

enum SettingsAtlasCategoryID: String, CaseIterable, Identifiable {
    case capture
    case screenRecording
    case gifRecording
    case screenshotEditor
    case export
    case sharingUploads
    case general
    case hotkeys
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
}

extension SettingsAtlasCategory {
    static let all: [SettingsAtlasCategory] = [
        .init(id: .capture, name: "Capture", band: .capture, pane: .capture, symbol: "camera.viewfinder", blurb: "Capture options and thumbnail actions.", intro: "Set the capture options that Aeroshot uses."),
        .init(id: .screenRecording, name: "Screen Recording", band: .capture, pane: .recording, symbol: "record.circle", blurb: "Video recording inputs and output.", intro: "Set the video recording options that Aeroshot uses."),
        .init(id: .gifRecording, name: "GIF Recording", band: .capture, pane: .recording, symbol: "film", blurb: "GIF frame rate and frame limit.", intro: "Set the limits for GIF recording."),
        .init(id: .screenshotEditor, name: "Screenshot Editor", band: .craft, pane: .editor, symbol: "rectangle.and.pencil.and.ellipsis", blurb: "Screenshot editor defaults.", intro: "Set the screenshot editor defaults."),
        .init(id: .export, name: "Export", band: .deliver, pane: .output, symbol: "square.and.arrow.up", blurb: "Formats, names, and output folders.", intro: "Set how Aeroshot writes output files."),
        .init(id: .sharingUploads, name: "Uploads", band: .deliver, pane: .output, symbol: "link", blurb: "Webhook upload options.", intro: "Set the webhook upload options."),
        .init(id: .general, name: "General", band: .foundation, pane: .system, symbol: "gearshape", blurb: "App presence and capture profiles.", intro: "Set the main app options."),
        .init(id: .hotkeys, name: "Hotkeys", band: .foundation, pane: .shortcuts, symbol: "keyboard", blurb: "Keyboard shortcuts and access.", intro: "Set the keyboard shortcuts that Aeroshot uses."),
        .init(id: .privacy, name: "Privacy & Security", band: .foundation, pane: .system, symbol: "lock.shield", blurb: "Redaction and macOS permissions.", intro: "Set redaction options and grant required permissions."),
        .init(id: .advanced, name: "Advanced", band: .foundation, pane: .system, symbol: "slider.horizontal.3", blurb: "Automation, profiles, and reset.", intro: "Use automation actions, manage profiles, or reset settings.")
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
