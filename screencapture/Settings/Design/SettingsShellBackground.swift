import SwiftUI

struct SettingsShellBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            RadialGradient(
                colors: [
                    Color.accentColor.opacity(colorScheme == .dark ? 0.08 : 0.05),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    private var gradientColors: [Color] {
        switch colorScheme {
        case .dark:
            return [
                Color(red: 0.11, green: 0.11, blue: 0.13),
                Color(red: 0.08, green: 0.08, blue: 0.10)
            ]
        default:
            return [
                Color(red: 0.97, green: 0.97, blue: 0.98),
                Color(red: 0.93, green: 0.94, blue: 0.96)
            ]
        }
    }
}
