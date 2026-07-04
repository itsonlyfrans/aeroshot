import SwiftUI

struct SettingsWindow: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var pane: SettingsPane = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { p in
                Label {
                    Text(p.title)
                } icon: {
                    SettingsSidebarIcon(pane: p)
                }
                .tag(p)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            Group {
                switch pane {
                case .general:
                    GeneralSettingsPane()
                case .shortcuts:
                    ShortcutsSettingsPane()
                case .recording:
                    RecordingSettingsPane()
                case .advanced:
                    AdvancedSettingsPane()
                case .about:
                    AboutSettingsPane()
                }
            }
            .navigationTitle(pane.title)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}
