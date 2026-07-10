import SwiftUI

/// Shared segmented control — Settings, editor, and studios all use this treatment.
struct AeroSegmentedControl<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    let symbol: ((T) -> String)?

    @Namespace private var segmentNamespace
    @State private var hoveredOption: T?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        options: [T],
        selection: Binding<T>,
        label: @escaping (T) -> String,
        symbol: ((T) -> String)? = nil
    ) {
        self.options = options
        self._selection = selection
        self.label = label
        self.symbol = symbol
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection == option
                Button {
                    withAnimation(SettingsTheme.spring(reducedMotion: reduceMotion)) {
                        selection = option
                    }
                    SettingsTheme.performHaptic()
                } label: {
                    HStack(spacing: 4) {
                        if let symbol {
                            let name = symbol(option)
                            if !name.isEmpty {
                                Image(systemName: name)
                                    .font(.caption2.weight(.medium))
                            }
                        }
                        Text(label(option))
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, SettingsTheme.spacingM)
                    .padding(.vertical, SettingsTheme.spacingS)
                    .frame(maxWidth: .infinity)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                                .fill(SettingsTheme.accent.opacity(0.15))
                                .overlay {
                                    RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                                        .strokeBorder(SettingsTheme.borderAccentSelected, lineWidth: 1)
                                }
                                .matchedGeometryEffect(id: "activeSegment", in: segmentNamespace)
                        } else if hoveredOption == option {
                            RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                                .fill(SettingsTheme.fillHover)
                        }
                    }
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    SettingsTheme.animateHover(reducedMotion: reduceMotion) {
                        hoveredOption = hovering ? option : (hoveredOption == option ? nil : hoveredOption)
                    }
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                .strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5)
        }
    }
}

typealias SettingsSegmentedControl<T: Hashable> = AeroSegmentedControl<T>
