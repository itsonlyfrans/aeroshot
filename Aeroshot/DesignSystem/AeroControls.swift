import SwiftUI

/// The bare switch capsule shared by `AeroToggleRow` and compact contexts
/// (editor Beautify bar). Purely visual — the enclosing control owns the
/// gesture, haptic, and accessibility surface.
struct AeroSwitchKnob: View {
    let isOn: Bool

    @ScaledMetric(relativeTo: .body) private var trackWidth: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var trackHeight: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var thumbSize: CGFloat = 18

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? AeroTokens.ColorRole.accent : AeroTokens.Fill.selected)
                .frame(width: trackWidth, height: trackHeight)

            Circle()
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                .frame(width: thumbSize, height: thumbSize)
                .padding(AeroTokens.Spacing.xxs)
        }
    }
}

/// Compact labeled switch for dense chrome (floating bars, toolbars) where the
/// full `AeroToggleRow` would be too heavy. Same knob, same behavior.
struct AeroCompactToggle: View {
    let title: String
    @Binding var isOn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(AeroTokens.Motion.resolved(AeroTokens.Motion.spring, reduceMotion: reduceMotion)) {
                isOn.toggle()
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        } label: {
            HStack(spacing: AeroTokens.Spacing.small) {
                if !title.isEmpty {
                    Text(title)
                        .font(AeroTokens.Typography.small(weight: .medium))
                        .foregroundStyle(.primary)
                }
                AeroSwitchKnob(isOn: isOn)
                    .scaleEffect(0.85, anchor: .trailing)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// Inline slider for dense chrome: micro label, native track, monospaced
/// value readout. The floating-bar sibling of `AeroSliderRow`.
struct AeroInlineSlider<V: BinaryFloatingPoint>: View where V.Stride: BinaryFloatingPoint {
    let label: String
    @Binding var value: V
    let range: ClosedRange<V>
    var step: V.Stride?
    var width: CGFloat = 80
    var valueText: ((V) -> String)?
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        HStack(spacing: AeroTokens.Spacing.xs + 2) {
            Text(label)
                .font(AeroTokens.Typography.small(weight: .medium))
                .foregroundStyle(.secondary)
            Group {
                if let step {
                    Slider(value: $value, in: range, step: step, onEditingChanged: onEditingChanged)
                } else {
                    Slider(value: $value, in: range, onEditingChanged: onEditingChanged)
                }
            }
            .frame(width: width)
            .controlSize(.small)
            .tint(AeroTokens.ColorRole.accent)
            .accessibilityLabel(label)
            Text(valueText.map { $0(value) } ?? "\(Int(value))")
                .font(AeroTokens.Typography.micro(design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 20, alignment: .trailing)
        }
    }
}

/// The quiet-field chrome shared by text fields app-wide (search field,
/// output filename fields, inspector text inputs). Replaces `.roundedBorder`.
struct AeroFieldChrome: ViewModifier {
    var isFocused = false

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, AeroTokens.Spacing.medium)
            .padding(.vertical, AeroTokens.Spacing.small - 1)
            .background {
                RoundedRectangle(cornerRadius: AeroTokens.Radius.control, style: .continuous)
                    .fill(AeroTokens.Fill.rest)
            }
            .overlay {
                RoundedRectangle(cornerRadius: AeroTokens.Radius.control, style: .continuous)
                    .strokeBorder(
                        isFocused ? AeroTokens.Stroke.accentSelected : AeroTokens.Stroke.subtle,
                        lineWidth: isFocused ? AeroTokens.Stroke.accentSelectedWidth : AeroTokens.Stroke.hairlineWidth
                    )
            }
    }
}

extension View {
    func aeroFieldChrome(isFocused: Bool = false) -> some View {
        modifier(AeroFieldChrome(isFocused: isFocused))
    }
}
