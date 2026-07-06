import SwiftUI

struct SettingsValueSlider: View {
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
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(valueLabel(value))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, SettingsTheme.spacingS)
                    .padding(.vertical, SettingsTheme.spacingXS)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }

            Slider(value: $value, in: range, step: step)
                .tint(Color.accentColor)
                .onChange(of: value) { _, _ in
                    SettingsTheme.performHaptic()
                }
        }
        .accessibilityElement(children: .combine)
    }
}
