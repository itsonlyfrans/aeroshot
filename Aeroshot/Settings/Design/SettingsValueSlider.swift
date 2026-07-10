import SwiftUI

/// Titled slider row with a monospaced value pill. The slider itself stays
/// native — deliberate: the system thumb is part of the instrument feel —
/// while the presentation (title, pill, haptics) is ours and shared app-wide.
struct AeroSliderRow: View {
    let title: String
    let subtitle: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueLabel: (Double) -> String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        subtitle: String? = nil,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double = 1,
        valueLabel: @escaping (Double) -> String
    ) {
        self.title = title
        self.subtitle = subtitle
        self._value = value
        self.range = range
        self.step = step
        self.valueLabel = valueLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(valueLabel(value))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, SettingsTheme.spacingS + 2)
                    .padding(.vertical, SettingsTheme.spacingXS + 1)
                    .background(SettingsTheme.fillHover, in: Capsule())
            }

            Slider(value: $value, in: range, step: step)
                .tint(SettingsTheme.accent)
                .onChange(of: value) { _, _ in
                    SettingsTheme.performHaptic()
                }
        }
        .accessibilityElement(children: .combine)
    }
}

typealias SettingsValueSlider = AeroSliderRow
