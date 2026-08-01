import SwiftUI

struct AtlasWorkbenchAppHeader: View {
    @Binding var surface: AtlasWorkbenchSurface

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(SettingsTheme.accent)
                .frame(width: 16, height: 16)
                .overlay {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AeroTokens.ColorRole.onAccent)
                }
                .accessibilityHidden(true)
            Text("Aeroshot")
                .font(.system(size: 13, weight: .semibold))
            Text("FULL APP · CLICKABLE")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(.tertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(Array(AtlasWorkbenchSurface.allCases.enumerated()), id: \.element.id) { index, item in
                        AtlasWorkbenchSurfaceTab(index: index, item: item, surface: $surface)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Text("Press 1–9 or [ ] to switch screens")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(.bar.opacity(0.88))
    }
}

private struct AtlasWorkbenchSurfaceTab: View {
    let index: Int
    let item: AtlasWorkbenchSurface
    @Binding var surface: AtlasWorkbenchSurface

    var body: some View {
        Button {
            surface = item
            SettingsTheme.performHaptic()
        } label: {
            HStack(spacing: 5) {
                Text(index < 9 ? String(index + 1) : "0")
                    .font(SettingsTheme.typeMicro(weight: .medium, design: .monospaced))
                    .foregroundStyle(surface == item ? AnyShapeStyle(SettingsTheme.accent) : AnyShapeStyle(.tertiary))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                Text(item.tabTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(surface == item ? .primary : .secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
            .background(surface == item ? SettingsTheme.fillSelected : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(surface == item ? SettingsTheme.borderHover : .clear, lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("atlas.surface.\(item.rawValue)")
    }
}

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

struct AtlasMockupCanvas<Content: View>: View {
    let title: String
    let status: String
    var menuItems: [String] = ["File", "Capture", "Library", "Window", "Help"]
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.145, blue: 0.19), Color(red: 0.055, green: 0.075, blue: 0.10), Color(red: 0.10, green: 0.13, blue: 0.17)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Canvas { context, size in
                    let spacing: CGFloat = 22
                    for x in stride(from: 1, through: size.width, by: spacing) {
                        for y in stride(from: 1, through: size.height, by: spacing) {
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.white.opacity(0.045)))
                        }
                    }
                }
            }

            VStack(spacing: 0) {
                HStack(spacing: 15) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(SettingsTheme.accent)
                        .frame(width: 14, height: 14)
                        .overlay { Image(systemName: "camera.viewfinder").font(.system(size: 8, weight: .bold)).foregroundStyle(AeroTokens.ColorRole.onAccent) }
                    Text("Aeroshot")
                        .font(.system(size: 12, weight: .bold))
                    ForEach(menuItems, id: \.self) { item in
                        Text(item)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    Spacer(minLength: 0)
                    Text(status)
                        .font(SettingsTheme.typeMicro(design: .monospaced))
                        .foregroundStyle(.white.opacity(0.52))
                }
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(.black.opacity(0.35))

                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            AtlasMockupDock()
        }
        .frame(minHeight: 410)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
    }
}

struct AtlasMockupDock: View {
    var labels: [String] = ["Capture", "Tray", "Editor", "Studio", "Settings"]

    var body: some View {
        HStack(spacing: 9) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(index == 0 ? SettingsTheme.accent : .white.opacity(0.12))
                        .frame(width: 39, height: 39)
                        .overlay {
                            Image(systemName: ["camera.viewfinder", "tray.full", "pencil.and.outline", "wand.and.stars", "square.grid.2x2"][index])
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(index == 0 ? AeroTokens.ColorRole.onAccent : .white.opacity(0.78))
                        }
                    Text(label)
                        .font(SettingsTheme.typeMicro(design: .monospaced))
                        .foregroundStyle(.white.opacity(0.52))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 12)
        .allowsHitTesting(false)
    }
}

struct AtlasMockupWindow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(.white.opacity(0.24)).frame(width: 9, height: 9)
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .padding(.leading, 6)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(.white.opacity(0.045))
            content()
        }
        .background(Color(red: 0.055, green: 0.07, blue: 0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.38), radius: 18, y: 8)
    }
}
