import SwiftUI

struct SettingsInlineCallout: View {
    let symbol: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: SettingsTheme.spacingS) {
            Image(systemName: symbol)
                .foregroundStyle(.orange)
                .font(.system(size: 13, weight: .semibold))

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: SettingsTheme.spacingS)

            Button(buttonTitle) {
                action()
            }
            .controlSize(.small)
        }
        .padding(SettingsTheme.spacingM)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.2), lineWidth: 0.5)
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
            Button(title) {
                action()
            }
            .foregroundStyle(isDestructive ? Color.red : Color.primary)
            .controlSize(.regular)
        }
        .padding(.top, SettingsTheme.spacingS)
    }
}
