import SwiftUI

enum SettingsTheme {
    static let controlRadius = AeroTokens.Radius.control
    static let cardRadius = AeroTheme.cardRadius
    static let panelRadius = AeroTokens.Radius.panel

    static let spacingXS = AeroTokens.Spacing.xs
    static let spacingS = AeroTokens.Spacing.small
    static let spacingM = AeroTokens.Spacing.medium
    static let spacingL = AeroTokens.Spacing.large
    static let spacingXL = AeroTokens.Spacing.extraLarge

    /// Primary accent — use instead of `Color.accentColor` for consistent branding.
    /// One accent, one job: interactive and selected states. Never decorative washes.
    static let accent = AeroTheme.accent
    static let success = AeroTokens.ColorRole.success
    static let warning = AeroTokens.ColorRole.warning

    static let iconColumnWidth = AeroTokens.Control.iconColumnWidth
    static let iconBadgeSize = AeroTokens.Control.iconBadgeSize
    static let iconSizeSmall = AeroTokens.Control.iconSmall
    static let iconSizeMedium = AeroTokens.Control.iconMedium
    static let iconSizeLarge = AeroTokens.Control.iconLarge

    static func typeMicro(weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        AeroTokens.Typography.micro(weight: weight, design: design)
    }

    static func typeSmall(weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        AeroTokens.Typography.small(weight: weight, design: design)
    }

    static let selectionCardMinHeight: CGFloat = 108
    static let statCardMinHeight: CGFloat = 92

    static let borderSubtle = AeroTokens.Stroke.subtle
    static let borderHover = AeroTokens.Stroke.hover
    static let borderAccentSelected = AeroTokens.Stroke.accentSelected
    static let fillRest = AeroTokens.Fill.rest
    static let fillHover = AeroTokens.Fill.hover
    static let fillPressed = AeroTokens.Fill.pressed
    static let fillSelected = AeroTokens.Fill.selected

    static func typeBody(weight: Font.Weight = .regular) -> Font {
        AeroTokens.Typography.body(weight: weight)
    }

    static func typeTitle(weight: Font.Weight = .semibold, design: Font.Design = .default) -> Font {
        AeroTokens.Typography.title(weight: weight, design: design)
    }

    static var spring: Animation {
        AeroTokens.Motion.spring
    }

    static let hoverAnimation = AeroTokens.Motion.hover

    static func spring(reducedMotion: Bool) -> Animation? {
        reducedMotion ? nil : spring
    }

    static func animateHover(reducedMotion: Bool, _ body: () -> Void) {
        withAnimation(reducedMotion ? nil : hoverAnimation, body)
    }

    static func performHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
