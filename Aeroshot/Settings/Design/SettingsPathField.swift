import AppKit
import SwiftUI

struct SettingsPathField: View {
    let path: String
    let chooseAction: () -> Void
    var openAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
            HStack(spacing: SettingsTheme.spacingS) {
                Text(path)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, SettingsTheme.spacingS)
                    .padding(.vertical, SettingsTheme.spacingS)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                    }

                Button("Choose…") {
                    chooseAction()
                }
                .controlSize(.small)

                if let openAction {
                    Button {
                        openAction()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Open in Finder")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Save location")
        .accessibilityValue(path)
    }
}
