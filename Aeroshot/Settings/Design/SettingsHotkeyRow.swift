import SwiftUI

struct SettingsHotkeyRow: View {
    let action: HotkeyAction
    @Binding var hotkey: Hotkey
    let errorMessage: String?
    let onChange: (Hotkey) -> Void
    let onValidationError: (String?) -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.spacingXS) {
            HStack(alignment: .center, spacing: SettingsTheme.spacingM) {
                Image(systemName: action.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)

                Text(action.displayName)
                    .font(.headline)

                Spacer(minLength: SettingsTheme.spacingM)

                Button {
                    onReset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Color.primary.opacity(0.04), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Reset to default")

                HotkeyRecorderView(
                    action: action,
                    hotkey: $hotkey,
                    validationMessage: { _ in nil },
                    onChange: onChange,
                    onValidationError: onValidationError
                )
                .frame(width: 128, height: 26)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, 30)
            }
        }
        .padding(.vertical, SettingsTheme.spacingXS)
        .accessibilityElement(children: .combine)
    }
}
