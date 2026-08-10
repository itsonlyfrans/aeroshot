import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsAtlasWindow: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("settingsAtlasAppearance") private var appearanceRaw = SettingsAtlasAppearance.dark.rawValue
    @State private var selectedAppearance: SettingsAtlasAppearance = .dark
    @State private var route: SettingsAtlasRoute = .atlas
    @State private var palettePresented = false
    @State private var paletteQuery = ""
    @State private var paletteSelection = 0
    @State private var highlightedRowID: String?

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                SettingsAtlasTopBar(
                    route: $route,
                    appearance: $selectedAppearance,
                    openPalette: openPalette
                )

                content

                HStack(spacing: 12) {
                    Button {
                        route = .category(.privacy)
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(SettingsTheme.warning).frame(width: 5, height: 5)
                            Text(SettingsPermissions.allGranted ? "READY TO CAPTURE" : "SET UP PERMISSIONS…")
                        }
                        .font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced))
                        .foregroundStyle(SettingsTheme.warning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(SettingsTheme.warning.opacity(0.13), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(SettingsPermissions.allGranted ? "Ready to capture" : "Set up permissions…")

                    Spacer(minLength: 0)
                    Text("18 settings differ from defaults · profile “\(settings.activeCaptureProfile.name)”")
                        .font(SettingsTheme.typeMicro(weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    Button("IMPORT…") { importProfile() }
                        .buttonStyle(.plain)
                    Button("EXPORT PROFILE") { exportProfile() }
                        .buttonStyle(.plain)
                    Divider().frame(height: 14)
                    Button("⌘0 ATLAS") { route = .atlas }
                        .buttonStyle(.plain)
                }
                .font(SettingsTheme.typeMicro(weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(SettingsTheme.fillRest)
                .overlay(alignment: .top) { Divider() }
            }

            if palettePresented {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .onTapGesture { closePalette() }

                SettingsAtlasPalette(
                    query: $paletteQuery,
                    results: paletteItems,
                    selectedIndex: $paletteSelection,
                    onSelect: openPaletteItem,
                    onToggle: togglePaletteItem
                )
                .padding(.top, 68)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -8)))
            }
        }
        .background(SettingsAtlasBackground())
        .preferredColorScheme(selectedAppearance.colorScheme)
        .onExitCommand {
            if palettePresented {
                closePalette()
            } else if route != .atlas {
                route = .atlas
            }
        }
        .background { keyboardCommands }
        .animation(SettingsTheme.spring(reducedMotion: reduceMotion), value: palettePresented)
        .animation(SettingsTheme.spring(reducedMotion: reduceMotion), value: route)
        .onAppear {
            let stored = SettingsAtlasAppearance(rawValue: appearanceRaw) ?? .dark
            selectedAppearance = stored == .system ? .dark : stored
        }
        .onChange(of: selectedAppearance) { _, newValue in
            appearanceRaw = newValue.rawValue
        }
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .atlas:
            atlasHome
        case let .category(id):
            categoryDetail(SettingsAtlasCategory.category(for: id))
        }
    }

    private var atlasHome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .bottom, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Everything Aeroshot can do, on one map.")
                            .font(.system(size: 26, weight: .semibold))
                            .tracking(-0.4)
                Text("Four bands follow the shape of the work: what you capture, how you shape it, where it goes, and the rules underneath. Zoom into any territory — nothing is more than two moves away.")
                            .font(.system(size: 13.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 600, alignment: .leading)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 9) {
                        HStack(spacing: 8) {
                            SettingsAtlasMetricCard(
                                value: "18",
                                label: "changed",
                                symbol: "circle.fill",
                                tint: SettingsTheme.accent
                            )
                            SettingsAtlasMetricCard(
                                value: SettingsPermissions.healthLabel,
                                label: "permissions",
                                symbol: SettingsPermissions.allGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                                tint: SettingsPermissions.allGranted ? SettingsTheme.success : SettingsTheme.warning
                            )
                        }
                    }
                    .frame(maxWidth: 330)
                }

                ForEach(SettingsAtlasBand.allCases) { band in
                    HStack(alignment: .top, spacing: 18) {
                        SettingsAtlasBandHeader(band: band)

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 11), count: 4),
                            spacing: 11
                        ) {
                            ForEach(SettingsAtlasCategory.categories(in: band)) { category in
                                SettingsAtlasCategoryCard(category: category) {
                                    open(category)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 34)
            .padding(.bottom, 40)
            .frame(maxWidth: 1440, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(SettingsAtlasDotGrid())
        .accessibilityIdentifier("settings.atlas.home")
    }

    private func categoryDetail(_ category: SettingsAtlasCategory) -> some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 9) {
                            Text(category.band.title)
                                .font(SettingsTheme.typeMicro(weight: .bold, design: .monospaced))
                                .tracking(1.2)
                                .foregroundStyle(SettingsTheme.accent)
                            Circle().fill(.tertiary).frame(width: 3, height: 3)
                        }

                        Text(category.name)
                            .font(.system(size: 23, weight: .semibold))
                            .tracking(-0.4)

                        Text(category.intro)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 620, alignment: .leading)
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 7) {
                        AtlasNavigationButton(title: previousCategoryName(category), symbol: "arrow.left") {
                            open(previousCategory(category))
                        }
                        AtlasNavigationButton(title: nextCategoryName(category), symbol: "arrow.right", trailingSymbol: true) {
                            open(nextCategory(category))
                        }
                        Button("⌘0 Atlas") { route = .atlas }
                            .buttonStyle(AtlasAccentButtonStyle())
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(SettingsAtlasTerritoryView.sectionTitles(for: category.id), id: \.self) { title in
                            Button(title) {
                                withAnimation(SettingsTheme.spring(reducedMotion: reduceMotion)) {
                                    proxy.scrollTo(title, anchor: .top)
                                }
                            }
                            .buttonStyle(SettingsAtlasIndexButtonStyle())
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 18)
                    .padding(.bottom, 11)
                }
                .background(SettingsAtlasBackground())
                .overlay(alignment: .bottom) { Divider() }

                HStack(alignment: .top, spacing: 0) {
                    SettingsAtlasTerritoryView(category: category.id, highlightedRowID: $highlightedRowID)
                        .environmentObject(settings)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    SettingsAtlasPreviewGutter(category: category, open: { id in
                        open(SettingsAtlasCategory.category(for: id))
                    })
                    .environmentObject(settings)
                    .frame(width: 336)
                }
                .frame(maxHeight: .infinity)
            }
            .background(SettingsAtlasBackground())
        }
        .accessibilityIdentifier("settings.atlas.category.\(category.id.rawValue)")
    }

    private var paletteItems: [SettingsAtlasPaletteItem] {
        let query = paletteQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let categories = SettingsAtlasCategory.all.compactMap { category -> SettingsAtlasPaletteItem? in
            guard query.isEmpty || [category.name, category.blurb, category.band.title, category.chips.joined(separator: " ")].joined(separator: " ").lowercased().contains(query) else { return nil }
            return SettingsAtlasPaletteItem(
                id: "category.\(category.id.rawValue)",
                title: category.name,
                detail: "\(category.band.title.capitalized) · \(category.blurb)",
                symbol: category.symbol,
                categoryID: category.id,
                value: category.liveChips(settings: settings).first,
                isToggleable: false
            )
        }

        let settingsItems = SettingsSearchEntry.results(for: paletteQuery).compactMap { entry -> SettingsAtlasPaletteItem? in
            guard let destination = entry.atlasDestination,
                  let detail = entry.atlasResultDetail
            else { return nil }
            return SettingsAtlasPaletteItem(
                id: "setting.\(entry.id)",
                title: entry.title,
                detail: detail,
                symbol: entry.pane.symbol,
                categoryID: destination.categoryID,
                value: value(for: entry.id),
                isToggleable: canToggle(entry.id)
            )
        }

        return Array((query.isEmpty ? settingsItems : categories + settingsItems).prefix(24))
    }

    private func openPalette() {
        palettePresented = true
        paletteQuery = ""
        paletteSelection = 0
    }

    private func closePalette() {
        palettePresented = false
        paletteQuery = ""
        paletteSelection = 0
    }

    private func openPaletteItem(_ item: SettingsAtlasPaletteItem) {
        if item.id.hasPrefix("setting."),
           let entry = SettingsSearchEntry.catalog.first(where: { item.id == "setting.\($0.id)" }),
           let destination = entry.atlasDestination {
            route = .category(destination.categoryID)
            highlightedRowID = destination.rowID
        } else {
            route = .category(item.categoryID)
            highlightedRowID = nil
        }
        closePalette()
        SettingsTheme.performHaptic()
    }

    private func togglePaletteItem(_ item: SettingsAtlasPaletteItem) {
        guard item.isToggleable, item.id.hasPrefix("setting.") else { return }
        toggle(entryID: String(item.id.dropFirst("setting.".count)))
        SettingsTheme.performHaptic()
    }

    private func canToggle(_ id: String) -> Bool {
        [
            "clipboard", "save-disk", "thumbnail", "sound", "editor-open",
            "system-audio", "microphone", "webcam-overlay", "click-highlight",
            "menu-bar-presence", "dock-presence", "ocr-history"
        ].contains(id)
    }

    private func value(for id: String) -> String? {
        switch id {
        case "clipboard": settings.copyToClipboardAfterCapture ? "On" : "Off"
        case "save-disk": settings.saveToDiskAfterCapture ? "On" : "Off"
        case "thumbnail": settings.showThumbnailAfterCapture ? "On" : "Off"
        case "sound": settings.playCaptureSound ? "On" : "Off"
        case "editor-open": settings.openEditorAfterCapture ? "On" : "Off"
        case "system-audio": settings.recordSystemAudio ? "On" : "Off"
        case "microphone": settings.recordMicrophone ? "On" : "Off"
        case "webcam-overlay": settings.showWebcamOverlay ? "On" : "Off"
        case "click-highlight": settings.highlightClicksDuringRecording ? "On" : "Off"
        case "menu-bar-presence": settings.showInMenuBar ? "On" : "Off"
        case "dock-presence": settings.showInDock ? "On" : "Off"
        case "ocr-history": settings.addOCRCapturesToHistory ? "On" : "Off"
        case "capture-delay": settings.captureDelaySeconds == 0 ? "Off" : "\(settings.captureDelaySeconds)s"
        case "format": settings.imageFormat.displayName
        case "recording-format": settings.recordingFormat.displayName
        case "save-folder": settings.saveDirectory.lastPathComponent
        default: nil
        }
    }

    private func toggle(entryID: String) {
        switch entryID {
        case "clipboard": settings.copyToClipboardAfterCapture.toggle()
        case "save-disk": settings.saveToDiskAfterCapture.toggle()
        case "thumbnail": settings.showThumbnailAfterCapture.toggle()
        case "sound": settings.playCaptureSound.toggle()
        case "editor-open": settings.openEditorAfterCapture.toggle()
        case "system-audio": settings.recordSystemAudio.toggle()
        case "microphone": settings.recordMicrophone.toggle()
        case "webcam-overlay": settings.showWebcamOverlay.toggle()
        case "click-highlight": settings.highlightClicksDuringRecording.toggle()
        case "menu-bar-presence": settings.showInMenuBar.toggle()
        case "dock-presence": settings.showInDock.toggle()
        case "ocr-history": settings.addOCRCapturesToHistory.toggle()
        default: break
        }
    }

    private func open(_ category: SettingsAtlasCategory) {
        route = .category(category.id)
        SettingsTheme.performHaptic()
    }

    private func previousCategory(_ category: SettingsAtlasCategory) -> SettingsAtlasCategory {
        let all = SettingsAtlasCategory.all
        guard let index = all.firstIndex(where: { $0.id == category.id }) else { return all[0] }
        return all[(index - 1 + all.count) % all.count]
    }

    private func nextCategory(_ category: SettingsAtlasCategory) -> SettingsAtlasCategory {
        let all = SettingsAtlasCategory.all
        guard let index = all.firstIndex(where: { $0.id == category.id }) else { return all[0] }
        return all[(index + 1) % all.count]
    }

    private func previousCategoryName(_ category: SettingsAtlasCategory) -> String {
        previousCategory(category).name
    }

    private func nextCategoryName(_ category: SettingsAtlasCategory) -> String {
        nextCategory(category).name
    }

    @ViewBuilder
    private var keyboardCommands: some View {
        Group {
            Button("") { openPalette() }
                .keyboardShortcut("k", modifiers: .command)
            Button("") { route = .atlas }
                .keyboardShortcut("0", modifiers: .command)
        }
        .hidden()
        .frame(width: 0, height: 0)
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

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
            try? settings.importProfile(from: data)
        }
    }
}

