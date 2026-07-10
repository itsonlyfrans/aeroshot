import AppKit
import SwiftUI

/// Shared visual tokens used outside the Settings surface.
enum AeroTheme {
    // Symbol policy: use the default monochrome rendering app-wide. Filled
    // symbols indicate an action/emphasis; outlines indicate status/decoration.
    /// The catalog-backed app accent. `AccentColor.colorset` defines the brand
    /// azure — deeper in light mode, brighter in dark, AA against each backdrop.
    static let accent = AeroTokens.ColorRole.accent

    /// An adaptive separator that remains visible against light and dark materials.
    static let strokeHairline = AeroTokens.ColorRole.border

    static let controlRadiusS = AeroTokens.Radius.small
    static let cardRadius = AeroTokens.Radius.card
    static let controlHeight = AeroTokens.Control.regularHeight

    static let overlayLabelBackground = NSColor(
        red: 0.08,
        green: 0.08,
        blue: 0.10,
        alpha: 0.85
    )

    static let pressScale = AeroTokens.Control.pressScale
    static let pressOpacity = AeroTokens.Control.pressOpacity
}
