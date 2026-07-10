import SwiftUI

struct SettingsHotkeyRow: View {
    let action: HotkeyAction
    @Binding var hotkey: Hotkey
    let errorMessage: String?
    let onChange: (Hotkey) -> Void
    let onValidationError: (String?) -> Void
    let onReset: () -> Void

    @State private var isRowHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.spacingXS) {
            HStack(alignment: .center, spacing: SettingsTheme.spacingM) {
                Image(systemName: action.symbol)
                    .font(.system(size: SettingsTheme.iconSizeMedium, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: SettingsTheme.iconColumnWidth)

                Text(action.displayName)
                    .font(.body.weight(.medium))

                Spacer(minLength: SettingsTheme.spacingM)

                Button {
                    SettingsTheme.performHaptic()
                    onReset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: SettingsTheme.iconSizeSmall, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(isRowHovered ? SettingsTheme.fillPressed : SettingsTheme.fillHover, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Reset to default")
                // Hidden until the row is hovered; stays in the tree so
                // accessibility can always reach it.
                .opacity(isRowHovered ? 1 : 0)
                .accessibilityHidden(false)

                HotkeyRecorderView(
                    action: action,
                    hotkey: $hotkey,
                    validationMessage: { _ in nil },
                    onChange: onChange,
                    onValidationError: onValidationError
                )
                .frame(width: 128, height: AeroTokens.Control.regularHeight)
                .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                        .strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5)
                }
            }
            .padding(.horizontal, SettingsTheme.spacingXS)
            .padding(.vertical, SettingsTheme.spacingXS)
            .background {
                if isRowHovered {
                    RoundedRectangle(cornerRadius: AeroTokens.Radius.small, style: .continuous)
                        .fill(SettingsTheme.fillHover)
                }
            }
            .contentShape(Rectangle())

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(AeroTokens.ColorRole.danger)
                    .padding(.leading, SettingsTheme.iconColumnWidth + SettingsTheme.spacingM)
            }
        }
        .padding(.vertical, SettingsTheme.spacingXS)
        .onHover { hovering in
            SettingsTheme.animateHover(reducedMotion: reduceMotion) {
                isRowHovered = hovering
            }
        }
        .accessibilityElement(children: .combine)
    }
}
