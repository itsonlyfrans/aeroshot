import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case overview, capture, output, shortcuts, recording, scrolling, editor, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .capture: return "Capture"
        case .output: return "Output"
        case .shortcuts: return "Shortcuts"
        case .recording: return "Recording"
        case .scrolling: return "Scrolling"
        case .editor: return "Editor"
        case .system: return "System"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return "Your capture setup at a glance"
        case .capture: return "What happens after you shoot"
        case .output: return "Where files go and how they look"
        case .shortcuts: return "Global keyboard controls"
        case .recording: return "Video and GIF exports"
        case .scrolling: return "Long-page stitch captures"
        case .editor: return "Annotation and beautify defaults"
        case .system: return "Permissions and advanced options"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .capture: return "camera.viewfinder"
        case .output: return "folder"
        case .shortcuts: return "keyboard"
        case .recording: return "record.circle"
        case .scrolling: return "arrow.up.and.down.text.horizontal"
        case .editor: return "pencil.tip.crop.circle"
        case .system: return "gearshape.2"
        }
    }

    /// Nav icons stay monochrome so the one accent keeps its one job.
    /// Recording is the sole exception — the hardware red-record convention.
    var tint: Color {
        switch self {
        case .recording: return .red
        default: return .secondary
        }
    }

    /// Sidebar grouping.
    static let navGroups: [(title: String, panes: [SettingsPane])] = [
        ("", [.overview]),
        ("Capture", [.capture, .output, .shortcuts]),
        ("Media", [.recording, .scrolling, .editor]),
        ("System", [.system])
    ]

    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .overview: return "1"
        case .capture: return "2"
        case .output: return "3"
        case .shortcuts: return "4"
        case .recording: return "5"
        case .scrolling: return "6"
        case .editor: return "7"
        case .system: return "8"
        }
    }

    /// Sections linked from Overview (excludes overview itself).
    static var exploreSections: [SettingsPane] {
        [.capture, .output, .shortcuts, .recording, .scrolling, .editor, .system]
    }

    var needsPermissionAttention: Bool {
        switch self {
        case .system:
            return !SettingsPermissions.allGranted
        case .shortcuts, .scrolling:
            return !SettingsPermissions.accessibilityGranted
        default:
            return false
        }
    }
}
