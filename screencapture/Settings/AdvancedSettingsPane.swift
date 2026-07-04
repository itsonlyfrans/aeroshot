import SwiftUI

struct AdvancedSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SettingsSectionCard("OCR Settings") {
                    Toggle("Add OCR captures to history", isOn: $settings.addOCRCapturesToHistory)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text("When enabled, plain text captures recognized via OCR are saved as searchable .txt files in your capture history.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 18)
                }
                
                SettingsSectionCard("App Identity") {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("Dock Icon")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("Hidden (menu bar accessory)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("ScreenCapture runs exclusively as a background agent accessed via the menu bar icon and global hotkeys, so it does not clutter your Dock.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
            .padding(18)
        }
    }
}
