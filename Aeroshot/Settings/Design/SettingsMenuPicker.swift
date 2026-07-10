import SwiftUI

/// Custom dropdown that replaces the stock macOS popup button: current value
/// plus a chevron in a quiet field, native Menu underneath.
/// Shared app-wide — Settings, editor, and studios all use this treatment.
struct AeroMenuPicker<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                    SettingsTheme.performHaptic()
                } label: {
                    if option == selection {
                        Label(label(option), systemImage: "checkmark")
                    } else {
                        Text(label(option))
                    }
                }
            }
        } label: {
            HStack(spacing: SettingsTheme.spacingS) {
                Text(label(selection))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(SettingsTheme.typeMicro(weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, SettingsTheme.spacingM)
            .padding(.vertical, SettingsTheme.spacingS - 1)
            .background {
                RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                    .fill(isHovered ? SettingsTheme.fillPressed : SettingsTheme.fillHover)
            }
            .overlay {
                RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                    .strokeBorder(isHovered ? SettingsTheme.borderHover : SettingsTheme.borderSubtle, lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering in
            SettingsTheme.animateHover(reducedMotion: reduceMotion) {
                isHovered = hovering
            }
        }
        .accessibilityValue(label(selection))
    }
}

typealias SettingsMenuPicker<T: Hashable> = AeroMenuPicker<T>

/// Compact themed action button — replaces stock small bordered buttons.
/// Shared app-wide — Settings, editor, and studios all use this treatment.
struct AeroChipButton: View {
    let title: String
    var symbol: String?
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button {
            SettingsTheme.performHaptic()
            action()
        } label: {
            HStack(spacing: SettingsTheme.spacingXS + 2) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(SettingsTheme.typeMicro(weight: .semibold))
                }
                if !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, SettingsTheme.spacingM)
            .padding(.vertical, SettingsTheme.spacingS - 1)
            .background {
                RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                    .fill(isHovered ? SettingsTheme.fillPressed : SettingsTheme.fillHover)
            }
            .overlay {
                RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                    .strokeBorder(isHovered ? SettingsTheme.borderHover : SettingsTheme.borderSubtle, lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
        }
        .buttonStyle(AeroPressableStyle())
        .onHover { hovering in
            SettingsTheme.animateHover(reducedMotion: reduceMotion) {
                isHovered = hovering
            }
        }
    }
}

typealias SettingsChipButton = AeroChipButton
