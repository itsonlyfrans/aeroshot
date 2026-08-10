import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

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
                    .frame(width: 22, height: 22)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2).fill(AeroTokens.ColorRole.onAccent).frame(width: 8, height: 8)
                    }
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 18)

            HStack(spacing: SettingsTheme.spacingS) {
                Button {
                    route = .atlas
                } label: {
                    Text("Atlas")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(route == .atlas ? .primary : .secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
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

            Spacer(minLength: 18)

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
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Cycle capture profile")
                .accessibilityLabel("Cycle capture profile")
                .accessibilityValue(settings.activeCaptureProfile.name)

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
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search every setting")

                HStack(spacing: 2) {
                    ForEach([SettingsAtlasAppearance.dark, .light]) { option in
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
                        .accessibilityValue(appearance == option ? "Selected" : "Not selected")
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label.uppercased())
                .font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced))
                .tracking(0.55)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 98, height: 68, alignment: .topLeading)
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
                }

                Text(category.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(category.blurb)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    ForEach(category.chips, id: \.self) { chip in
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
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(isHovered ? SettingsTheme.fillHover : SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isHovered ? SettingsTheme.borderHover : SettingsTheme.borderSubtle, lineWidth: 0.5)
            }
            .offset(y: isHovered && !reduceMotion ? -2 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
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
    @Binding var selectedIndex: Int
    let onSelect: (SettingsAtlasPaletteItem) -> Void
    let onToggle: (SettingsAtlasPaletteItem) -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .stroke(SettingsTheme.accent, lineWidth: 1.5)
                    .frame(width: 13, height: 13)
                TextField("Jump to any setting or action…", text: $query)
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
                Text("↵ FLY TO SETTING")
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
        .shadow(color: .black.opacity(0.6), radius: 40, y: 16)
        .onAppear {
            DispatchQueue.main.async {
                searchFocused = true
            }
        }
        .onChange(of: results.count) { _, count in
            selectedIndex = min(selectedIndex, max(0, count - 1))
        }
        .onMoveCommand { direction in
            guard !results.isEmpty else { return }
            switch direction {
            case .up:
                selectedIndex = selectedIndex == 0 ? results.count - 1 : selectedIndex - 1
            case .down:
                selectedIndex = (selectedIndex + 1) % results.count
            default:
                break
            }
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct SettingsAtlasPreviewGutter: View {
    @EnvironmentObject private var settings: SettingsStore

    let category: SettingsAtlasCategory
    let open: (SettingsAtlasCategoryID) -> Void
    @State private var showResetConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("LIVE PREVIEW")
                        .font(SettingsTheme.typeMicro(weight: .bold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 10)

                    previewSurface
                        .padding(12)
                        .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5)
                        }

                    Text(category.previewNote)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 11)
                }

                previewCard(title: "CHANGED HERE") {
                    let chips = category.liveChips(settings: settings)
                    ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                        HStack(spacing: 8) {
                            Text(chip)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Text("LIVE")
                                .font(SettingsTheme.typeMicro(weight: .medium, design: .monospaced))
                                .foregroundStyle(SettingsTheme.accent)
                        }
                        .padding(.vertical, 6)
                        .overlay(alignment: .top) { Divider() }
                    }
                    Button("Reset this territory") { showResetConfirmation = true }
                        .buttonStyle(SettingsAtlasValueButtonStyle(tint: .secondary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .accessibilityHint("Restore the defaults for \(category.name) settings")
                }

                previewCard(title: "NEARBY") {
                    ForEach(Array(category.nearby.enumerated()), id: \.offset) { _, relation in
                        Button {
                            open(relation.0)
                        } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(SettingsAtlasCategory.category(for: relation.0).name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Text(relation.1)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Text("→")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .top) { Divider() }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
        .background(SettingsTheme.fillRest)
        .overlay(alignment: .leading) { Divider() }
        .confirmationDialog(
            "Reset \(category.name) settings?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset territory", role: .destructive) { resetTerritory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores the settings in \(category.name) to their defaults.")
        }
    }

    @ViewBuilder
    private var previewSurface: some View {
        switch category.id {
        case .capture:
            SettingsAtlasThumbnailPreview()
        case .quickAnnotation:
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(SettingsTheme.fillHover)
                Circle().stroke(SettingsTheme.accent, lineWidth: 2).frame(width: 86, height: 86)
                HStack(spacing: 8) {
                    ForEach(["arrow.up.right", "square", "textformat", "drop"] , id: \.self) { symbol in
                        Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(SettingsTheme.accent)
                    }
                }
            }
        case .screenRecording:
            HStack(spacing: 10) {
                Circle().fill(.red).frame(width: 9, height: 9)
                Text("00:12.48").font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced))
                Spacer(minLength: 0)
                Text(settings.recordSystemAudio ? "SYSTEM AUDIO" : "MIC OFF").font(SettingsTheme.typeMicro(weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                Image(systemName: "stop.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.red)
            }
            .padding(.horizontal, 12).frame(height: 44)
            .background(SettingsTheme.fillHover, in: Capsule())
        case .gifRecording:
            VStack(alignment: .leading, spacing: 9) {
                HStack { Text("ESTIMATED SIZE").font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced)); Spacer(); Text("2.7 / 5 MB").font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced)).foregroundStyle(SettingsTheme.accent) }
                GeometryReader { proxy in
                    Capsule().fill(SettingsTheme.fillHover).overlay(alignment: .leading) { Capsule().fill(SettingsTheme.accent).frame(width: proxy.size.width * 0.54) }
                }.frame(height: 8)
                Text("(settings.gifFPS) fps · 640 px · (settings.gifMaxFrames) frames").font(SettingsTheme.typeMicro(weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            }
        case .screenshotEditor:
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(SettingsTheme.fillHover)
                VStack(spacing: 7) {
                    HStack(spacing: 6) { ForEach(0..<5, id: \.self) { _ in Circle().fill(SettingsTheme.borderSubtle).frame(width: 4, height: 4) } }
                    RoundedRectangle(cornerRadius: 4).fill(SettingsTheme.accent.opacity(0.18)).frame(width: 160, height: 78).overlay { Text("AEROSHOT").font(.system(size: 11, weight: .bold)).foregroundStyle(SettingsTheme.accent) }
                }
            }
        case .videoEditor:
            VStack(alignment: .leading, spacing: 7) {
                ForEach(["VIDEO", "MIC", "EVENTS", "OVERLAYS"], id: \.self) { lane in
                    HStack(spacing: 7) { Text(lane).font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced)).frame(width: 47, alignment: .leading); Capsule().fill(lane == "EVENTS" ? SettingsTheme.accent : SettingsTheme.fillHover).frame(height: 7) }
                }
            }
        case .mediaLibrary:
            VStack(alignment: .leading, spacing: 7) {
                ForEach(["Pictures", "Aeroshot", "2026", "August"], id: \.self) { folder in
                    HStack(spacing: 6) { Image(systemName: "folder.fill").foregroundStyle(SettingsTheme.accent); Text(folder).font(.system(size: 11)); Spacer(); Text(folder == "August" ? "18" : "").font(SettingsTheme.typeMicro(design: .monospaced)).foregroundStyle(.tertiary) }
                }
            }
        case .export:
            VStack(alignment: .leading, spacing: 8) {
                Text("FILENAME PREVIEW").font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced)).foregroundStyle(.tertiary)
                Text("Screenshot 2026-08-01 at 14-32-08.png").font(SettingsTheme.typeMicro(weight: .medium, design: .monospaced)).foregroundStyle(.primary).lineLimit(2)
                Text("\(settings.imageFormat.displayName) · \(Int(settings.jpegQuality * 100))% quality").font(SettingsTheme.typeMicro(design: .monospaced)).foregroundStyle(.secondary)
            }
        case .sharingUploads:
            VStack(alignment: .leading, spacing: 8) {
                HStack { Image(systemName: "link").foregroundStyle(SettingsTheme.accent); Text("WEBHOOK").font(SettingsTheme.typeMicro(weight: .medium, design: .monospaced)); Spacer() }
                Text(settings.uploadWebhookURL.isEmpty ? "NOT CONFIGURED" : "CONFIGURED").font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced)).foregroundStyle(SettingsTheme.accent)
            }
        case .general:
            HStack(spacing: 8) { Circle().fill(.red).frame(width: 8, height: 8); Circle().fill(.yellow).frame(width: 8, height: 8); Circle().fill(.green).frame(width: 8, height: 8); Spacer(); Image(systemName: settings.showInMenuBar ? "camera.fill" : "camera").foregroundStyle(SettingsTheme.accent); Text(settings.appPresenceSummary).font(SettingsTheme.typeMicro(weight: .medium, design: .monospaced)).foregroundStyle(.secondary) }
        case .hotkeys:
            VStack(alignment: .leading, spacing: 8) { keycapRow("Capture Area", settings.hotkeys()[.captureArea]?.displayString ?? "⌃⌥1"); keycapRow("All-in-One", settings.hotkeys()[.allInOne]?.displayString ?? "⌘Space"); keycapRow("Record Area", settings.hotkeys()[.recordArea]?.displayString ?? "⌃⌥0") }
        case .appearance:
            RoundedRectangle(cornerRadius: 8).fill(SettingsTheme.fillHover).overlay { VStack(spacing: 8) { HStack { Circle().fill(SettingsTheme.accent).frame(width: 9, height: 9); Circle().fill(SettingsTheme.success).frame(width: 9, height: 9); Circle().fill(SettingsTheme.warning).frame(width: 9, height: 9) }; RoundedRectangle(cornerRadius: 5).fill(SettingsTheme.fillRest).frame(height: 28) } .padding(12) }
        case .accessibility:
            HStack(spacing: 8) { ForEach([SettingsTheme.accent, .blue, .green, .orange, .purple], id: \.self) { color in Circle().fill(color).frame(width: 22, height: 22) } }
        case .privacy:
            VStack(alignment: .leading, spacing: 8) { Text("REDACTION").font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced)).foregroundStyle(SettingsTheme.success); HStack(spacing: 5) { RoundedRectangle(cornerRadius: 3).fill(SettingsTheme.fillHover).frame(width: 62, height: 20); RoundedRectangle(cornerRadius: 3).fill(SettingsTheme.accent.opacity(0.72)).frame(width: 80, height: 20); RoundedRectangle(cornerRadius: 3).fill(SettingsTheme.fillHover).frame(width: 44, height: 20) } }
        case .advanced:
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(SettingsTheme.accent)
                Text("CONFIGURATION")
                    .font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func keycapRow(_ label: String, _ key: String) -> some View {
        HStack { Text(label).font(.system(size: 11)); Spacer(); Text(key).font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced)).padding(.horizontal, 6).padding(.vertical, 4).background(SettingsTheme.fillHover, in: RoundedRectangle(cornerRadius: 5)) }
    }

    private func resetTerritory() {
        switch category.id {
        case .capture:
            settings.applyCaptureProfile(.standard)
            settings.resetThumbnailSettings()
            settings.captureDelaySeconds = 0
            settings.freezeScreenDuringCapture = false
            settings.downscaleRetina = false
            settings.scrollingAutoScroll = false
            settings.openEditorAfterCapture = false
            settings.copyToClipboardAfterCapture = false
            settings.saveToDiskAfterCapture = true
            settings.showThumbnailAfterCapture = true
            settings.playCaptureSound = true
        case .screenRecording, .gifRecording:
            settings.recordingFormat = .mp4
            settings.recordSystemAudio = false
            settings.recordMicrophone = false
            settings.showWebcamOverlay = false
            settings.highlightClicksDuringRecording = true
            settings.gifFPS = 10
            settings.gifMaxFrames = 300
        case .export:
            settings.imageFormat = .png
            settings.jpegQuality = 0.9
            settings.downscaleRetina = false
            settings.filenameTemplate = "Screenshot {date} at {time}"
            settings.recordingFilenameTemplate = "Screen Recording {date} at {time}"
        case .sharingUploads:
            settings.uploadAfterCapture = false
            settings.copyLinkAfterUpload = false
            settings.uploadWebhookURL = ""
        case .general:
            settings.showInMenuBar = true
            settings.showInDock = false
        default:
            return
        }
        SettingsTheme.performHaptic()
    }

    @ViewBuilder
    private func previewCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(SettingsTheme.typeMicro(weight: .bold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 8)
            content()
        }
        .padding(14)
        .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5) }
    }
}

