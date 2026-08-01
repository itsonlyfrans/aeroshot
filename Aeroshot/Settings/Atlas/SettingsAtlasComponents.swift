import Foundation
import SwiftUI

struct SettingsAtlasSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SettingsTheme.panelRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SettingsTheme.panelRadius, style: .continuous)
                    .strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5)
            }
    }
}

struct SettingsAtlasIconBadge: View {
    let symbol: String
    var tint: Color = SettingsTheme.accent
    var size: CGFloat = 42

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct SettingsAtlasTopBar: View {
    @EnvironmentObject private var settings: SettingsStore
    @Binding var route: SettingsAtlasRoute
    @Binding var appearance: SettingsAtlasAppearance
    let openPalette: () -> Void

    private var category: SettingsAtlasCategory? {
        guard case let .category(id) = route else { return nil }
        return SettingsAtlasCategory.category(for: id)
    }

    var body: some View {
        HStack(spacing: SettingsTheme.spacingM) {
            HStack(spacing: SettingsTheme.spacingS) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(SettingsTheme.accent)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Text("A")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(AeroTokens.ColorRole.onAccent)
                    }
                    .accessibilityHidden(true)

                Button {
                    route = .atlas
                } label: {
                    Text("Atlas")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(route == .atlas ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings Atlas")

                if let category {
                    Text("›")
                        .foregroundStyle(.tertiary)
                    Text(category.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(SettingsTheme.fillHover, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Text(category.deepLink)
                        .font(SettingsTheme.typeMicro(weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: SettingsTheme.spacingM)

            HStack(spacing: SettingsTheme.spacingS) {
                Button {
                    cycleProfile()
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(SettingsTheme.accent)
                            .frame(width: 6, height: 6)
                        Text("PROFILE")
                            .font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Text(settings.activeCaptureProfile.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(SettingsTheme.fillHover, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)
                .help("Cycle capture profile")

                Button(action: openPalette) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                        Text("Search every setting")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.tertiary)
                        Text("⌘K")
                            .font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minWidth: 188, alignment: .leading)
                    .background(SettingsTheme.fillHover, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search every setting")

                HStack(spacing: 2) {
                    ForEach(SettingsAtlasAppearance.allCases) { option in
                        Button(option.label) {
                            appearance = option
                        }
                        .buttonStyle(.plain)
                        .font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced))
                        .foregroundStyle(appearance == option ? SettingsTheme.accent : AeroTokens.ColorRole.foregroundTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .background(appearance == option ? SettingsTheme.accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .accessibilityAddTraits(appearance == option ? .isSelected : [])
                    }
                }
                .padding(2)
                .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func cycleProfile() {
        let profiles = CaptureProfile.builtIn
        guard let current = profiles.firstIndex(where: { $0.id == settings.activeCaptureProfileID }) else {
            settings.applyCaptureProfile(profiles[0])
            return
        }
        settings.applyCaptureProfile(profiles[(current + 1) % profiles.count])
        SettingsTheme.performHaptic()
    }
}

struct SettingsAtlasMetricCard: View {
    let value: String
    let label: String
    let symbol: String
    var tint: Color = SettingsTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label.uppercased())
                .font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced))
                .tracking(0.55)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5)
        }
    }
}

struct SettingsAtlasCategoryCard: View {
    @EnvironmentObject private var settings: SettingsStore
    let category: SettingsAtlasCategory
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var indexLabel: String {
        guard let index = SettingsAtlasCategory.all.firstIndex(where: { $0.id == category.id }) else { return "" }
        return String(format: "%02d", index + 1)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text(indexLabel)
                        .font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    if category.needsAttention {
                        Circle()
                            .fill(SettingsTheme.warning)
                            .frame(width: 6, height: 6)
                            .accessibilityLabel("Needs attention")
                    }
                    Text("\(category.settingCount)")
                        .font(SettingsTheme.typeMicro(weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 9) {
                    SettingsAtlasIconBadge(symbol: category.symbol, size: 34)
                    Text(category.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                Text(category.blurb)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    ForEach(category.liveChips(settings: settings).prefix(3), id: \.self) { chip in
                        Text(chip)
                            .font(SettingsTheme.typeMicro(weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3.5)
                            .background(SettingsTheme.fillHover, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 146, alignment: .topLeading)
            .background(isHovered ? SettingsTheme.fillHover : SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isHovered ? SettingsTheme.borderHover : SettingsTheme.borderSubtle, lineWidth: 0.5)
            }
            .offset(y: isHovered && !reduceMotion ? -2 : 0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            SettingsTheme.animateHover(reducedMotion: reduceMotion) {
                isHovered = hovering
            }
        }
        .accessibilityLabel("Open \(category.name) settings")
        .accessibilityHint(category.blurb)
    }
}

struct SettingsAtlasBandHeader: View {
    let band: SettingsAtlasBand

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(band.title)
                .font(SettingsTheme.typeMicro(weight: .bold, design: .monospaced))
                .tracking(1.25)
                .foregroundStyle(SettingsTheme.accent)
            Text(band.blurb)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Rectangle()
                .fill(SettingsTheme.borderSubtle)
                .frame(height: 1)
                .padding(.top, 4)
        }
        .frame(width: 112, alignment: .leading)
        .padding(.top, 4)
    }
}

struct SettingsAtlasPalette: View {
    @Binding var query: String
    let results: [SettingsAtlasPaletteItem]
    let selectedIndex: Int
    let onSelect: (SettingsAtlasPaletteItem) -> Void
    let onToggle: (SettingsAtlasPaletteItem) -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search labels, values, and shortcuts", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($searchFocused)
                    .onSubmit {
                        guard let result = results[safe: selectedIndex] else { return }
                        onSelect(result)
                    }
                    .accessibilityIdentifier("settings.atlas.search")
                Text("ESC")
                    .font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .padding(15)

            Divider()

            if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.folder")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No matching settings")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Try a label, value, or shortcut.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            Button {
                                onSelect(result)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: result.symbol)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(index == selectedIndex ? SettingsTheme.accent : .secondary)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.title)
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundStyle(.primary)
                                        Text(result.detail)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    if let value = result.value {
                                        Text(value)
                                            .font(SettingsTheme.typeMicro(weight: .medium, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                    if result.isToggleable {
                                        Text("⌥↵")
                                            .font(SettingsTheme.typeMicro(weight: .medium, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(index == selectedIndex ? SettingsTheme.fillSelected : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if result.isToggleable {
                                    Button("Toggle in place") { onToggle(result) }
                                }
                                Button("Open category") { onSelect(result) }
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 360)
            }

            Divider()
            HStack(spacing: 14) {
                Text("↑↓ MOVE")
                Text("↵ OPEN")
                Text("⌥↵ TOGGLE")
                Spacer(minLength: 0)
                Text("\(results.count) MATCHES")
            }
            .font(SettingsTheme.typeMicro(weight: .medium, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
        }
        .frame(width: 660)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(SettingsTheme.borderHover, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.3), radius: 32, y: 12)
        .onAppear {
            DispatchQueue.main.async {
                searchFocused = true
            }
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
