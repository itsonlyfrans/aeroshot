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
                Button("Download model (\(PrivacyFilterModel.downloadSizeLabel))") {
                    model.download()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .downloading(let progress):
                HStack(spacing: SettingsTheme.spacingS) {
                    ProgressView(value: progress)
                        .frame(maxWidth: 220)
                    Text("Downloading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .ready:
                Button("Remove model") {
                    isOn = false
                    model.remove()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            case .failed(let message):
                HStack(spacing: SettingsTheme.spacingS) {
                    Text("Download failed: \(message)")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Retry") { model.download() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }

    private var subtitle: String {
        switch model.state {
        case .ready:
            return "Supplements pattern matching with an on-device model — only lines patterns would already flag get redacted"
        case .downloading:
            return "Preparing the on-device model…"
        case .notDownloaded, .failed:
            return "Requires a one-time \(PrivacyFilterModel.downloadSizeLabel) model download. Runs fully on device."
        }
    }
}
