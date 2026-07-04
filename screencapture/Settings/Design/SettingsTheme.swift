import SwiftUI

enum SettingsTheme {
    static let controlRadius: CGFloat = 10
    static let cardRadius: CGFloat = 14
    static let panelRadius: CGFloat = 18

    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 12
    static let spacingL: CGFloat = 16
    static let spacingXL: CGFloat = 24

    static var spring: Animation {
        .spring(response: 0.28, dampingFraction: 0.78)
    }

    static func spring(reducedMotion: Bool) -> Animation? {
        reducedMotion ? nil : spring
    }

    static func performHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