private struct SettingsAtlasDotGrid: View {
    var body: some View {
        Canvas { context, size in
            for x in stride(from: CGFloat(1), through: size.width, by: 16) {
                for y in stride(from: CGFloat(1), through: size.height, by: 16) {
                    let dot = Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5))
                    context.fill(dot, with: .color(SettingsTheme.borderSubtle.opacity(0.8)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct SettingsAtlasBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Rectangle()
                .fill(
                    RadialGradient(
                        colors: [SettingsTheme.accent.opacity(0.045), .clear],
                        center: .topLeading,
                        startRadius: 20,
                        endRadius: 680
                    )
                )
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

private struct AtlasNavigationButtonStyle: ButtonStyle {
    let trailingSymbol: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(configuration.isPressed ? SettingsTheme.accent : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? SettingsTheme.fillPressed : SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isFocused ? SettingsTheme.accent : SettingsTheme.borderSubtle, lineWidth: isFocused ? 1.5 : 0.5)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(SettingsTheme.spring(reducedMotion: reduceMotion), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AtlasAccentButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(configuration.isPressed ? SettingsTheme.accent : SettingsTheme.accent)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                configuration.isPressed ? SettingsTheme.fillPressed : SettingsTheme.accent.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isFocused ? SettingsTheme.accent : .clear, lineWidth: isFocused ? 1.5 : 0)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(SettingsTheme.spring(reducedMotion: reduceMotion), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AtlasNavigationButton: View {
    let title: String
    let symbol: String
    var trailingSymbol = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if !trailingSymbol {
                    Image(systemName: symbol)
                }
                Text(title)
                if trailingSymbol {
                    Image(systemName: symbol)
                }
            }
        }
        .buttonStyle(AtlasNavigationButtonStyle(trailingSymbol: trailingSymbol))
    }
}