private struct SettingsAtlasThumbnailPreview: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hovering = false
    @State private var feedbackAction: ThumbnailAction?
    @State private var dismissFeedback = false
    @State private var previewOffset: CGSize = .zero
    @State private var gestureStatus = "Drag the preview or use arrow keys."

    private var visibleActions: [ThumbnailAction] {
        settings.thumbnailVisibleActions
    }

    private var showSecondaryActions: Bool {
        settings.showThumbnailActionsAlways || hovering
    }

    private var overflowActions: [ThumbnailAction] {
        ThumbnailAction.allCases.filter { !visibleActions.contains($0) }
    }

    private var menuActions: [ThumbnailAction] {
        (showSecondaryActions ? [] : Array(visibleActions.dropFirst())) + overflowActions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 6) {
                previewCard
                previewRail
            }
            .onHover { hovering = $0 }
            .animation(SettingsTheme.spring(reducedMotion: reduceMotion), value: hovering)

            Text("\(visibleActions.count) selected · \(settings.showThumbnailActionsAlways ? "always visible" : "reveal on hover") · \(Int(settings.thumbnailDuration)) s")
                .font(SettingsTheme.typeMicro(weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Text("TEST SWIPES")
                    .font(SettingsTheme.typeMicro(weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                SettingsAtlasSegmentedControl(
                    options: ThumbnailSwipeFingerCount.allCases.map(\.title),
                    selection: Binding(
                        get: { ThumbnailSwipeFingerCount.allCases.firstIndex(of: settings.thumbnailSwipeFingerCount) ?? 0 },
                        set: { settings.thumbnailSwipeFingerCount = ThumbnailSwipeFingerCount.allCases[$0] }
                    )
                )
            }

            ForEach(ThumbnailSwipeDirection.allCases) { direction in
                mappingRow(direction)
            }

            Text(gestureStatus)
                .font(SettingsTheme.typeMicro(weight: .medium, design: .monospaced))
                .foregroundStyle(SettingsTheme.accent)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previewCard: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [Color.black.opacity(0.94), SettingsTheme.fillHover],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "photo")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(SettingsTheme.accent.opacity(0.74))
                Text("1280×720")
                    .font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced))
                    .foregroundStyle(SettingsTheme.accent)
                    .padding(4)
                    .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(6)
            }
            .frame(height: 76)

            HStack(spacing: 5) {
                Circle()
                    .fill(SettingsTheme.accent)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
                Text("Area capture")
                Spacer(minLength: 3)
                Text("LIVE")
                    .foregroundStyle(.tertiary)
            }
            .font(SettingsTheme.typeMicro(weight: .medium, design: .monospaced))
            .padding(.horizontal, 7)
            .frame(height: 27)
            .background(.regularMaterial)
        }
        .frame(width: 176, height: 103)
        .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(SettingsTheme.accent.opacity(hovering ? 0.7 : 0.35), lineWidth: hovering ? 1 : 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .offset(previewOffset)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 8)
                .onEnded {
                    testGesture(CGSize(width: $0.translation.width, height: -$0.translation.height))
                }
        )
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .left:
                testGesture(CGSize(width: -48, height: 0))
            case .right:
                testGesture(CGSize(width: 48, height: 0))
            case .up:
                testGesture(CGSize(width: 0, height: 48))
            case .down:
                testGesture(CGSize(width: 0, height: -48))
            default:
                break
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Thumbnail gesture preview")
        .accessibilityHint("Drag or use arrow keys to test a thumbnail swipe")
    }

    private var previewRail: some View {
        VStack(spacing: 3) {
            if let action = visibleActions.first {
                previewActionButton(action)
            }
            if showSecondaryActions {
                ForEach(Array(visibleActions.dropFirst())) { action in
                    previewActionButton(action)
                }
            }

            Menu {
                ForEach(menuActions) { action in
                    Button {
                        previewAction(action)
                    } label: {
                        Label(action.title, systemImage: action.symbol)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AeroTokens.ColorRole.onAccent)
                    .frame(width: 27, height: 27)
                    .background(SettingsTheme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .menuStyle(.button)
            .buttonStyle(AeroPressableStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More preview actions")
            .accessibilityLabel("More preview thumbnail actions")

            Button {
                dismissPreview()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(dismissFeedback ? SettingsTheme.accent : .secondary)
                    .frame(width: 27, height: 27)
                    .background(
                        dismissFeedback ? SettingsTheme.accent.opacity(0.16) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
            }
            .buttonStyle(AeroPressableStyle())
            .help("Dismiss preview (Settings stays open)")
            .accessibilityLabel("Dismiss preview thumbnail")
        }
        .padding(3)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }

    private func previewActionButton(_ action: ThumbnailAction) -> some View {
        Button {
            previewAction(action)
        } label: {
            Image(systemName: action.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(feedbackAction == action ? SettingsTheme.accent : .secondary)
                .frame(width: 27, height: 27)
                .background(
                    feedbackAction == action ? SettingsTheme.accent.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
        .buttonStyle(AeroPressableStyle())
        .help("Preview \(action.title)")
        .accessibilityLabel("Preview \(action.title)")
    }

    private func mappingRow(_ direction: ThumbnailSwipeDirection) -> some View {
        let action = settings.thumbnailSwipeBindings.action(for: settings.thumbnailSwipeFingerCount, direction: direction)
        return HStack(spacing: 7) {
            Image(systemName: direction.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SettingsTheme.accent)
                .frame(width: 14)
            Text(direction.title)
                .font(SettingsTheme.typeSmall(weight: .medium))
            Spacer(minLength: 4)
            Text(action.title)
                .font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(settings.thumbnailSwipeFingerCount.title) \(direction.title) swipe")
        .accessibilityValue(action.title)
    }

    private func previewAction(_ action: ThumbnailAction) {
        feedbackAction = action
        dismissFeedback = false
        gestureStatus = "Preview: \(action.title) selected"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if feedbackAction == action {
                feedbackAction = nil
            }
        }
    }

    private func dismissPreview() {
        feedbackAction = nil
        dismissFeedback = true
        gestureStatus = "Preview: Dismiss selected (Settings stays open)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            dismissFeedback = false
        }
    }

    private func testGesture(_ translation: CGSize) {
        guard let direction = ThumbnailSwipeResolver.direction(for: translation, minimumDistance: 24) else {
            gestureStatus = "No clear swipe direction"
            previewOffset = .zero
            return
        }

        let action = settings.thumbnailSwipeBindings.action(for: settings.thumbnailSwipeFingerCount, direction: direction)
        gestureStatus = "Resolved: \(direction.title) → \(action.title)"
        guard !reduceMotion else { return }

        let offset: CGSize
        switch direction {
        case .left:
            offset = CGSize(width: -12, height: 0)
        case .right:
            offset = CGSize(width: 12, height: 0)
        case .up:
            offset = CGSize(width: 0, height: -10)
        case .down:
            offset = CGSize(width: 0, height: 10)
        }
        withAnimation(SettingsTheme.spring(reducedMotion: false)) {
            previewOffset = offset
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(SettingsTheme.spring(reducedMotion: false)) {
                previewOffset = .zero
            }
        }
    }
}

// MARK: - Atlas territory controls

/// The territory view intentionally has its own row language. The old settings
/// panes remain available to the legacy navigation surface, but Atlas never
/// drops back into those panels once a category is opened.
struct SettingsAtlasTerritoryView: View {
    let category: SettingsAtlasCategoryID
    @Binding var highlightedRowID: String?

    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var focusedRowID: String?
    @State private var hotkeys: [HotkeyAction: Hotkey] = [:]
    @State private var hotkeyErrors: [HotkeyAction: String] = [:]
    @State private var showResetConfirmation = false
    @AppStorage("settingsAtlasAppearance") private var appearanceRaw = SettingsAtlasAppearance.system.rawValue
    @AppStorage("settingsAtlasIncreaseContrast") private var increaseContrast = false
    @AppStorage("settingsAtlasReduceTransparency") private var reduceTransparency = false
    @AppStorage("settingsAtlasSafeAnnotationPalette") private var safeAnnotationPalette = true

    static func sectionTitles(for category: SettingsAtlasCategoryID) -> [String] {
        switch category {
        case .capture: ["Modes & memory", "Timing", "Cursor & chrome", "Selection surface", "Displays & resolution", "After capture"]
        case .quickAnnotation: ["Toolbar composition", "Defaults", "Numbered steps", "Quick actions"]
        case .screenRecording: ["Format & quality", "Audio", "Webcam", "Cursor & input", "Session"]
        case .gifRecording: ["Frames & size", "Colour", "Loop & speed", "Budget"]
        case .screenshotEditor: ["Canvas", "Guides & snapping", "Objects & layers", "Presets", "Intelligence", "Output"]
        case .videoEditor: ["Timeline", "Motion", "Audio & captions", "Performance"]
        case .mediaLibrary: ["Location & structure", "Organisation", "Sync", "Lifecycle"]
        case .export: ["Formats", "Naming & destination", "Safety & feedback"]
        case .sharingUploads: ["Upload"]
        case .general: ["Startup & presence", "Session", "Updates", "Notifications & confirmations", "Language & region"]
        case .hotkeys: ["Capture", "Recording", "Session", "Behaviour"]
        case .appearance: ["Theme", "Density & scale", "Surfaces", "Motion", "Themes"]
        case .accessibility: ["Motion & contrast", "Colour", "Targets & focus", "Navigation & speech"]
        case .privacy: ["Redaction", "Permissions"]
        case .advanced: ["Performance", "Storage", "Extensibility", "Configuration"]
        }
    }

    private var sectionTitles: [String] { Self.sectionTitles(for: category) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
            .onAppear {
                hotkeys = settings.hotkeys()
                revealHighlightedRow(with: proxy)
            }
            .onChange(of: highlightedRowID) { _, _ in
                revealHighlightedRow(with: proxy)
            }
        }
        .background(SettingsAtlasBackground())
        .accessibilityIdentifier("settings.atlas.territory.\(category.rawValue)")
        .confirmationDialog(
            "Reset all settings?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset all settings", role: .destructive) {
                settings.resetAllToDefaults()
                SettingsTheme.performHaptic()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores every preference and keyboard shortcut to factory defaults.")
        }
    }

    private func revealHighlightedRow(with proxy: ScrollViewProxy) {
        guard let rowID = highlightedRowID else { return }
        Task { @MainActor in
            await Task.yield()
            guard highlightedRowID == rowID else { return }
            withAnimation(SettingsTheme.spring(reducedMotion: reduceMotion)) {
                proxy.scrollTo(rowID, anchor: .center)
            }
            focusedRowID = rowID
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard highlightedRowID == rowID else { return }
            withAnimation(SettingsTheme.spring(reducedMotion: reduceMotion)) {
                highlightedRowID = nil
            }
        }
    }


    @ViewBuilder
    private var content: some View {
        switch category {
        case .capture:
            captureContent
        case .quickAnnotation:
            quickAnnotationContent
        case .screenRecording:
            screenRecordingContent
        case .gifRecording:
            gifRecordingContent
        case .screenshotEditor:
            screenshotEditorContent
        case .videoEditor:
            videoEditorContent
        case .mediaLibrary:
            mediaLibraryContent
        case .export:
            exportContent
        case .sharingUploads:
            sharingContent
        case .general:
            generalContent
        case .hotkeys:
            hotkeysContent
        case .appearance:
            appearanceContent
        case .accessibility:
            accessibilityContent
        case .privacy:
            privacyContent
        case .advanced:
            advancedContent
        }
    }

    @ViewBuilder
    private var captureContent: some View {
        section("Modes & memory") {
            row("Default screenshot mode", "What the primary shortcut does with no modifiers", id: "capture.mode") {
                value("Region")
            }
            row("Remember last capture region", "Re-offer the previous rectangle, pre-selected", id: "capture.last-region") {
                toggle($settings.recallLastRegionEnabled)
            }
            row("Selection aspect lock", "Keep area captures at a repeatable ratio", id: "capture.aspect") {
                choice(
                    options: SelectionAspectLock.allCases.map(\.displayName),
                    selection: Binding(
                        get: { SelectionAspectLock.allCases.firstIndex(of: settings.selectionAspectLock) ?? 0 },
                        set: { settings.selectionAspectLock = SelectionAspectLock.allCases[$0] }
                    )
                )
            }
            row("Window detection", "How aggressively Aeroshot snaps to window edges", id: "capture.window-detection") {
                value("Hover")
            }
        }

        section("Timing") {
            row("Capture delay", "Countdown before the overlay starts", id: "capture.delay") {
                choice(
                    options: ["Off", "3s", "5s", "10s"],
                    selection: Binding(
                        get: { [0, 3, 5, 10].firstIndex(of: settings.captureDelaySeconds) ?? 0 },
                        set: { settings.captureDelaySeconds = [0, 3, 5, 10][$0] }
                    )
                )
            }
            row("Post-shutter freeze", "Hold the frozen frame before the editor takes over", id: "capture.freeze") {
                HStack(spacing: 8) {
                    toggle($settings.freezeScreenDuringCapture)
                    value(settings.freezeScreenDuringCapture ? "350 ms" : "Off")
                }
            }
        }

        section("Cursor & chrome") {
            row("Play capture sound", "Audible confirmation when a capture completes", id: "capture.sound") {
                toggle($settings.playCaptureSound)
            }
            row("Sound effect", "Sampled from the built-in set", id: "capture.sound-effect") {
                AeroMenuPicker(
                    options: settings.availableSounds.map(\.filename),
                    selection: $settings.selectedCaptureSound,
                    label: { filename in settings.availableSounds.first { $0.filename == filename }?.displayName ?? filename }
                )
            }
            row("Cursor in captures", "Draw the pointer into the image", id: "capture.cursor") {
                value("System default")
            }
            row("Alignment guides", "Snap lines against window and screen edges", id: "capture.guides") {
                value("On")
            }
        }

        section("Selection surface") {
            row("Selection border colour", "Used for handles and the dimension readout", id: "capture.border") {
                swatches(colors: [SettingsTheme.accent, .blue, .green, .orange, .white], selected: 0)
            }
            row("Dim outside selection", "Opacity of the mask over everything unselected", id: "capture.dim") {
                value("50%")
            }
            row("Annotate during capture", "Open annotation before you choose the capture region", id: "capture.annotate") {
                value("Before region selection")
            }
            row("Dimension readout", "Where the live size label sits", id: "capture.readout") {
                value("Top-left")
            }
        }

        section("Displays & resolution") {
            row("Multi-monitor", "Behaviour when the pointer crosses displays", id: "capture.displays") {
                value("Active display")
            }
            row("Retina handling", "Pixel density written into the file", id: "capture.retina") {
                HStack(spacing: 8) {
                    toggle($settings.downscaleRetina)
                    value(settings.downscaleRetina ? "@1x" : "@2x")
                }
            }
            row("Scrolling capture auto-stitch", "Detect scroll end and merge without asking", id: "capture.scroll") {
                HStack(spacing: 8) {
                    if settings.scrollingAutoScroll && !SettingsPermissions.accessibilityGranted {
                        Button("Grant") { SettingsPermissions.requestAccessibility() }
                            .buttonStyle(SettingsAtlasValueButtonStyle(tint: SettingsTheme.warning))
                    }
                    toggle($settings.scrollingAutoScroll)
                }
            }
            row("Scroll overlap tolerance", "How much repeated content the stitcher allows", id: "capture.scroll-overlap") {
                value("120 px")
            }
        }

        section("After capture") {
            row("Open full editor", "Skip the thumbnail and go straight to the canvas", id: "capture.editor") {
                toggle($settings.openEditorAfterCapture)
            }
            row("Copy to clipboard", "Paste captured images right away", id: "capture.clipboard") {
                toggle($settings.copyToClipboardAfterCapture)
            }
            row("Save to disk", "Write to the output folder automatically", id: "capture.save") {
                toggle($settings.saveToDiskAfterCapture)
            }
            row("Quick-access thumbnail", "Floating preview in the corner", id: "capture.thumbnail") {
                toggle($settings.showThumbnailAfterCapture)
            }
            row("Thumbnail quick actions", "Choose the actions shown when you hover the preview", id: "capture.thumbnail-actions") {
                VStack(alignment: .trailing, spacing: 4) {
                    Menu {
                        ForEach(ThumbnailAction.allCases) { action in
                            let selected = settings.thumbnailVisibleActions.contains(action)
                            Button {
                                settings.setThumbnailAction(action, visible: !selected)
                            } label: {
                                Label(action.title, systemImage: selected ? "checkmark" : action.symbol)
                            }
                            .disabled(!selected && settings.thumbnailVisibleActions.count >= 4)
                        }
                    } label: {
                        AeroMenuLabel(title:
                            settings.thumbnailVisibleActions.isEmpty
                                ? "None"
                                : settings.thumbnailVisibleActions.map(\.title).joined(separator: " · ")
                        )
                    }
                    Text("\(settings.thumbnailVisibleActions.count)/4 selected · 4 max")
                        .font(SettingsTheme.typeMicro(weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            row("Always show actions", "Keep the configured thumbnail actions visible", id: "capture.thumbnail-actions-always") {
                toggle($settings.showThumbnailActionsAlways)
            }
            row("Thumbnail duration", "How long the preview remains visible", id: "capture.thumbnail-duration") {
                slider(value: $settings.thumbnailDuration, range: 1...15, step: 1, valueText: "\(Int(settings.thumbnailDuration)) s")
            }
            row("Swipe fingers", "Choose the two- or three-finger mappings to edit", id: "capture.thumbnail-swipe-fingers") {
                choice(
                    options: ThumbnailSwipeFingerCount.allCases.map(\.title),
                    selection: Binding(
                        get: { ThumbnailSwipeFingerCount.allCases.firstIndex(of: settings.thumbnailSwipeFingerCount) ?? 0 },
                        set: { settings.thumbnailSwipeFingerCount = ThumbnailSwipeFingerCount.allCases[$0] }
                    )
                )
            }
            ForEach(ThumbnailSwipeDirection.allCases) { direction in
                row(
                    "\(settings.thumbnailSwipeFingerCount.title) · \(direction.title) swipe",
                    "Action for this thumbnail gesture",
                    id: "capture.thumbnail-swipe.\(settings.thumbnailSwipeFingerCount.rawValue).\(direction.rawValue)"
                ) {
                    thumbnailSwipeMenu(fingers: settings.thumbnailSwipeFingerCount, direction: direction)
                }
            }
        }
    }

    private func thumbnailSwipeMenu(
        fingers: ThumbnailSwipeFingerCount,
        direction: ThumbnailSwipeDirection
    ) -> some View {
        let selected = settings.thumbnailSwipeBindings.action(for: fingers, direction: direction)
        return AeroMenuPicker(
            options: ThumbnailGestureAction.allCases,
            selection: Binding(
                get: { selected },
                set: { settings.setThumbnailSwipeAction($0, fingers: fingers, direction: direction) }
            ),
            label: \.title
        )
    }

    @ViewBuilder
    private var quickAnnotationContent: some View {
        section("Toolbar composition") {
            row("Tools shown", "Arrow · Box · Text · Step · Blur · Highlight · Crop", id: "annot.tools") { value("7 tools") }
            row("Placement", "Where the ring attaches to the capture", id: "annot.placement") { value("Nearest edge") }
            row("Auto-reposition", "Move out of the way when it would cover content", id: "annot.reposition") { value("On") }
            row("Remember last tool", "Reopen with whatever you used last", id: "annot.last-tool") { value("On") }
        }
        section("Defaults") {
            row("Default colour", "Applies to new arrows, shapes, and text", id: "annot.colour") { swatches(colors: [SettingsTheme.accent, .red, .yellow, .green, .blue], selected: 0) }
            row("Redaction style", "How sensitive regions are covered", id: "annot.redaction") {
                choice(options: ShareSafeRedactionStyle.allCases.map(\.displayName), selection: Binding(get: { ShareSafeRedactionStyle.allCases.firstIndex(of: settings.shareSafeRedactionStyle) ?? 0 }, set: { settings.shareSafeRedactionStyle = ShareSafeRedactionStyle.allCases[$0] }))
            }
            row("Beautify by default", "Apply presentation framing to new editor documents", id: "annot.beautify") { toggle($settings.beautifyEnabledDefault) }
            row("Canvas padding", "Breathing room around the captured image", id: "annot.padding") { slider(value: $settings.beautifyPadding, range: 0...160, step: 4, valueText: "\(Int(settings.beautifyPadding)) pt") }
        }
        section("Numbered steps") {
            row("Step counter", "What each new step badge shows", id: "annot.step-counter") { value("1, 2, 3") }
            row("Auto-increment across captures", "Continue the sequence into the next screenshot", id: "annot.step-auto") { value("On") }
            row("Badge size", "Diameter of the step marker", id: "annot.badge") { value("28 pt") }
        }
        section("Quick actions") {
            row("Text presets", "Saved type styles offered under the text tool", id: "annot.text-presets") { value("Caption · Callout · Label") }
            row("Primary action", "What the big button on the ring does", id: "annot.primary") { value("Copy") }
            row("Show secondary actions", "Reveal the other actions behind a press-and-hold", id: "annot.secondary") { value("On") }
        }
    }

    @ViewBuilder
    private var screenRecordingContent: some View {
        section("Format & quality") {
            row("Container", "Written to disk when the recording stops", id: "rec.container") {
                choice(options: RecordingFormat.allCases.map(\.displayName), selection: Binding(get: { settings.recordingFormat == .mp4 ? 0 : 1 }, set: { settings.recordingFormat = $0 == 0 ? .mp4 : .gif }))
            }
            row("Frame rate", "Higher is smoother; cursor motion benefits most", id: "rec.fps") {
                value("60 fps")
            }
            row("Resolution", "Downscaled from the source at capture time", id: "rec.resolution") { value("Native") }
            row("Quality", "Bitrate and output quality target", id: "rec.quality") { value("High") }
        }
        section("Audio") {
            row("Capture system audio", "Include everything the Mac is playing", id: "rec.system-audio") { toggle($settings.recordSystemAudio) }
            row("Record microphone", "Voice in recordings", id: "rec.microphone") { toggle($settings.recordMicrophone) }
            row("Microphone", "Input device for narration", id: "rec.microphone-device") { value(settings.recordingMicrophoneDeviceID.isEmpty ? "System default" : settings.recordingMicrophoneDeviceID) }
            row("Noise suppression", "Remove fan and room tone in real time", id: "rec.noise") { value("System") }
        }
        section("Webcam") {
            row("Webcam overlay", "Picture-in-picture bubble", id: "rec.webcam") { toggle($settings.showWebcamOverlay) }
            row("Camera", "Source for the presenter bubble", id: "rec.camera") { value("System default") }
            row("Frame style", "Shape of the webcam overlay", id: "rec.camera-style") { value("Circle") }
            row("Bubble size", "Diameter relative to the shorter screen edge", id: "rec.camera-size") { value("18%") }
        }
        section("Cursor & input") {
            row("Cursor highlight", "Soft halo that follows the pointer", id: "rec.click-highlight") { toggle($settings.highlightClicksDuringRecording) }
            row("Show cursor", "Draw the pointer into the video", id: "rec.cursor") { value("On") }
            row("Keystroke display", "Show pressed keys in a corner overlay", id: "rec.keys") { value("Off") }
            row("Cursor smoothing", "Damps hand jitter in the recorded pointer path", id: "rec.smoothing") { value("40%") }
        }
        section("Session") {
            row("Recording location", "Where finished recordings are written", id: "rec.location") { pathValue(settings.saveDirectoryPath) }
            row("Add recordings to history", "Keep finished recordings in the library", id: "rec.history") { toggle($settings.addRecordingsToHistory) }
            row("GIF frame budget", "Maximum frames for animated captures", id: "rec.gif-frames") { slider(value: Binding(get: { Double(settings.gifMaxFrames) }, set: { settings.gifMaxFrames = Int($0.rounded()) }), range: 30...900, step: 30, valueText: "\(settings.gifMaxFrames) frames") }
        }
    }

    @ViewBuilder
    private var gifRecordingContent: some View {
        section("Frames & size") {
            row("Frame rate", "Higher is smoother and larger", id: "gif.fps") { slider(value: Binding(get: { Double(settings.gifFPS) }, set: { settings.gifFPS = Int($0.rounded()) }), range: 6...30, step: 1, valueText: "\(settings.gifFPS) fps") }
            row("Maximum frames", "Hard upper bound for the recording", id: "gif.frames") { slider(value: Binding(get: { Double(settings.gifMaxFrames) }, set: { settings.gifMaxFrames = Int($0.rounded()) }), range: 30...900, step: 30, valueText: "\(settings.gifMaxFrames)") }
            row("Container", "GIF mode is selected in the recording surface", id: "gif.container") { value(settings.recordingFormat == .gif ? "Animated GIF" : "MP4 Video") }
            row("Automatic optimisation", "Drop duplicate frames and quantise on the fly", id: "gif.optimise") { value("On") }
        }
        section("Colour") {
            row("Palette size", "Fewer colours produce smaller files", id: "gif.palette") { value("256") }
            row("Dithering", "Trades noise for smoother gradients", id: "gif.dither") { value("Floyd–Steinberg") }
            row("Transparent background", "Requires a source with alpha", id: "gif.alpha") { value("Off") }
        }
        section("Loop & speed") {
            row("Loop", "Playback behaviour in browsers and chat clients", id: "gif.loop") { value("Forever") }
            row("Playback speed", "Applied at encode time", id: "gif.speed") { value("100%") }
            row("Hold last frame", "Add a pause before the loop restarts", id: "gif.hold") { value("On") }
        }
        section("Budget") {
            row("Size ceiling", "The number every other control is measured against", id: "gif.budget") { value("5 MB") }
            row("Warn before export", "Interrupt only when the estimate exceeds the ceiling", id: "gif.warn") { value("On") }
            row("When over budget", "What Aeroshot proposes automatically", id: "gif.over") { value("Suggest fixes") }
        }
    }

    @ViewBuilder
    private var screenshotEditorContent: some View {
        section("Canvas") {
            row("Default background", "Behind the captured image", id: "editor.background") { value(settings.beautifyGradientPreset.displayName) }
            row("Canvas padding", "Breathing room around the image", id: "editor.padding") { slider(value: $settings.beautifyPadding, range: 0...160, step: 4, valueText: "\(Int(settings.beautifyPadding)) pt") }
            row("Image corner radius", "Rounding applied to the capture itself", id: "editor.radius") { slider(value: $settings.beautifyCornerRadius, range: 0...40, step: 2, valueText: "\(Int(settings.beautifyCornerRadius)) pt") }
            row("Shadow", "Depth under the captured image", id: "editor.shadow") { slider(value: $settings.beautifyShadowRadius, range: 0...80, step: 2, valueText: "\(Int(settings.beautifyShadowRadius)) pt") }
            row("Beautify by default", "Apply presentation framing to new editor documents", id: "editor.beautify") { toggle($settings.beautifyEnabledDefault) }
        }
        section("Guides & snapping") {
            row("Aspect preset", "Default canvas ratio for new documents", id: "editor.aspect") {
                choice(options: BeautifySettings.AspectPreset.allCases.map(\.displayName), selection: Binding(get: { BeautifySettings.AspectPreset.allCases.firstIndex(of: settings.beautifyAspectPreset) ?? 0 }, set: { settings.beautifyAspectPreset = BeautifySettings.AspectPreset.allCases[$0] }))
            }
            row("Dot grid", "Faint alignment grid on the canvas", id: "editor.grid") { value("On") }
            row("Snap to grid", "Objects land on the grid step", id: "editor.snap") { value("On") }
            row("Grid step", "Distance between snap points", id: "editor.grid-step") { value("8 pt") }
        }
        section("Objects & layers") {
            row("New object placement", "Where a tool drops its first object", id: "editor.placement") { value("At cursor") }
            row("Select behind on repeat click", "Cycle downward through stacked objects", id: "editor.cycle") { value("On") }
            row("Auto-group related annotations", "Steps and labels move together", id: "editor.group") { value("On") }
            row("Undo history", "Steps kept per document", id: "editor.undo") { value("200 steps") }
        }
        section("Presets") {
            row("Font defaults", "Applied to new text objects", id: "editor.font") { value("SF Pro Text · 15 pt") }
            row("Shape defaults", "Applied to new boxes and ellipses", id: "editor.shape") { value("2 pt stroke · coral") }
            row("Gradient preset", "Applied to the presentation background", id: "editor.gradient") {
                choice(options: BeautifySettings.GradientPreset.allCases.map(\.displayName), selection: Binding(get: { BeautifySettings.GradientPreset.allCases.firstIndex(of: settings.beautifyGradientPreset) ?? 0 }, set: { settings.beautifyGradientPreset = BeautifySettings.GradientPreset.allCases[$0] }))
            }
        }
        section("Intelligence") {
            row("Sensitive-information detection", "Find emails, keys, and card numbers on the canvas", id: "editor.scan") { toggle($settings.shareSafeSmartScan) }
            row("Default redaction", "Applied when you accept a suggestion", id: "editor.redaction") {
                choice(options: ShareSafeRedactionStyle.allCases.map(\.displayName), selection: Binding(get: { ShareSafeRedactionStyle.allCases.firstIndex(of: settings.shareSafeRedactionStyle) ?? 0 }, set: { settings.shareSafeRedactionStyle = ShareSafeRedactionStyle.allCases[$0] }))
            }
            row("Copy recognised text with the image", "Puts both on the clipboard", id: "editor.ocr") { toggle($settings.addOCRCapturesToHistory) }
        }
        section("Output") {
            row("Default format", "Used by save from the editor", id: "editor.format") { imageFormatChoice }
            row("JPEG quality", "Only applies to lossy formats", id: "editor.quality") {
                slider(value: $settings.jpegQuality, range: 0.4...1, step: 0.01, valueText: "\(Int(settings.jpegQuality * 100))%")
                    .disabled(settings.imageFormat == .png)
                    .help("Only available when the default format is a lossy image format")
            }
            row("Autosave frequency", "Interval for the recovery snapshot", id: "editor.autosave") { value("30 s") }
        }
    }

    @ViewBuilder
    private var videoEditorContent: some View {
        section("Timeline") {
            row("Default scale", "Zoom level when a project opens", id: "video.scale") { value("Fit") }
            row("Magnetic snapping", "Clips and markers attract to each other", id: "video.snap") { value("On") }
            row("Show audio waveform", "Draw speech amplitude in the audio lane", id: "video.waveform") { value("On") }
            row("Collapse empty lanes", "Hide lanes with no events in this project", id: "video.collapse") { value("On") }
        }
        section("Motion") {
            row("Automatic zoom", "Push in on clusters of clicks and typing", id: "video.zoom") { value("On") }
            row("Zoom intensity", "How far an automatic zoom travels", id: "video.zoom-intensity") { value("35%") }
            row("Cursor smoothing", "Applied in the editor on top of capture smoothing", id: "video.smoothing") { value("25%") }
            row("Remove idle sections", "Cut detected idle automatically on import", id: "video.idle") { value("Off") }
        }
        section("Audio & captions") {
            row("Generate captions", "Speech to text on device when a project opens", id: "video.captions") { value("On device") }
            row("Caption language", "Used for recognition and caption files", id: "video.language") { value("English (US)") }
            row("Caption style", "Burned-in appearance in the render", id: "video.caption-style") { value("Minimal") }
            row("Duck system audio under speech", "Automatic level ride", id: "video.duck") { value("Off") }
        }
        section("Performance") {
            row("Playback quality", "Preview only; never affects the render", id: "video.quality") { value("Half") }
            row("Generate proxies", "Low-res working copies for smooth scrubbing", id: "video.proxies") { value("On") }
            row("Render in background", "Keep exporting while you open another project", id: "video.background") { value("On") }
            row("Recordings in history", "Keep finished projects in the library", id: "video.history") { toggle($settings.addRecordingsToHistory) }
        }
    }

    @ViewBuilder
    private var mediaLibraryContent: some View {
        section("Location & structure") {
            row("Library location", "Root folder for all captures", id: "library.location") { pathValue(settings.saveDirectoryPath, choose: chooseSaveDirectory) }
            row("Folder organisation", "Subfolder pattern under the root", id: "library.organisation") { value("By month") }
            row("Separate recordings folder", "Keep video out of screenshot folders", id: "library.recordings") { value("On") }
        }
        section("Organisation") {
            row("Automatic tags", "Tag by source app, display, and detected content", id: "library.tags") { value("On") }
            row("OCR index", "Keep recognised text searchable in history", id: "library.ocr") { toggle($settings.addOCRCapturesToHistory) }
            row("Favourites", "Star captures from the thumbnail and library", id: "library.favourites") { value("Available") }
        }
        section("Sync") {
            row("Cloud synchronisation", "Keep previews available on your other Macs", id: "library.sync") { value("Off") }
        }
    }

    @ViewBuilder
    private var exportContent: some View {
        section("Formats") {
            row("Screenshots", "Default image format", id: "export.image-format") { imageFormatChoice }
            row("Video", "Default video container", id: "export.video-format") {
                AeroMenuPicker(options: RecordingFormat.allCases, selection: $settings.recordingFormat, label: \.displayName)
            }
            row("GIF", "Encoder used for looping exports", id: "export.gif-format") { value("Optimised") }
            row("Image quality", "Applies to lossy image formats", id: "export.quality") {
                slider(value: $settings.jpegQuality, range: 0.4...1, step: 0.01, valueText: "\(Int(settings.jpegQuality * 100))%")
                    .disabled(settings.imageFormat == .png)
                    .help("Only available when Screenshots is set to a lossy image format")
            }
        }
        section("Naming & destination") {
            row("Naming template", "Tokens resolve at write time", id: "export.template") { textField($settings.filenameTemplate, placeholder: "Screenshot {date} at {time}") }
            row("Recording filename template", "Tokens resolve when a video or GIF is written", id: "export.recording-template") { textField($settings.recordingFilenameTemplate, placeholder: "Screen Recording {date} at {time}") }
            row("Collision handling", "When the name already exists", id: "export.collision") { value("Add counter") }
            row("Screenshot destination", "Folder for exported images", id: "export.destination") { pathValue(settings.saveDirectoryPath, choose: chooseSaveDirectory) }
            row("Downscale Retina captures", "Write a 1× image to disk", id: "export.retina") { toggle($settings.downscaleRetina) }
        }
        section("Safety & feedback") {
            row("Copy to clipboard on export", "Put exported image data on the clipboard", id: "export.clipboard") { toggle($settings.copyToClipboardAfterCapture) }
            row("Notify when exports finish", "System notification with a reveal action", id: "export.notify") { value("On") }
        }
    }

    @ViewBuilder
    private var sharingContent: some View {
        section("Upload") {
            row("Webhook URL", "HTTPS endpoint for captured files", id: "share.endpoint") { textField($settings.uploadWebhookURL, placeholder: "https://your-server.com/upload") }
            row("Upload after capture", "Send files to the configured webhook", id: "share.upload") { toggle($settings.uploadAfterCapture) }
            row("Copy returned link", "Put a webhook response link on the clipboard", id: "share.copy") { toggle($settings.copyLinkAfterUpload) }
            row("Redact before upload", "Require redaction review for flagged captures", id: "share.warn") { toggle($settings.shareSafeRedactBeforeSharing) }
        }
    }

    @ViewBuilder
    private var generalContent: some View {
        section("Startup & presence") {
            row("Show in menu bar", "Camera icon with the capture menu", id: "general.menu-bar") { toggle($settings.showInMenuBar) }
            row("Show in Dock", "Keep an app icon for quick access", id: "general.dock") { toggle($settings.showInDock) }
            row("Default startup screen", "What opens when the app is activated", id: "general.startup") { value("Nothing") }
            row("Capture profile", "Preset bundle for capture and export", id: "general.profile") {
                AeroMenuPicker(
                    options: CaptureProfile.builtIn.map(\.id),
                    selection: Binding(
                        get: { settings.activeCaptureProfileID },
                        set: { id in
                            guard let profile = CaptureProfile.builtIn.first(where: { $0.id == id }) else { return }
                            settings.applyCaptureProfile(profile)
                        }
                    ),
                    label: { id in CaptureProfile.builtIn.first { $0.id == id }?.name ?? id }
                )
            }
        }
        section("Session") {
            row("Restore windows", "Reopen editors and projects from the last session", id: "general.restore") { value("On") }
            row("Autosave interval", "Applies to editors and recordings in progress", id: "general.autosave") { value("30 s") }
            row("Keep recovery snapshots", "Survive a crash mid-edit", id: "general.recovery") { value("On") }
        }
        section("Updates") {
            row("Update channel", "How new builds reach you", id: "general.channel") { value("Beta") }
            row("Check automatically", "Once a day in the background", id: "general.check") { value("On") }
            row("Download in the background", "Install on next launch, never mid-capture", id: "general.download") { value("On") }
        }
        section("Notifications & confirmations") {
            row("Notifications", "System notifications Aeroshot may post", id: "general.notifications") { value("All") }
            row("Confirm before discarding an edit", "One dialog only when work would be lost", id: "general.discard") { value("On") }
            row("Confirm before deleting from the library", "Trash is recoverable", id: "general.delete") { value("Off") }
            row("Confirm before overwriting a file", "Only when the name already exists", id: "general.overwrite") { value("On") }
        }
        section("Language & region") {
            row("Language", "Interface language", id: "general.language") { value("System (English)") }
            row("Region formatting", "Dates and numbers in filenames and captions", id: "general.region") { value("System") }
            row("Date token format", "Resolves the {date} token in naming templates", id: "general.date") { value("2026-08-01") }
        }
    }

    @ViewBuilder
    private var hotkeysContent: some View {
        hotkeySection("Capture", actions: HotkeyAction.allCases.filter { $0.settingsSection == .capture })
        hotkeySection("Recording", actions: HotkeyAction.allCases.filter { $0.settingsSection == .recording })
        hotkeySection("Session", actions: [.showHistory])
        section("Behaviour") {
            row("Warn about conflicts before saving", "Rather than after the shortcut fails", id: "hotkeys.warn") { value("On") }
            row("Allow app-only fallback", "Keep bindings working inside Aeroshot when global fails", id: "hotkeys.fallback") { value("On") }
            row("Accessibility access", "Required for global shortcuts", id: "hotkeys.access") {
                Button(SettingsPermissions.accessibilityGranted ? "Granted" : "Grant…") {
                    SettingsPermissions.requestAccessibility()
                }
                .buttonStyle(SettingsAtlasValueButtonStyle(tint: SettingsPermissions.accessibilityGranted ? SettingsTheme.success : SettingsTheme.warning))
            }
        }
    }

    @ViewBuilder
    private var appearanceContent: some View {
        section("Theme") {
            row("Appearance", "Follows the system unless overridden", id: "appearance.theme") {
                choice(options: SettingsAtlasAppearance.allCases.map(\.label), selection: Binding(get: { SettingsAtlasAppearance.allCases.firstIndex(of: SettingsAtlasAppearance(rawValue: appearanceRaw) ?? .system) ?? 0 }, set: { appearanceRaw = SettingsAtlasAppearance.allCases[$0].rawValue }))
            }
            row("Accent colour", "Interactive and selected states only", id: "appearance.accent") { swatches(colors: [SettingsTheme.accent, .blue, .green, .purple, .orange], selected: 0) }
            row("Match macOS accent", "Use the system accent instead of Aeroshot's", id: "appearance.system-accent") { value("Off") }
        }
        section("Density & scale") {
            row("Toolbar density", "Height and padding of chrome", id: "appearance.density") { value("Regular") }
            row("Interface scale", "Scales type and controls together", id: "appearance.scale") { value("100%") }
            row("Corner radius", "Applied to cards, panels, and controls", id: "appearance.radius") { value("14 pt") }
        }
        section("Surfaces") {
            row("Panel transparency", "Vibrancy behind floating panels", id: "appearance.transparency") { toggle($reduceTransparency) }
            row("Icon style", "Weight of the custom glyph set", id: "appearance.icons") { value("Outline") }
            row("Editor background", "Behind the canvas in the editor", id: "appearance.editor-background") { value("Match theme") }
        }
        section("Motion") {
            row("Animation intensity", "Amplitude of camera moves and transitions", id: "appearance.motion") { value(reduceMotion ? "System reduced" : "Full") }
            row("Respect system Reduce Motion", "Overrides the setting above when enabled", id: "appearance.respect-motion") { value("On") }
            row("Animate the Atlas camera", "Zoom between map and territory", id: "appearance.atlas-motion") { value(reduceMotion ? "Off" : "On") }
        }
        section("Themes") {
            row("Custom themes", "Saved appearance bundles you can share", id: "appearance.themes") { value("Default · Midnight · Paper") }
            row("Sync appearance across Macs", "Requires an account", id: "appearance.sync") { value("Off") }
        }
    }

    @ViewBuilder
    private var accessibilityContent: some View {
        section("Motion & contrast") {
            row("Reduce motion", "Cross-fades instead of camera moves", id: "access.motion") { value(reduceMotion ? "System enabled" : "System off") }
            row("Increase contrast", "Stronger borders and focus rings", id: "access.contrast") { toggle($increaseContrast) }
            row("Reduce transparency", "Opaque panels instead of vibrancy", id: "access.transparency") { toggle($reduceTransparency) }
            row("Differentiate without colour", "Add shape and text to every state", id: "access.shape") { value("On") }
        }
        section("Colour") {
            row("Colour-blind-safe annotation palette", "Replaces the default swatch set", id: "access.palette") { toggle($safeAnnotationPalette) }
            row("Simulation preview", "Preview the canvas as others see it", id: "access.simulation") { value("Off") }
            row("Label colours by name", "Show the colour name in swatch tooltips", id: "access.labels") { value("On") }
        }
        section("Targets & focus") {
            row("Larger controls", "Minimum 44 pt hit target across the app", id: "access.targets") { value("System") }
            row("Focus ring width", "Applies to every focusable custom control", id: "access.focus") { value("2 pt") }
            row("Always show focus ring", "Even when navigating with the pointer", id: "access.always-focus") { value("Off") }
            row("Cursor size", "Enlarges the pointer in captures and overlays", id: "access.cursor") { value("100%") }
        }
        section("Navigation & speech") {
            row("Keyboard-only navigation", "Every custom control reachable by Tab and arrows", id: "access.keyboard") { value("On") }
            row("VoiceOver descriptions", "Rotor-navigable groups on Atlas and timeline", id: "access.voiceover") { value("On") }
            row("Tooltip delay", "Time before a help tag appears", id: "access.tooltip") { value("600 ms") }
            row("Alternative click indicators", "Non-colour feedback for clicks in recordings", id: "access.clicks") { toggle($settings.highlightClicksDuringRecording) }
        }
    }

    @ViewBuilder
    private var privacyContent: some View {
        section("Redaction") {
            row("Sensitive-information detection", "Emails, tokens, card numbers, and addresses", id: "privacy.detection") { toggle($settings.shareSafeSmartScan) }
            row("Default redaction", "Applied when you accept a suggestion", id: "privacy.redaction") { choice(options: ShareSafeRedactionStyle.allCases.map(\.displayName), selection: Binding(get: { ShareSafeRedactionStyle.allCases.firstIndex(of: settings.shareSafeRedactionStyle) ?? 0 }, set: { settings.shareSafeRedactionStyle = ShareSafeRedactionStyle.allCases[$0] })) }
            row("Redact before sharing", "Never send a flagged original silently", id: "privacy.before-share") { toggle($settings.shareSafeRedactBeforeSharing) }
        }
        section("Permissions") {
            permissionRow("Screen Recording", SettingsPermissions.screenRecordingGranted) { SettingsPermissions.requestScreenRecording() }
            permissionRow("Accessibility", SettingsPermissions.accessibilityGranted) { SettingsPermissions.requestAccessibility() }
            permissionRow("Microphone", SettingsPermissions.microphoneGranted) { Task { _ = await SettingsPermissions.requestMicrophone() } }
            permissionRow("Camera", SettingsPermissions.cameraGranted) { Task { _ = await SettingsPermissions.requestCamera() } }
        }
    }

    @ViewBuilder
    private var advancedContent: some View {
        section("Performance") {
            row("Hardware acceleration", "VideoToolbox for encode and decode", id: "advanced.hardware") { value("Automatic") }
            row("Encoder selection", "Override the automatic choice", id: "advanced.encoder") { value("Automatic") }
            row("Background priority", "CPU share for background renders", id: "advanced.priority") { value("Normal") }
        }
        section("Extensibility") {
            row("Plugins", "Installed extensions", id: "advanced.plugins") { value("None") }
            row("Custom commands", "Appear in the palette and share ring", id: "advanced.commands") { value("None") }
            row("Automation hooks", "Shortcuts and AppleScript triggers", id: "advanced.automation") { EmptyView() }
        }
        section("Configuration") {
            row("Export settings profile", "Share capture preferences with another Mac", id: "advanced.export") {
                Button("Export…") { exportProfile() }
                    .buttonStyle(SettingsAtlasValueButtonStyle(tint: SettingsTheme.accent))
            }
            row("Reset all settings", "Restore Aeroshot preferences and shortcuts", id: "advanced.reset") {
                Button("Reset", role: .destructive) { showResetConfirmation = true }
                    .buttonStyle(SettingsAtlasValueButtonStyle(tint: SettingsTheme.warning))
                    .accessibilityHint("Ask for confirmation before restoring every setting and shortcut")
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        SettingsAtlasSectionCard(title: title) {
            content()
        }
        .id(title)
    }

    @ViewBuilder
    private func row<Control: View>(
        _ title: String,
        _ detail: String,
        id: String,
        @ViewBuilder control: @escaping () -> Control
    ) -> some View {
        SettingsAtlasRow(
            title: title,
            detail: detail,
            id: id,
            isHighlighted: highlightedRowID == id,
            control: control
        )
        .id(id)
        .accessibilityFocused($focusedRowID, equals: id)
    }

    private func toggle(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: binding)
            .labelsHidden()
            .toggleStyle(SettingsAtlasSwitchStyle())
    }

    private func choice(options: [String], selection: Binding<Int>) -> some View {
        SettingsAtlasSegmentedControl(options: options, selection: selection)
    }

    private func slider(value: Binding<Double>, range: ClosedRange<Double>, step: Double, valueText: String) -> some View {
        SettingsAtlasSlider(value: value, range: range, step: step, valueText: valueText)
    }

    private func value(_ text: String, chevron: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(SettingsTheme.typeSmall(weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            if chevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(minWidth: 92, alignment: .leading)
        .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5)
        }
    }

    private func textField(_ binding: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: binding)
            .textFieldStyle(.plain)
            .font(SettingsTheme.typeSmall(weight: .medium, design: .monospaced))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(minWidth: 190, maxWidth: 280)
            .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5)
            }
    }

    private func pathValue(_ path: String, choose: (() -> Void)? = nil) -> some View {
        HStack(spacing: 6) {
            Text(NSString(string: path).abbreviatingWithTildeInPath)
                .font(SettingsTheme.typeSmall(weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let choose {
                Button("Choose…", action: choose)
                    .buttonStyle(SettingsAtlasValueButtonStyle(tint: SettingsTheme.accent))
            }
        }
    }

    private var imageFormatChoice: some View {
        choice(
            options: ImageFormat.allCases.map(\.displayName),
            selection: Binding(
                get: { ImageFormat.allCases.firstIndex(of: settings.imageFormat) ?? 0 },
                set: { settings.imageFormat = ImageFormat.allCases[$0] }
            )
        )
    }

    @ViewBuilder
    private func swatches(colors: [Color], selected: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                Circle()
                    .fill(color)
                    .frame(width: 17, height: 17)
                    .overlay {
                        let strokeColor: Color = index == selected ? .primary : .clear
                        Circle()
                            .strokeBorder(strokeColor, lineWidth: 2)
                            .padding(-3)
                    }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(SettingsTheme.fillRest, in: Capsule())
        .overlay { Capsule().strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5) }
    }

    @ViewBuilder
    private func hotkeySection(_ title: String, actions: [HotkeyAction]) -> some View {
        section(title) {
            ForEach(actions) { action in
                row(action.displayName, "Keyboard shortcut for \(action.displayName.lowercased())", id: "hotkey.\(action.rawValue)") {
                    SettingsAtlasHotkeyControl(
                        action: action,
                        hotkey: Binding(
                            get: { hotkeys[action] ?? action.defaultHotkey },
                            set: { hotkeys[action] = $0 }
                        ),
                        errorMessage: hotkeyErrors[action],
                        onChange: { newHotkey in
                            settings.setHotkey(newHotkey, for: action)
                            hotkeys = settings.hotkeys()
                            hotkeyErrors[action] = nil
                            rebindHotkeys()
                        },
                        onValidationError: { message in
                            if let message {
                                hotkeyErrors[action] = message
                            } else {
                                hotkeyErrors.removeValue(forKey: action)
                            }
                        },
                        onReset: {
                            settings.setHotkey(action.defaultHotkey, for: action)
                            hotkeys = settings.hotkeys()
                            hotkeyErrors[action] = nil
                            rebindHotkeys()
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func permissionRow(_ title: String, _ granted: Bool, action: @escaping () -> Void) -> some View {
        row(title, granted ? "Permission granted" : "Required for this capture workflow", id: "permission.\(title)") {
            Button(granted ? "Granted" : "Grant…", action: action)
                .buttonStyle(SettingsAtlasValueButtonStyle(tint: granted ? SettingsTheme.success : SettingsTheme.warning))
        }
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.saveDirectory
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            settings.saveDirectoryPath = url.path
        }
    }

    private func exportProfile() {
        guard let data = settings.exportProfile() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Aeroshot Profile.json"
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func rebindHotkeys() {
        (NSApp.delegate as? AppDelegate)?.rebindHotkeys()
    }
}

private struct SettingsAtlasControlTitleKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private extension EnvironmentValues {
    var settingsAtlasControlTitle: String? {
        get { self[SettingsAtlasControlTitleKey.self] }
        set { self[SettingsAtlasControlTitleKey.self] = newValue }
    }
}

private struct SettingsAtlasSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Text(title.uppercased())
                    .font(SettingsTheme.typeMicro(weight: .bold, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(SettingsTheme.fillRest)
            .overlay(alignment: .bottom) { Divider() }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
        }
        .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SettingsAtlasRow<Control: View>: View {
    let title: String
    let detail: String
    let id: String
    let isHighlighted: Bool
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 0, alignment: .leading)

            Spacer(minLength: 10)
            control()
                .environment(\.settingsAtlasControlTitle, title)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SettingsTheme.accent.opacity(0.14))
            }
        }
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.atlas.row.\(id)")
    }
}

private struct SettingsAtlasSwitchStyle: ToggleStyle {
    @Environment(\.settingsAtlasControlTitle) private var settingTitle

    func makeBody(configuration: Configuration) -> some View {
        SettingsAtlasSwitchButton(
            isOn: configuration.isOn,
            settingTitle: settingTitle,
            toggle: { configuration.isOn.toggle() }
        )
    }
}

private struct SettingsAtlasSwitchButton: View {
    let isOn: Bool
    let settingTitle: String?
    let toggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    var body: some View {
        Button {
            toggle()
            SettingsTheme.performHaptic()
        } label: {
            HStack(spacing: 0) {
                Circle()
                    .fill(isOn ? AeroTokens.ColorRole.onAccent : AeroTokens.ColorRole.foregroundTertiary)
                    .frame(width: isOn ? 18 : 17, height: isOn ? 18 : 17)
                    .padding(2)
            }
            .frame(width: 40, height: 23, alignment: isOn ? .trailing : .leading)
            .padding(.horizontal, 2)
            .background(
                isOn
                    ? SettingsTheme.accent
                    : (isHovered ? SettingsTheme.fillHover : SettingsTheme.fillRest),
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(
                    isFocused ? SettingsTheme.accent : (isOn ? SettingsTheme.accent : SettingsTheme.borderHover),
                    lineWidth: isFocused ? 1.5 : (isOn ? 0 : 0.5)
                )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(settingTitle ?? "Setting")
        .accessibilityValue(isEnabled ? (isOn ? "On" : "Off") : "Unavailable")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .onHover { hovering in
            SettingsTheme.animateHover(reducedMotion: reduceMotion) {
                isHovered = hovering
            }
        }
    }
}

private struct SettingsAtlasSegmentedControl: View {
    let options: [String]
    @Binding var selection: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.settingsAtlasControlTitle) private var settingTitle
    @State private var hoveredIndex: Int?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let isSelected = selection == index
                Button(option) {
                    withAnimation(SettingsTheme.spring(reducedMotion: reduceMotion)) {
                        selection = index
                    }
                    SettingsTheme.performHaptic()
                }
                .buttonStyle(SettingsAtlasSegmentButtonStyle(isSelected: isSelected, isHovered: hoveredIndex == index))
                .onHover { hovering in
                    SettingsTheme.animateHover(reducedMotion: reduceMotion) {
                        hoveredIndex = hovering ? index : (hoveredIndex == index ? nil : hoveredIndex)
                    }
                }
                .accessibilityLabel("\(settingTitle ?? "Setting"): \(option)")
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(2)
        .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5) }
    }
}

private struct SettingsAtlasSegmentButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isHovered: Bool

    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? AeroTokens.ColorRole.onAccent : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                isSelected
                    ? SettingsTheme.accent
                    : (configuration.isPressed ? SettingsTheme.fillPressed : (isHovered ? SettingsTheme.fillHover : .clear)),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isFocused ? SettingsTheme.accent : .clear, lineWidth: isFocused ? 1 : 0)
            }
            .lineLimit(1)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct SettingsAtlasSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.settingsAtlasControlTitle) private var settingTitle

    var body: some View {
        HStack(spacing: 9) {
            Slider(value: $value, in: range, step: step)
                .tint(SettingsTheme.accent)
                .frame(width: 150)
                .accessibilityLabel(settingTitle ?? "Setting")
                .accessibilityValue(valueText)
                .accessibilityHint("Adjust \(settingTitle ?? "this setting")")
            Text(valueText)
                .font(SettingsTheme.typeSmall(weight: .semibold, design: .monospaced))
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .frame(minWidth: 54, alignment: .trailing)
        }
        .opacity(isEnabled ? 1 : 0.55)
        .contentShape(Rectangle())
    }
}

private struct SettingsAtlasValueButtonStyle: ButtonStyle {
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        SettingsAtlasValueButtonLabel(
            label: configuration.label,
            tint: tint,
            isPressed: configuration.isPressed,
            reduceMotion: reduceMotion
        )
    }
}

private struct SettingsAtlasValueButtonLabel<Label: View>: View {
    let label: Label
    let tint: Color
    let isPressed: Bool
    let reduceMotion: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    var body: some View {
        label
            .font(SettingsTheme.typeSmall(weight: .semibold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                tint.opacity(isPressed ? 0.2 : (isHovered ? 0.17 : 0.12)),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isFocused ? SettingsTheme.accent : tint.opacity(0.32),
                        lineWidth: isFocused ? 1.5 : 0.5
                    )
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(isPressed && !reduceMotion ? 0.98 : 1)
            .animation(SettingsTheme.spring(reducedMotion: reduceMotion), value: isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { isHovered = $0 }
    }
}

struct SettingsAtlasIndexButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        SettingsAtlasIndexButtonLabel(
            label: configuration.label,
            isPressed: configuration.isPressed,
            reduceMotion: reduceMotion
        )
    }
}

private struct SettingsAtlasIndexButtonLabel<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let reduceMotion: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    var body: some View {
        label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isPressed || isHovered ? SettingsTheme.accent : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isPressed ? SettingsTheme.fillPressed : (isHovered ? SettingsTheme.fillHover : SettingsTheme.fillRest), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isFocused ? SettingsTheme.accent : SettingsTheme.borderSubtle, lineWidth: isFocused ? 1.5 : 0.5)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(isPressed && !reduceMotion ? 0.98 : 1)
            .animation(SettingsTheme.spring(reducedMotion: reduceMotion), value: isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onHover { isHovered = $0 }
    }
}

private struct SettingsAtlasHotkeyControl: View {
    let action: HotkeyAction
    @Binding var hotkey: Hotkey
    let errorMessage: String?
    let onChange: (Hotkey) -> Void
    let onValidationError: (String?) -> Void
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onReset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(SettingsAtlasValueButtonStyle(tint: AeroTokens.ColorRole.foregroundTertiary))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .accessibilityLabel("Reset \(action.displayName) shortcut")
            .accessibilityHint("Restore the default shortcut")
            .help("Reset to default")

            HotkeyRecorderView(
                action: action,
                hotkey: $hotkey,
                validationMessage: { _ in nil },
                onChange: onChange,
                onValidationError: onValidationError
            )
            .frame(width: 120, height: 24)
            .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(errorMessage == nil ? SettingsTheme.borderSubtle : SettingsTheme.warning, lineWidth: 0.5) }
        }
    }
}
