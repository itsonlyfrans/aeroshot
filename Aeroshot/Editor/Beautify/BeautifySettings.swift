import AppKit

struct BeautifySettings: Equatable {
    var enabled: Bool = false
    var padding: CGFloat = 64
    var cornerRadius: CGFloat = 12
    var shadowRadius: CGFloat = 30
    var shadowOpacity: CGFloat = 0.45
    var gradient: GradientPreset = .indigo
    var aspectPreset: AspectPreset = .auto

    enum GradientPreset: String, CaseIterable, Identifiable {
        case indigo, sunset, ocean, forest, candy, mono

        var id: String { rawValue }
        var displayName: String { rawValue.capitalized }

        var colors: (NSColor, NSColor) {
            switch self {
            case .indigo: return (NSColor(red: 0.35, green: 0.30, blue: 0.90, alpha: 1),
                                  NSColor(red: 0.65, green: 0.35, blue: 0.95, alpha: 1))
            case .sunset: return (NSColor(red: 0.98, green: 0.45, blue: 0.35, alpha: 1),
                                  NSColor(red: 0.98, green: 0.75, blue: 0.35, alpha: 1))
            case .ocean: return (NSColor(red: 0.10, green: 0.55, blue: 0.85, alpha: 1),
                                 NSColor(red: 0.25, green: 0.85, blue: 0.80, alpha: 1))
            case .forest: return (NSColor(red: 0.10, green: 0.50, blue: 0.35, alpha: 1),
                                  NSColor(red: 0.55, green: 0.80, blue: 0.40, alpha: 1))
            case .candy: return (NSColor(red: 0.95, green: 0.45, blue: 0.75, alpha: 1),
                                 NSColor(red: 0.55, green: 0.55, blue: 0.98, alpha: 1))
            case .mono: return (NSColor(white: 0.20, alpha: 1), NSColor(white: 0.45, alpha: 1))
            }
        }
    }

    enum AspectPreset: String, CaseIterable, Identifiable {
        case auto, square, wide16x9, fourByThree

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .auto: return "Auto"
            case .square: return "1:1"
            case .wide16x9: return "16:9"
            case .fourByThree: return "4:3"
            }
        }
        var ratio: CGFloat? {
            switch self {
            case .auto: return nil
            case .square: return 1
            case .wide16x9: return 16.0 / 9.0
            case .fourByThree: return 4.0 / 3.0
            }
        }
    }
}
