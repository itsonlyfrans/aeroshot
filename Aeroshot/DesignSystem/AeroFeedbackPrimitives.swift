import SwiftUI

struct AeroToast: View {
    let message: String
    var state: AeroSemanticState = .success
    var actionTitle: String?
    var action: (() -> Void)?
    var dismiss: (() -> Void)?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var accessibilitySummary: String { "\(state.label): \(message)" }

    var body: some View {
        HStack(spacing: AeroTokens.Spacing.small) {
            Image(systemName: state.symbol)
                .foregroundStyle(state.color)
                .accessibilityHidden(true)
            Text(message)
                .font(AeroTokens.Typography.body(weight: .medium))
                .lineLimit(2)
            Spacer(minLength: AeroTokens.Spacing.small)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(AeroButtonStyle(kind: .quiet, size: .compact))
            }
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .accessibilityLabel("Dismiss notification")
                }
                .buttonStyle(AeroButtonStyle(kind: .quiet, size: .compact))
            }
        }
        .padding(.horizontal, AeroTokens.Spacing.medium)
        .frame(minHeight: 44)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: AeroTokens.Radius.control, style: .continuous)
                    .fill(AeroTokens.ColorRole.surface)
            } else {
                RoundedRectangle(cornerRadius: AeroTokens.Radius.control, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: AeroTokens.Radius.control, style: .continuous)
                .strokeBorder(AeroTokens.ColorRole.border, lineWidth: contrast == .increased ? 2 : 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }
}

enum AeroPermissionStatus: CaseIterable, Equatable, Sendable {
    case granted
    case required
    case denied

    var state: AeroSemanticState {
        switch self {
        case .granted: .success
        case .required: .warning
        case .denied: .danger
        }
    }

    var label: String {
        switch self {
        case .granted: "Granted"
        case .required: "Required"
        case .denied: "Denied"
        }
    }

    var actionTitle: String? {
        switch self {
        case .granted: nil
        case .required: "Grant Access…"
        case .denied: "Open System Settings…"
        }
    }
}

struct AeroPermissionState: View {
    let title: String
    let message: String
    let status: AeroPermissionStatus
    var action: (() -> Void)?

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast

    var accessibilitySummary: String { "\(title), \(status.label.lowercased()). \(message)" }

    var body: some View {
        HStack(alignment: .top, spacing: AeroTokens.Spacing.medium) {
            Image(systemName: status.state.symbol)
                .font(.title3)
                .foregroundStyle(status.state.color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AeroTokens.Spacing.xxs) {
                Text(title).font(AeroTokens.Typography.body(weight: .semibold))
                Text(message)
                    .font(AeroTokens.Typography.small())
                    .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if differentiateWithoutColor || contrast == .increased {
                    Label(status.label, systemImage: status.state.symbol)
                        .font(AeroTokens.Typography.small(weight: .semibold))
                        .foregroundStyle(status.state.color)
                } else {
                    Text(status.label)
                        .font(AeroTokens.Typography.small(weight: .semibold))
                        .foregroundStyle(status.state.color)
                }
            }

            Spacer(minLength: AeroTokens.Spacing.small)

            if let actionTitle = status.actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(AeroButtonStyle(kind: status == .denied ? .destructive : .secondary))
            }
        }
        .padding(AeroTokens.Spacing.medium)
        .background(AeroTokens.ColorRole.surfaceRaised, in: RoundedRectangle(cornerRadius: AeroTokens.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AeroTokens.Radius.control)
                .strokeBorder(status.state.color.opacity(contrast == .increased ? 1 : 0.35), lineWidth: contrast == .increased ? 2 : 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }
}
