import SwiftUI

struct SettingsInlineCallout: View {
    enum Tone {
        case warning, info, success

        var color: Color {
            switch self {
            case .warning: return SettingsTheme.warning
            case .info: return SettingsTheme.accent
            case .success: return SettingsTheme.success
            }
        }
    }

    let symbol: String
    let message: String
    var tone: Tone = .warning
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: SettingsTheme.spacingS) {
            Image(systemName: symbol)
                .foregroundStyle(tone.color)
                .font(.subheadline.weight(.semibold))
                .frame(width: SettingsTheme.iconColumnWidth)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let buttonTitle, let action {
                Spacer(minLength: SettingsTheme.spacingS)

                AeroChipButton(buttonTitle) {
                    action()
                }
            }
        }
        .padding(SettingsTheme.spacingM)
        .background(tone.color.opacity(0.08), in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                .strokeBorder(tone.color.opacity(0.2), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SettingsFooterActions: View {
    let title: String
    let isDestructive: Bool
    let action: () -> Void

    init(_ title: String, destructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isDestructive = destructive
        self.action = action
    }

    var body: some View {
        HStack {
            Spacer()
            if isDestructive {
                Button(title) {
                    SettingsTheme.performHaptic()
                    action()
                }
                .buttonStyle(AeroButtonStyle(kind: .destructive, size: .compact))
            } else {
                AeroChipButton(title) {
                    action()
                }
            }
        }
        .padding(.top, SettingsTheme.spacingS)
    }
}
