import AppKit
import SwiftUI

/// The semantic vocabulary shared by every Aeroshot surface.
///
/// Values describe intent rather than a particular screen. Legacy themes below
/// are facades over these tokens so existing call sites can migrate gradually.
enum AeroTokens {
    enum ColorRole {
        static let accent = Color.accentColor
        static let foreground = Color.primary
        static let foregroundSecondary = Color.secondary
        static let foregroundTertiary = Color(nsColor: .tertiaryLabelColor)
        static let surface = Color(nsColor: .windowBackgroundColor)
        static let surfaceRaised = Color(nsColor: .controlBackgroundColor)
        static let surfaceSelected = Color(nsColor: .selectedContentBackgroundColor)
        static let border = Color(nsColor: .separatorColor)
        static let focus = Color.accentColor
        static let success = Color(nsColor: .systemGreen)
        static let warning = Color(nsColor: .systemOrange)
        static let danger = Color(nsColor: .systemRed)
        static let information = Color(nsColor: .systemBlue)
    }

    enum Typography {
        static let microSize: CGFloat = 9
        static let smallSize: CGFloat = 12
        static let bodySize: CGFloat = 13
        static let titleSize: CGFloat = 17

        static func micro(weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
            .system(size: microSize, weight: weight, design: design)
        }

        static func small(weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
            .system(size: smallSize, weight: weight, design: design)
        }

        static func body(weight: Font.Weight = .regular) -> Font {
            .system(size: bodySize, weight: weight)
        }

        static func title(weight: Font.Weight = .semibold) -> Font {
            .system(size: titleSize, weight: weight)
        }
    }

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let extraLarge: CGFloat = 24
        static let jumbo: CGFloat = 32
    }

    enum Radius {
        static let small: CGFloat = 7
        static let control: CGFloat = 10
        static let card: CGFloat = 14
        static let panel: CGFloat = 18
    }

    struct Elevation: Equatable, Sendable {
        let opacity: Double
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat

        static let none = Elevation(opacity: 0, radius: 0, x: 0, y: 0)
        static let card = Elevation(opacity: 0.04, radius: 8, x: 0, y: 4)
        static let floating = Elevation(opacity: 0.12, radius: 18, x: 0, y: 8)
    }

    enum MaterialIntent: Equatable, Sendable {
        case panel
        case floating
        case overlay

        var opaqueFallbackOpacity: Double {
            switch self {
            case .panel: 1
            case .floating: 0.98
            case .overlay: 0.96
            }
        }
    }

    enum Focus {
        static let ringWidth: CGFloat = 2
        static let ringInset: CGFloat = 2
        static let highContrastRingWidth: CGFloat = 3
    }

    enum Motion {
        static let hoverDuration: Double = 0.12
        static let standardDuration: Double = 0.20
        static let springResponse: Double = 0.28
        static let springDamping: Double = 0.78

        static let hover: Animation = .easeOut(duration: hoverDuration)
        static let standard: Animation = .easeInOut(duration: standardDuration)
        static var spring: Animation {
            .spring(response: springResponse, dampingFraction: springDamping)
        }

        static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : animation
        }
    }

    enum Control {
        static let compactHeight: CGFloat = 24
        static let regularHeight: CGFloat = 28
        static let largeHeight: CGFloat = 36
        static let minimumHitSize: CGFloat = 28
        static let iconColumnWidth: CGFloat = 22
        static let iconBadgeSize: CGFloat = 36
        static let iconSmall: CGFloat = 11
        static let iconMedium: CGFloat = 13
        static let iconLarge: CGFloat = 16
        static let pressScale: CGFloat = 0.96
        static let pressOpacity: Double = 0.70
    }
}

enum AeroSemanticState: CaseIterable, Equatable, Sendable {
    case neutral
    case accent
    case success
    case warning
    case danger
    case information

    var label: String {
        switch self {
        case .neutral: "Status"
        case .accent: "Active"
        case .success: "Complete"
        case .warning: "Needs attention"
        case .danger: "Error"
        case .information: "Information"
        }
    }

    var symbol: String {
        switch self {
        case .neutral: "circle"
        case .accent: "circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        case .information: "info.circle.fill"
        }
    }

    @MainActor var color: Color {
        switch self {
        case .neutral: AeroTokens.ColorRole.foregroundSecondary
        case .accent: AeroTokens.ColorRole.accent
        case .success: AeroTokens.ColorRole.success
        case .warning: AeroTokens.ColorRole.warning
        case .danger: AeroTokens.ColorRole.danger
        case .information: AeroTokens.ColorRole.information
        }
    }
}

/// A value form of the SwiftUI accessibility environment. Keeping resolution
/// deterministic makes fallback behavior testable without launching a window.
struct AeroAccessibilityPreferences: Equatable, Sendable {
    var reduceMotion: Bool = false
    var increasedContrast: Bool = false
    var reduceTransparency: Bool = false
    var differentiateWithoutColor: Bool = false

    var allowsMotion: Bool { !reduceMotion }
    var allowsTransparency: Bool { !reduceTransparency }
    var requiresStateSymbol: Bool { differentiateWithoutColor || increasedContrast }

    func animation(_ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }

    func borderWidth(normal: CGFloat = 1) -> CGFloat {
        increasedContrast ? max(normal * 2, 2) : normal
    }
}
