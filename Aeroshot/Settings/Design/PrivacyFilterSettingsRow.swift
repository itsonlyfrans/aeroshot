import SwiftUI

/// Toggle for the OpenAI privacy-filter scan tier, with inline download management
/// for the on-device model. The toggle only enables once the model is downloaded.
struct PrivacyFilterSettingsRow: View {
    @Binding var isOn: Bool
    @ObservedObject private var model = PrivacyFilterModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.spacingXS) {
            SettingsToggle(
                title: "Enhanced scan (privacy filter)",
                subtitle: subtitle,
                isOn: $isOn,
                symbol: "shield.lefthalf.filled.badge.checkmark"
            )
            .disabled(model.state != .ready)

            switch model.state {
            case .notDownloaded:
                AeroChipButton("Download model (\(PrivacyFilterModel.downloadSizeLabel))") {
                    model.download()
                }
            case .downloading(let progress):
                AeroProgress(label: "Downloading…", value: progress)
                    .frame(maxWidth: 220)
            case .ready:
                Button {
                    isOn = false
                    model.remove()
                } label: {
                    Label("Remove downloaded model", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.leading, 34)
                .help("Deletes the on-device model and disables enhanced scan")
            case .failed(let message):
                HStack(spacing: SettingsTheme.spacingS) {
                    Text("Download failed: \(message)")
                        .font(.caption)
                        .foregroundStyle(AeroTokens.ColorRole.danger)
                    AeroChipButton("Retry") { model.download() }
                }
            }
        }
    }

    private var subtitle: String {
        switch model.state {
        case .ready:
            return "An on-device model double-checks lines that pattern matching flags, catching context it would miss"
        case .downloading:
            return "Preparing the on-device model…"
        case .notDownloaded, .failed:
            return "Requires a one-time \(PrivacyFilterModel.downloadSizeLabel) model download. Runs fully on device."
        }
    }
}
