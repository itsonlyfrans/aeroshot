import SwiftUI

struct SettingsPermissionTile: View {
    let title: String
    let description: String
    let granted: Bool
    let openSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringScale: CGFloat = 0.85
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: SettingsTheme.spacingM) {
            ZStack {
                Circle()
                    .strokeBorder(
                        granted ? SettingsTheme.success.opacity(0.3) : SettingsTheme.warning.opacity(0.3),
                        lineWidth: 3
                    )
                    .frame(width: SettingsTheme.iconBadgeSize, height: SettingsTheme.iconBadgeSize)
                    .scaleEffect(ringScale)

                Circle()
                    .fill(granted ? SettingsTheme.success : SettingsTheme.warning)
                    .frame(width: 10, height: 10)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: SettingsTheme.spacingS)

            VStack(alignment: .trailing, spacing: SettingsTheme.spacingS) {
                SettingsStatusBadge(
                    text: granted ? "Granted" : "Required",
                    tone: granted ? .success : .warning
                )

                if !granted {
                    AeroChipButton("Grant Access…", symbol: "arrow.up.forward.app") {
                        openSettings()
                    }
                }
            }
        }
        .padding(SettingsTheme.spacingM)
        .background(
            SettingsTheme.fillRest,
            in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                .strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5)
        }
        .onHover { hovering in
            SettingsTheme.animateHover(reducedMotion: reduceMotion) {
                isHovered = hovering
            }
        }
        .onAppear {
            guard !reduceMotion else {
                ringScale = 1
                return
            }
            withAnimation(SettingsTheme.spring) {
                ringScale = 1
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(granted ? "granted" : "not granted")")
    }
}
