import SwiftUI

/// Custom dropdown that replaces the stock macOS popup button: current value
/// plus a chevron in a quiet field, native Menu underneath.
/// Shared app-wide — Settings, editor, and studios all use this treatment.
struct AeroMenuPicker<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    @ViewBuilder
    var body: some View {
        if options.count > 1 {
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
                AeroMenuLabel(title: label(selection))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityValue(label(selection))
        } else {
            AeroMenuLabel(title: label(selection), showsChevron: false)
                .accessibilityValue(label(selection))
        }
    }
}

struct AeroMenuLabel: View {
    let title: String
    var showsChevron = true

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: SettingsTheme.spacingS) {
            Text(title)
                .font(SettingsTheme.typeSmall(weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(SettingsTheme.typeMicro(weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 9)
        .frame(minWidth: 92, minHeight: 32, alignment: .leading)
        .background(isHovered ? SettingsTheme.fillHover : SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                .strokeBorder(isHovered ? SettingsTheme.borderHover : SettingsTheme.borderSubtle, lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
        .onHover { hovering in
            SettingsTheme.animateHover(reducedMotion: reduceMotion) {
                isHovered = hovering
            }
        }
    }
}

typealias SettingsMenuPicker<T: Hashable> = AeroMenuPicker<T>
