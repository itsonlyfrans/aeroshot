import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, shortcuts, recording, advanced, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .shortcuts: return "Shortcuts"
        case .recording: return "Recording"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gear"
        case .shortcuts: return "keyboard"
        case .recording: return "record.circle"
        case .advanced: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .gray
        case .shortcuts: return .purple
        case .recording: return .red
        case .advanced: return .orange
        case .about: return .blue
        }
    }
}

struct SettingsSidebarIcon: View {
    let pane: SettingsPane

    var body: some View {
        Image(systemName: pane.symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(pane.tint.gradient, in: RoundedRectangle(cornerRadius: 6))
    }
}
