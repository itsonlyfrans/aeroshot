import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case overview, capture, output, shortcuts, recording, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .capture: return "Capture"
        case .output: return "Output"
        case .shortcuts: return "Shortcuts"
        case .recording: return "Recording"
        case .system: return "System"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return "Your capture setup at a glance"
        case .capture: return "What happens after you shoot"
        case .output: return "Where files go and how they look"
        case .shortcuts: return "Global keyboard controls"
        case .recording: return "Video, GIF, and scrolling"
        case .system: return "Permissions and advanced options"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "sparkles"
        case .capture: return "camera.viewfinder"
        case .output: return "folder"
        case .shortcuts: return "keyboard"
        case .recording: return "record.circle"
        case .system: return "gearshape.2"
        }
    }

    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .overview: return "1"
        case .capture: return "2"
        case .output: return "3"
        case .shortcuts: return "4"
        case .recording: return "5"
        case .system: return "6"
        }
    }

    /// Sections linked from Overview (excludes overview itself).
    static var exploreSections: [SettingsPane] {
        [.capture, .output, .shortcuts, .recording, .system]
    }
}
