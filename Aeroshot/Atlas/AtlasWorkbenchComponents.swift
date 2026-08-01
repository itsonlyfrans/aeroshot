import SwiftUI

struct AtlasWorkbenchSidebar: View {
    @Binding var surface: AtlasWorkbenchSurface
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(SettingsTheme.accent)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AeroTokens.ColorRole.onAccent)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aeroshot")
                        .font(.system(size: 14, weight: .semibold))
                    Text("ATLAS WORKBENCH")
                        .font(SettingsTheme.typeMicro(weight: .bold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 24)

            Text("SURFACES")
                .font(SettingsTheme.typeMicro(weight: .bold, design: .monospaced))
                .tracking(1.3)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 3) {
                    ForEach(AtlasWorkbenchSurface.allCases) { item in
                        Button {
                            surface = item
                            SettingsTheme.performHaptic()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 18)
                                Text(item.title)
                                    .font(.system(size: 12.5, weight: surface == item ? .semibold : .regular))
                                Spacer(minLength: 0)
                                if item == .settings && !SettingsPermissions.allGranted {
                                    Circle()
                                        .fill(SettingsTheme.warning)
                                        .frame(width: 6, height: 6)
                                }
                            }
                            .foregroundStyle(surface == item ? .primary : .secondary)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(surface == item ? SettingsTheme.fillSelected : .clear)
                            )
                            .overlay(alignment: .leading) {
                                if surface == item {
                                    Capsule()
                                        .fill(SettingsTheme.accent)
                                        .frame(width: 3, height: 18)
                                        .offset(x: 1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("atlas.surface.\(item.rawValue)")
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 18)

            HStack(spacing: 8) {
                Circle()
                    .fill(SettingsPermissions.allGranted ? SettingsTheme.success : SettingsTheme.warning)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(SettingsPermissions.allGranted ? "Ready to capture" : "Permissions need review")
                        .font(.system(size: 11, weight: .semibold))
                    Text(SettingsPermissions.healthLabel)
                        .font(SettingsTheme.typeMicro(design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(14)
        }
        .frame(width: 222)
        .background(.regularMaterial.opacity(0.62))
    }
}

struct AtlasWorkbenchTopBar: View {
    let surface: AtlasWorkbenchSurface
    let appState: AppState
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(surface.eyebrow)
                    .font(SettingsTheme.typeMicro(weight: .bold, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(SettingsTheme.accent)
                Text(surface.title)
                    .font(.system(size: 20, weight: .semibold))
            }
            Spacer(minLength: 0)
            AtlasWorkbenchPill(
                text: SettingsPermissions.allGranted ? "LIVE APP STATE" : "PERMISSIONS PENDING",
                color: SettingsPermissions.allGranted ? SettingsTheme.success : SettingsTheme.warning,
                symbol: SettingsPermissions.allGranted ? "bolt.fill" : "exclamationmark.triangle.fill"
            )
            Button(action: openSettings) {
                Label("Settings", systemImage: "square.grid.2x2")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(AtlasWorkbenchButtonStyle(kind: .quiet))
            .accessibilityLabel("Open Settings Atlas")
            .help("Open Settings Atlas")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.bar.opacity(0.75))
    }
}

struct AtlasWorkbenchPill: View {
    let text: String
    let color: Color
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
            Text(text)
        }
        .font(SettingsTheme.typeMicro(weight: .bold, design: .monospaced))
        .tracking(0.45)
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(color.opacity(0.11), in: Capsule())
    }
}

struct AtlasWorkbenchPanel<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SettingsTheme.accent)
                        .frame(width: 28, height: 28)
                        .background(SettingsTheme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(SettingsTheme.typeMicro())
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            content()
        }
        .padding(16)
        .background(.regularMaterial.opacity(0.66), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SettingsTheme.borderSubtle, lineWidth: 0.7)
        }
    }
}

struct AtlasWorkbenchStat: View {
    let value: String
    let label: String
    var tint: Color = SettingsTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
            Text(label.uppercased())
                .font(SettingsTheme.typeMicro(weight: .bold, design: .monospaced))
                .tracking(0.65)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

struct AtlasWorkbenchActionButton: View {
    enum Kind { case primary, secondary, quiet, destructive }

    let title: String
    let symbol: String
    var kind: Kind = .secondary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(AtlasWorkbenchButtonStyle(kind: kind))
    }
}

struct AtlasWorkbenchButtonStyle: ButtonStyle {
    let kind: AtlasWorkbenchActionButton.Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(border, lineWidth: kind == .primary ? 0 : 0.7)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(SettingsTheme.hoverAnimation, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: AeroTokens.ColorRole.onAccent
        case .secondary: .primary
        case .quiet: .secondary
        case .destructive: AeroTokens.ColorRole.danger
        }
    }

    private var background: Color {
        switch kind {
        case .primary: SettingsTheme.accent
        case .secondary: SettingsTheme.fillRest
        case .quiet: .clear
        case .destructive: AeroTokens.ColorRole.danger.opacity(0.10)
        }
    }

    private var border: Color {
        switch kind {
        case .primary: .clear
        case .secondary: SettingsTheme.borderSubtle
        case .quiet: .clear
        case .destructive: AeroTokens.ColorRole.danger.opacity(0.25)
        }
    }
}

struct AtlasWorkbenchSectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(SettingsTheme.typeMicro(weight: .bold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(SettingsTheme.accent)
            Spacer(minLength: 0)
            Text(detail)
                .font(SettingsTheme.typeMicro(design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }
}

struct AtlasWorkbenchTag: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.10), in: Capsule())
    }
}

