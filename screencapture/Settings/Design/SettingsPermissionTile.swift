import SwiftUI

struct SettingsPermissionTile: View {
    let title: String
    let description: String
    let granted: Bool
    let openSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringScale: CGFloat = 0.85

    var body: some View {
        HStack(alignment: .top, spacing: SettingsTheme.spacingM) {
            ZStack {
                Circle()
                    .strokeBorder(
                        granted ? Color.green.opacity(0.3) : Color.orange.opacity(0.3),
                        lineWidth: 3
                    )
                    .frame(width: 36, height: 36)
                    .scaleEffect(ringScale)

                Circle()
                    .fill(granted ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: SettingsTheme.spacingXS) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: SettingsTheme.spacingS)

            VStack(alignment: .trailing, spacing: SettingsTheme.spacingS) {
                Text(granted ? "Granted" : "Required")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(granted ? Color.green : Color.orange)
                    .padding(.horizontal, SettingsTheme.spacingS)
                    .padding(.vertical, SettingsTheme.spacingXS)
                    .background(
                        (granted ? Color.green : Color.orange).opacity(0.12),
                        in: Capsule()
                    )

                if !granted {
                    Button("Grant Access…") {
                        openSettings()
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(SettingsTheme.spacingM)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
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
