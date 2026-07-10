import SwiftUI

struct SettingsSegmentedControl<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    let symbol: ((T) -> String)?

    @Namespace private var segmentNamespace
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
                                .fill(Color.primary.opacity(0.12))
                                .matchedGeometryEffect(id: "activeSegment", in: segmentNamespace)
                                                        }
                    }
                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.85))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius + 2, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsTheme.controlRadius + 2, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
    }
}
