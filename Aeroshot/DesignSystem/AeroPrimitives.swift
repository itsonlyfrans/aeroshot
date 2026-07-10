import SwiftUI

enum AeroButtonKind: Equatable, Sendable {
    case primary
    case secondary
    case quiet
    case destructive
}

enum AeroControlSize: Equatable, Sendable {
    case compact
    case regular
    case large

    var height: CGFloat {
        switch self {
        case .compact: AeroTokens.Control.compactHeight
        case .regular: AeroTokens.Control.regularHeight
        case .large: AeroTokens.Control.largeHeight
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact: AeroTokens.Spacing.small
        case .regular: AeroTokens.Spacing.medium
        case .large: AeroTokens.Spacing.large
        }
    }
}

/// Shared button treatment. Native `Button` semantics are retained, including
/// keyboard activation, disabled state, and the system focus ring.
struct AeroButtonStyle: ButtonStyle {
    var kind: AeroButtonKind = .secondary
    var size: AeroControlSize = .regular

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let preferences = AeroAccessibilityPreferences(
            reduceMotion: reduceMotion,
            increasedContrast: contrast == .increased,
            differentiateWithoutColor: differentiateWithoutColor
        )

        configuration.label
            .font(AeroTokens.Typography.body(weight: .medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, size.horizontalPadding)
            .frame(minHeight: max(size.height, AeroTokens.Control.minimumHitSize))
            .background(backgroundColor(configuration: configuration))
            .clipShape(RoundedRectangle(cornerRadius: AeroTokens.Radius.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AeroTokens.Radius.small, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: preferences.borderWidth(normal: 0.5))
            }
            .opacity(isEnabled ? (configuration.isPressed ? AeroTokens.Control.pressOpacity : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? AeroTokens.Control.pressScale : 1)
            .animation(preferences.animation(AeroTokens.Motion.hover), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: AeroTokens.Radius.small, style: .continuous))
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary, .destructive: .white
        case .secondary, .quiet: AeroTokens.ColorRole.foreground
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary: AeroTokens.ColorRole.accent
        case .destructive: AeroTokens.ColorRole.danger
        case .secondary: AeroTokens.ColorRole.border
        case .quiet: .clear
        }
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        let pressed = configuration.isPressed
        switch kind {
        case .primary:
            return AeroTokens.ColorRole.accent.opacity(pressed ? 0.78 : 1)
        case .destructive:
            return AeroTokens.ColorRole.danger.opacity(pressed ? 0.78 : 1)
        case .secondary:
            return AeroTokens.ColorRole.surfaceRaised.opacity(pressed ? 0.72 : 1)
        case .quiet:
            return AeroTokens.ColorRole.foreground.opacity(pressed ? 0.10 : 0)
        }
    }
}

/// Press feedback for custom-chrome buttons that draw their own hover and
/// selection fills. Replaces `.buttonStyle(.plain)` so every interactive
/// surface shares the same pressed scale/opacity, gated on Reduce Motion.
struct AeroPressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? AeroTokens.Control.pressOpacity : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? AeroTokens.Control.pressScale : 1)
            .animation(
                AeroTokens.Motion.resolved(AeroTokens.Motion.hover, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

private struct AeroFocusRingModifier<S: InsettableShape>: ViewModifier {
    let isFocused: Bool
    let shape: S
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.overlay {
            if isFocused {
                shape.strokeBorder(
                    AeroTokens.ColorRole.focus,
                    lineWidth: contrast == .increased
                        ? AeroTokens.Focus.highContrastRingWidth
                        : AeroTokens.Focus.ringWidth
                )
                .padding(-AeroTokens.Focus.ringInset)
                .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    /// Adds a deterministic focus affordance to custom controls. Interactive
    /// views should still use native `Button`, `Toggle`, or `.focusable()` APIs.
    func aeroFocusRing<S: InsettableShape>(isFocused: Bool, in shape: S) -> some View {
        modifier(AeroFocusRingModifier(isFocused: isFocused, shape: shape))
    }
}

struct AeroInspectorRow<Content: View>: View {
    let title: String
    let detail: String?
    private let content: Content

    init(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AeroTokens.Spacing.medium) {
            VStack(alignment: .leading, spacing: AeroTokens.Spacing.xxs) {
                Text(title).font(AeroTokens.Typography.body(weight: .medium))
                if let detail {
                    Text(detail)
                        .font(AeroTokens.Typography.small())
                        .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            content
        }
        .padding(.vertical, AeroTokens.Spacing.xs)
        .accessibilityElement(children: .contain)
    }
}

struct AeroPanel<Content: View>: View {
    let title: String?
    let symbol: String?
    let materialIntent: AeroTokens.MaterialIntent
    private let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    init(
        _ title: String? = nil,
        symbol: String? = nil,
        materialIntent: AeroTokens.MaterialIntent = .panel,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.materialIntent = materialIntent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AeroTokens.Spacing.small) {
            if let title {
                Label(title, systemImage: symbol ?? "square.stack.3d.up")
                    .font(AeroTokens.Typography.body(weight: .semibold))
                    .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
            }

            content
        }
        .padding(AeroTokens.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: AeroTokens.Radius.card, style: .continuous)
                    .fill(AeroTokens.ColorRole.surface.opacity(materialIntent.opaqueFallbackOpacity))
            } else {
                RoundedRectangle(cornerRadius: AeroTokens.Radius.card, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: AeroTokens.Radius.card, style: .continuous)
                .strokeBorder(AeroTokens.ColorRole.border, lineWidth: contrast == .increased ? 2 : 0.5)
        }
        .shadow(
            color: .black.opacity(elevation.opacity),
            radius: elevation.radius,
            x: elevation.x,
            y: elevation.y
        )
        .accessibilityElement(children: .contain)
    }

    /// Elevation follows the material's intent: in-flow panels sit at card
    /// depth, floating/overlay surfaces lift to the shared floating recipe.
    private var elevation: AeroTokens.Elevation {
        switch materialIntent {
        case .panel: AeroTokens.Elevation.card
        case .floating, .overlay: AeroTokens.Elevation.floating
        }
    }
}

struct AeroEmptyState: View {
    let title: String
    let message: String
    let symbol: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: AeroTokens.Spacing.medium) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
                .accessibilityHidden(true)
            VStack(spacing: AeroTokens.Spacing.xs) {
                Text(title).font(AeroTokens.Typography.title())
                Text(message)
                    .font(AeroTokens.Typography.body())
                    .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(AeroButtonStyle(kind: .primary))
            }
        }
        .frame(maxWidth: 360)
        .padding(AeroTokens.Spacing.jumbo)
        .accessibilityElement(children: .contain)
    }
}

struct AeroProgress: View {
    let label: String
    let value: Double?
    var status: String?
    var state: AeroSemanticState = .accent

    var normalizedValue: Double? { value.map { min(max($0, 0), 1) } }

    var body: some View {
        VStack(alignment: .leading, spacing: AeroTokens.Spacing.small) {
            HStack {
                Label(label, systemImage: state.symbol)
                    .font(AeroTokens.Typography.body(weight: .medium))
                    .foregroundStyle(state.color)
                Spacer(minLength: AeroTokens.Spacing.small)
                if let status {
                    Text(status)
                        .font(AeroTokens.Typography.small())
                        .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
                }
            }
            if let normalizedValue {
                ProgressView(value: normalizedValue)
                    .tint(state.color)
                    .accessibilityValue(Text("\(Int((normalizedValue * 100).rounded())) percent"))
            } else {
                ProgressView().tint(state.color)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
