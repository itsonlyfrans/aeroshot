import AppKit
import SwiftUI

struct SettingsPathField: View {
    let path: String
    let chooseAction: () -> Void
    var openAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
            HStack(spacing: SettingsTheme.spacingS) {
                Group {
                    if path.isEmpty {
                        Text("No folder selected")
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(path)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, SettingsTheme.spacingS)
                .padding(.vertical, SettingsTheme.spacingS)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                        .strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5)
                }

                SettingsChipButton("Choose…", symbol: "folder.badge.plus") {
                    chooseAction()
                }

                if let openAction {
                    SettingsChipButton("", symbol: "arrow.up.forward.square") {
                        openAction()
                    }
                    .help("Open in Finder")
                    .accessibilityLabel("Open in Finder")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Save location")
        .accessibilityValue(path)
    }
}
