import AppKit
import SwiftUI

struct AtlasAppSurface: View {
    let appState: AppState
    let select: (AtlasWorkbenchSurface) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero

                AtlasMockupCanvas(title: "Aeroshot", status: "READY · \(SettingsPermissions.healthLabel)") {
                    ZStack(alignment: .topLeading) {
                        AtlasMockupWindow(title: "HistoryStore.swift") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach([0.58, 0.41, 0.72, 0.35, 0.64, 0.49, 0.68, 0.28, 0.55], id: \.self) { width in
                                    Capsule().fill(.white.opacity(width == 0.41 ? 0.18 : 0.08)).frame(width: 270 * width, height: 7)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(18)
                        }
                        .frame(width: 430, height: 255)
                        .padding(.leading, 58)
                        .padding(.top, 54)

                        AtlasMockupWindow(title: "Captures") {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 7) {
                                ForEach(0..<8, id: \.self) { index in
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(index == 0 ? SettingsTheme.accent.opacity(0.26) : .white.opacity(0.07))
                                        .aspectRatio(1, contentMode: .fit)
                                }
                            }
                            .padding(13)
                        }
                        .frame(width: 205, height: 164)
                        .padding(.leading, 560)
                        .padding(.top, 38)
                    }
                }

                HStack(spacing: 10) {
                    AtlasWorkbenchStat(value: "\(appState.history.items.count)", label: "library items")
                    AtlasWorkbenchStat(value: SettingsPermissions.healthLabel, label: "permission health", tint: SettingsPermissions.allGranted ? SettingsTheme.success : SettingsTheme.warning)
                    AtlasWorkbenchStat(value: appState.settings.activeCaptureProfile.name, label: "active profile", tint: AeroTokens.ColorRole.information)
                }

                AtlasWorkbenchSectionHeader(title: "CAPTURE", detail: "the fastest path to a useful frame")
                captureGrid

                AtlasWorkbenchSectionHeader(title: "OPEN SURFACES", detail: "every prototype is wired to the live app")
                surfaceGrid

                recentItems
            }
            .padding(28)
            .frame(maxWidth: 1_060, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .accessibilityIdentifier("atlas.surface.app")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            AtlasWorkbenchTag(text: "CAPTURE · EDIT · DELIVER", color: SettingsTheme.accent)
            Text("A capture system that keeps the frame intact.")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .tracking(-0.8)
                .fixedSize(horizontal: false, vertical: true)
            Text("Choose an intent, keep the original safe, and move through the same reversible stack from selection to export.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 590, alignment: .leading)
        }
    }

    private var captureGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            AtlasCaptureAction(title: "Capture area", symbol: "rectangle.dashed", shortcut: "⇧⌘4") {
                appState.captureController.beginAreaCapture()
            }
            AtlasCaptureAction(title: "Capture window", symbol: "macwindow", shortcut: "⇧⌘5") {
                appState.captureController.beginWindowCapture()
            }
            AtlasCaptureAction(title: "Capture screen", symbol: "display", shortcut: "⇧⌘3") {
                appState.captureController.captureFullScreen()
            }
            AtlasCaptureAction(title: "Scrolling capture", symbol: "arrow.down.to.line", shortcut: "⇧⌘7") {
                appState.scrollingCaptureController.begin()
            }
            AtlasCaptureAction(title: "Capture text", symbol: "text.viewfinder", shortcut: "⇧⌘8") {
                appState.ocrCaptureController.begin()
            }
            AtlasCaptureAction(title: "Record screen", symbol: "record.circle", shortcut: "⇧⌘9", tint: AeroTokens.ColorRole.danger) {
                appState.recordingController.beginScreenRecording()
            }
        }
    }

    private var surfaceGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            AtlasSurfaceAction(surface: .tray, action: { select(.tray) })
            AtlasSurfaceAction(surface: .selection, action: { select(.selection) })
            AtlasSurfaceAction(surface: .editor, action: { select(.editor) })
            AtlasSurfaceAction(surface: .gifStudio, action: { select(.gifStudio) })
            AtlasSurfaceAction(surface: .mediaStudio, action: { select(.mediaStudio) })
            AtlasSurfaceAction(surface: .studio, action: { select(.studio) })
            AtlasSurfaceAction(surface: .menuBar, action: { select(.menuBar) })
            AtlasSurfaceAction(surface: .onboarding, action: { select(.onboarding) })
            AtlasSurfaceAction(surface: .settings, action: { select(.settings) })
        }
    }

    private var recentItems: some View {
        AtlasWorkbenchPanel(title: "Recent library", subtitle: "real HistoryStore state", symbol: "clock.arrow.circlepath") {
            if appState.history.items.isEmpty {
                Text("No captures yet. Start with Capture area above.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.history.items.prefix(5)) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.kind.atlasSymbol)
                            .foregroundStyle(SettingsTheme.accent)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.fileName.isEmpty ? item.kind.rawValue.capitalized : item.fileName)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Text(item.atlasDetail)
                                .font(SettingsTheme.typeMicro(design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                        Text(item.createdAt, style: .time)
                            .font(SettingsTheme.typeMicro(design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

private struct AtlasCaptureAction: View {
    let title: String
    let symbol: String
    let shortcut: String
    var tint: Color = SettingsTheme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(shortcut)
                        .font(SettingsTheme.typeMicro(design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(SettingsTheme.borderSubtle, lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct AtlasSurfaceAction: View {
    let surface: AtlasWorkbenchSurface
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: surface.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SettingsTheme.accent)
                Text(surface.title)
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(surface.title)")
    }
}

struct AtlasOnboardingSurface: View {
    let appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AtlasWorkbenchTag(text: "PROVE IT · DO NOT PROMISE IT", color: SettingsTheme.accent)
                AtlasMockupCanvas(title: "Onboarding", status: "SETUP · STEP 1 OF 4", menuItems: ["File", "Window", "Help"]) {
                    AtlasMockupWindow(title: "Aeroshot setup") {
                        OnboardingView(startStep: .welcome) {
                            appState.settings.hasCompletedOnboarding = true
                        }
                        .environmentObject(appState.settings)
                        .scaleEffect(0.64)
                        .frame(width: 358, height: 333)
                    }
                    .frame(width: 590, height: 404)
                }
                .frame(height: 470)
            }
            .padding(28)
            .frame(maxWidth: 1_060, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .accessibilityIdentifier("atlas.surface.onboarding")
    }
}

struct AtlasTraySurface: View {
    let appState: AppState
    @EnvironmentObject private var history: HistoryStore
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var selectedKind: HistoryCaptureKind?

    private var items: [HistoryItem] {
        var result = history.search(query, filter: .init(favoritesOnly: favoritesOnly), sort: .newest)
        if let selectedKind { result = result.filter { $0.kind == selectedKind } }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            trayStage

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search file names, tags, OCR…", text: $query)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("atlas.tray.search")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Divider().frame(height: 20)
                Button { favoritesOnly.toggle() } label: {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                        .foregroundStyle(favoritesOnly ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(favoritesOnly ? "Showing favorites" : "Show favorites")
            }
            .padding(10)
            .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 22)
            .padding(.vertical, 16)

            HStack(spacing: 6) {
                AtlasTrayFilter(title: "All", selected: selectedKind == nil) { selectedKind = nil }
                ForEach(HistoryCaptureKind.allCases, id: \.self) { kind in
                    AtlasTrayFilter(title: kind.rawValue.uppercased(), selected: selectedKind == kind) { selectedKind = kind }
                }
                Spacer(minLength: 0)
                Text("\(items.count) ITEMS")
                    .font(SettingsTheme.typeMicro(weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 10)

            Divider()

            if items.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: query.isEmpty ? "tray" : "magnifyingglass")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(query.isEmpty ? "Your capture tray is empty" : "Nothing matches \(query)")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Capture something and it will land here with its source, tags, checksum, and OCR text intact.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                    AtlasWorkbenchActionButton(title: "Capture area", symbol: "rectangle.dashed", kind: .primary) {
                        appState.captureController.beginAreaCapture()
                    }
                    .frame(width: 160)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(items) { item in
                            AtlasTrayRow(item: item, appState: appState)
                        }
                    }
                    .padding(22)
                }
            }
        }
        .accessibilityIdentifier("atlas.surface.tray")
    }

    private var trayStage: some View {
        AtlasMockupCanvas(title: "Capture Tray", status: "\(items.count) ITEMS · STACK READY") {
            ZStack(alignment: .bottom) {
                AtlasMockupWindow(title: "HistoryStore.swift") {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach([0.58, 0.41, 0.72, 0.35, 0.64, 0.49, 0.68], id: \.self) { width in
                            Capsule().fill(.white.opacity(width == 0.41 ? 0.20 : 0.08)).frame(width: 320 * width, height: 7)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(18)
                }
                .frame(width: 440, height: 235)
                .padding(.leading, 54)
                .padding(.bottom, 58)

                HStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(index == 0 ? SettingsTheme.accent.opacity(0.78) : .white.opacity(0.15))
                            .frame(width: 74, height: 48)
                            .overlay(alignment: .bottomLeading) {
                                Text(index == 0 ? "IMG 1880×1184" : index == 1 ? "TXT OCR" : "REC 00:42")
                                    .font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .padding(5)
                            }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SHARESAFE SCAN")
                            .font(SettingsTheme.typeMicro(weight: .bold, design: .monospaced))
                            .foregroundStyle(AeroTokens.ColorRole.warning)
                        Text("hover rail · click to open tray")
                            .font(SettingsTheme.typeMicro())
                            .foregroundStyle(.white.opacity(0.48))
                    }
                    .padding(.leading, 5)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.40), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .frame(height: 315)
        .padding(.horizontal, 22)
        .padding(.top, 18)
    }
}

private struct AtlasTrayFilter: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(SettingsTheme.typeMicro(weight: .bold, design: .monospaced))
            .foregroundStyle(selected ? AeroTokens.ColorRole.onAccent : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(selected ? SettingsTheme.accent : SettingsTheme.fillRest, in: Capsule())
            .buttonStyle(.plain)
    }
}

private struct AtlasTrayRow: View {
    let item: HistoryItem
    let appState: AppState
    @EnvironmentObject private var history: HistoryStore

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(SettingsTheme.accent.opacity(0.10))
                if item.kind == .image, let url = history.fileURL(for: item) as URL?, let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                } else {
                    Image(systemName: item.kind.atlasSymbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SettingsTheme.accent)
                }
            }
            .frame(width: 60, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(item.fileName.isEmpty ? item.kind.rawValue.capitalized : item.fileName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    AtlasWorkbenchTag(text: item.kind.rawValue.uppercased(), color: item.kind.atlasColor)
                    if item.isFavorite { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow) }
                }
                Text(item.atlasDetail)
                    .font(SettingsTheme.typeMicro(design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !item.tags.isEmpty {
                    Text(item.tags.map { "#\($0)" }.joined(separator: "  "))
                        .font(SettingsTheme.typeMicro(design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 5) {
                Text(item.createdAt, style: .time)
                    .font(SettingsTheme.typeMicro(design: .monospaced))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 4) {
                    Button { open() } label: { Image(systemName: "arrow.up.right") }
                    Button { history.toggleFavorite(item) } label: { Image(systemName: item.isFavorite ? "star.fill" : "star") }
                    Button(role: .destructive) { _ = history.remove(item) } label: { Image(systemName: "trash") }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SettingsTheme.borderSubtle, lineWidth: 0.7)
        }
        .contextMenu {
            Button(item.isFavorite ? "Remove from Favorites" : "Add to Favorites") { history.toggleFavorite(item) }
            Button("Open") { open() }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([history.fileURL(for: item)]) }
            Divider()
            Button("Delete", role: .destructive) { _ = history.remove(item) }
        }
    }

    private func open() {
        guard let url = history.primaryURL(for: item) else { return }
        history.markOpened(item)
        if item.kind == .image, let image = NSImage(contentsOf: url)?.cgImageForAtlas {
            appState.openEditor(with: image)
        } else if item.kind == .gif {
            try? ProjectWindowRouter.openGIF(at: url)
        } else if item.kind == .project {
            _ = try? ProjectWindowRouter.openProject(at: url, appState: appState)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

struct AtlasSelectionSurface: View {
    let appState: AppState
    @State private var selectedIntent: AtlasSelectionIntent = .area
    @State private var aspect = "Free"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        AtlasWorkbenchTag(text: "V1 · DRAG TO SELECT", color: SettingsTheme.accent)
                        Text("Select the bit that matters.")
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                        Text("The overlay keeps the rest of the screen quiet while intent, ratio, and handoff stay one keypress away.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 520, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                    AtlasWorkbenchPill(text: "LIVE OVERLAY", color: SettingsTheme.success, symbol: "viewfinder")
                }

                selectionStage

                AtlasWorkbenchPanel(title: "Intent", subtitle: "choose what the overlay should do", symbol: "scope") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                        ForEach(AtlasSelectionIntent.allCases) { intent in
                            Button {
                                selectedIntent = intent
                                SettingsTheme.performHaptic()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: intent.symbol)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(intent.title)
                                            .font(.system(size: 12, weight: .semibold))
                                        Text(intent.shortcut)
                                            .font(SettingsTheme.typeMicro(design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(selectedIntent == intent ? AeroTokens.ColorRole.onAccent : .primary)
                                .padding(10)
                                .background(selectedIntent == intent ? SettingsTheme.accent : SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 14) {
                    AtlasWorkbenchPanel(title: "Selection rail", subtitle: "what the live overlay exposes", symbol: "rectangle.dashed") {
                        VStack(alignment: .leading, spacing: 11) {
                            AtlasSelectionRailRow(symbol: "viewfinder", title: "Window snap", detail: "Hover a window to retain its exact frame")
                            AtlasSelectionRailRow(symbol: "ruler", title: "Dimensions", detail: "1,880 × 1,184 · 2× Retina")
                            AtlasSelectionRailRow(symbol: "text.viewfinder", title: "ShareSafe", detail: "Sensitive regions stay reviewable before handoff")
                            AtlasSelectionRailRow(symbol: "keyboard", title: "Keyboard first", detail: "Arrows nudge · Return commits · Esc cancels")
                        }
                    }

                    AtlasWorkbenchPanel(title: "Ratio", subtitle: "lock the frame without leaving selection", symbol: "aspectratio") {
                        VStack(spacing: 8) {
                            ForEach(["Free", "16:9", "4:3", "1:1", "3:2"], id: \.self) { value in
                                Button {
                                    aspect = value
                                } label: {
                                    HStack {
                                        Text(value)
                                        Spacer()
                                        if aspect == value { Image(systemName: "checkmark") }
                                    }
                                    .font(.system(size: 12, weight: aspect == value ? .semibold : .regular))
                                    .foregroundStyle(aspect == value ? SettingsTheme.accent : .secondary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 7)
                                    .background(aspect == value ? SettingsTheme.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                AtlasWorkbenchPanel(title: "Run this intent", subtitle: "the button routes to the same production capture controller", symbol: "play.fill") {
                    HStack(spacing: 10) {
                        AtlasWorkbenchActionButton(title: selectedIntent.title, symbol: selectedIntent.symbol, kind: .primary) {
                            selectedIntent.run(appState)
                        }
                        AtlasWorkbenchActionButton(title: "Open tray", symbol: "tray.full") {
                            appState.showHistoryWindow()
                        }
                        Spacer(minLength: 0)
                        Text("\(selectedIntent.shortcut)  ·  \(aspect)  ·  ShareSafe ready")
                            .font(SettingsTheme.typeMicro(design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1_060, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .accessibilityIdentifier("atlas.surface.selection")
    }

    private var selectionStage: some View {
        AtlasMockupCanvas(title: "Selection Surface", status: "100% · SAT 12:41", menuItems: ["File", "Capture", "Edit", "Window", "Help"]) {
            ZStack {
                AtlasMockupWindow(title: "SelectionOverlayView.swift") {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach([0.62, 0.44, 0.74, 0.38, 0.66, 0.52, 0.70, 0.30, 0.58, 0.46, 0.64], id: \.self) { width in
                            Capsule().fill(.white.opacity(width == 0.44 ? 0.19 : 0.08)).frame(width: 360 * width, height: 7)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(17)
                }
                .frame(width: 385, height: 250)
                .padding(.leading, 48)
                .padding(.top, 46)

                AtlasMockupWindow(title: "Captures") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                        ForEach(0..<8, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(.white.opacity(index < 4 ? 0.09 : 0.05))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                    .padding(11)
                }
                .frame(width: 208, height: 150)
                .padding(.leading, 560)
                .padding(.top, 26)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(SettingsTheme.accent, lineWidth: 1.5)
                    .frame(width: 350, height: 178)
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 7) {
                            Text("1880 × 1184")
                                .font(SettingsTheme.typeMicro(weight: .bold, design: .monospaced))
                                .foregroundStyle(AeroTokens.ColorRole.onAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(SettingsTheme.accent, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            Text("Window snap")
                                .font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.68))
                        }
                        .offset(x: -1, y: -29)
                    }
                    .overlay {
                        Image(systemName: "scope")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(SettingsTheme.accent.opacity(0.9))
                    }
            }
        }
        .frame(height: 330)
    }
}

private enum AtlasSelectionIntent: String, CaseIterable, Identifiable {
    case area, window, screen, scrolling, record, text

    var id: String { rawValue }
    var title: String {
        switch self {
        case .area: "Area capture"
        case .window: "Window snap"
        case .screen: "Full screen"
        case .scrolling: "Scroll capture"
        case .record: "Record"
        case .text: "Text / OCR"
        }
    }
    var symbol: String {
        switch self {
        case .area: "rectangle.dashed"
        case .window: "macwindow"
        case .screen: "display"
        case .scrolling: "arrow.down.to.line"
        case .record: "record.circle"
        case .text: "text.viewfinder"
        }
    }
    var shortcut: String {
        switch self {
        case .area: "⌥⌘1"
        case .window: "⌥⌘2"
        case .screen: "⌥⌘3"
        case .scrolling: "⌥⌘4"
        case .record: "⌥⌘5"
        case .text: "⌥⌘6"
        }
    }
    func run(_ appState: AppState) {
        switch self {
        case .area: appState.captureController.beginAreaCapture()
        case .window: appState.captureController.beginWindowCapture()
        case .screen: appState.captureController.captureFullScreen()
        case .scrolling: appState.scrollingCaptureController.begin()
        case .record: appState.recordingController.beginScreenRecording()
        case .text: appState.ocrCaptureController.begin()
        }
    }
}

private struct AtlasSelectionRailRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(SettingsTheme.accent)
                .frame(width: 19)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(SettingsTheme.typeMicro()).foregroundStyle(.tertiary)
            }
        }
    }
}

struct AtlasEditorSurface: View {
    let appState: AppState
    @EnvironmentObject private var history: HistoryStore

    private var imageItems: [HistoryItem] {
        history.items.filter { $0.kind == .image && history.primaryURL(for: $0) != nil }.prefix(8).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                AtlasWorkbenchPanel(title: "Editor stack", subtitle: "every move stays reversible", symbol: "pencil.and.outline") {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 9) {
                            AtlasWorkbenchTag(text: "BASE CAPTURE · NEVER REWRITTEN", color: SettingsTheme.success)
                            Text("Mark up the frame, then hand it to a recipe.")
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                            Text("The production editor opens from any image in the tray. The Atlas chrome keeps the tool stack and privacy state visible without flattening the source.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: 500, alignment: .leading)
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .leading, spacing: 9) {
                            AtlasWorkbenchStat(value: "M B R E", label: "modes")
                            AtlasWorkbenchStat(value: "⌘Z", label: "reversible stack", tint: AeroTokens.ColorRole.information)
                        }
                        .frame(width: 150)
                    }
                }

                editorStage

                HStack(alignment: .top, spacing: 14) {
                    AtlasWorkbenchPanel(title: "Tool rail", subtitle: "the first keystroke is always visible", symbol: "wrench.and.screwdriver") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach([("select", "Select", "V"), ("arrow.up.right", "Arrow", "A"), ("pencil", "Pen", "P"), ("textformat", "Text", "T"), ("eye.slash", "Blur", "B"), ("crop", "Crop", "C")], id: \.0) { tool in
                                HStack(spacing: 8) {
                                    Image(systemName: tool.0).foregroundStyle(SettingsTheme.accent)
                                    Text(tool.1).font(.system(size: 12, weight: .medium))
                                    Spacer()
                                    Text(tool.2).font(SettingsTheme.typeMicro(design: .monospaced)).foregroundStyle(.tertiary)
                                }
                                .padding(9)
                                .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                    AtlasWorkbenchPanel(title: "ShareSafe", subtitle: "privacy review before delivery", symbol: "shield.checkered") {
                        VStack(alignment: .leading, spacing: 8) {
                            AtlasWorkbenchPill(text: appState.settings.shareSafeAutoRedactAfterCapture ? "AUTO-REDACT ON" : "REVIEW ON EXPORT", color: SettingsTheme.success, symbol: "checkmark.shield.fill")
                            Text("Blur, pixelate, or solid-fill sensitive regions without rewriting the original capture.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                AtlasWorkbenchPanel(title: "Open an image", subtitle: "real HistoryStore artifacts", symbol: "photo.on.rectangle") {
                    if imageItems.isEmpty {
                        Text("Capture an image to populate the editor stack.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(imageItems) { item in
                            AtlasOpenArtifactRow(item: item) {
                                guard let url = history.primaryURL(for: item), let image = NSImage(contentsOf: url)?.cgImageForAtlas else { return }
                                history.markOpened(item)
                                appState.openEditor(with: image)
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1_060, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .accessibilityIdentifier("atlas.surface.editor")
    }

    private var editorStage: some View {
        AtlasMockupCanvas(title: "Editor", status: "retention-dashboard.aeroshot · AUTOSAVED", menuItems: ["File", "Edit", "View", "Window", "Help"]) {
            HStack(alignment: .top, spacing: 12) {
                AtlasMockupWindow(title: "retention-dashboard.aeroshot") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("RETENTION DASHBOARD")
                                .font(SettingsTheme.typeMicro(weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.64))
                            Spacer()
                            AtlasWorkbenchTag(text: "BASE CAPTURE", color: SettingsTheme.success)
                        }
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LinearGradient(colors: [SettingsTheme.accent.opacity(0.20), AeroTokens.ColorRole.information.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(height: 132)
                            .overlay {
                                HStack(alignment: .bottom, spacing: 8) {
                                    ForEach([0.42, 0.66, 0.50, 0.78, 0.58, 0.91, 0.72], id: \.self) { value in
                                        Capsule().fill(.white.opacity(0.34)).frame(width: 14, height: 92 * value)
                                    }
                                }
                            }
                        ForEach([0.96, 0.91, 0.97, 0.64, 0.88], id: \.self) { width in
                            Capsule().fill(.white.opacity(0.10)).frame(width: 380 * width, height: 7)
                        }
                    }
                    .padding(20)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    AtlasWorkbenchTag(text: "INSPECTOR", color: SettingsTheme.accent)
                    AtlasValueRow(title: "Arrowheads", value: "Both")
                    AtlasValueRow(title: "Curve", value: "12 px")
                    AtlasValueRow(title: "Redaction", value: "Blur")
                    AtlasValueRow(title: "Opacity", value: "84%")
                    Divider().opacity(0.4)
                    AtlasWorkbenchPill(text: "SHARESAFE REVIEW", color: SettingsTheme.success, symbol: "checkmark.shield.fill")
                }
                .padding(14)
                .frame(width: 190)
                .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(18)
        }
        .frame(height: 335)
    }
}

struct AtlasGIFStudioSurface: View {
    let appState: AppState
    @EnvironmentObject private var history: HistoryStore

    private var gifItems: [HistoryItem] {
        history.items.filter { $0.kind == .gif && history.primaryURL(for: $0) != nil }.prefix(8).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 18) {
                    AtlasWorkbenchPanel(title: "GIF Studio", subtitle: "duration is width", symbol: "rectangle.on.rectangle") {
                        VStack(alignment: .leading, spacing: 9) {
                            AtlasWorkbenchTag(text: "SPACE PLAY · ←→ STEP · [ ] RETIME", color: SettingsTheme.accent)
                            Text("Make the loop legible before making it small.")
                                .font(.system(size: 27, weight: .semibold, design: .rounded))
                            Text("Frame timing, captions, palette, and export budget stay beside the exact frame they affect.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: 520, alignment: .leading)
                        }
                    }
                    AtlasWorkbenchPanel(title: "Export estimate", subtitle: "live plan", symbol: "gauge.with.dots.needle.67percent") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("2.0 MB")
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .foregroundStyle(SettingsTheme.accent)
                            Text("900 × 560 · 64 colours")
                                .font(SettingsTheme.typeMicro(design: .monospaced))
                                .foregroundStyle(.secondary)
                            AtlasWorkbenchPill(text: "BUDGET AUTO-FIT", color: SettingsTheme.success, symbol: "checkmark")
                        }
                    }
                    .frame(width: 205)
                }

                gifStage

                HStack(alignment: .top, spacing: 14) {
                    AtlasWorkbenchPanel(title: "Timing & frames", subtitle: "selected frame · 00:03.20", symbol: "timer") {
                        VStack(alignment: .leading, spacing: 10) {
                            AtlasTimelinePreview(frameCount: 12, accent: SettingsTheme.accent)
                            HStack {
                                AtlasWorkbenchActionButton(title: "−20 ms", symbol: "minus", kind: .secondary) { openLatestGIF() }
                                AtlasWorkbenchActionButton(title: "+20 ms", symbol: "plus", kind: .secondary) { openLatestGIF() }
                                AtlasWorkbenchActionButton(title: "Even out", symbol: "equal", kind: .quiet) { openLatestGIF() }
                            }
                            .frame(maxWidth: .infinity)
                            Text("Loop · forever     Captions · on     Duplicates merged · 3")
                                .font(SettingsTheme.typeMicro(design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    AtlasWorkbenchPanel(title: "Colour & output", subtitle: "write plan", symbol: "paintpalette") {
                        VStack(alignment: .leading, spacing: 9) {
                            AtlasValueRow(title: "Palette size", value: "64 colors")
                            AtlasValueRow(title: "Quality", value: "0.84")
                            AtlasValueRow(title: "Dither", value: "Ordered")
                            AtlasValueRow(title: "Width", value: "900 px")
                        }
                    }
                }

                AtlasWorkbenchPanel(title: "Open a GIF", subtitle: "real project routing", symbol: "rectangle.on.rectangle.angled") {
                    if gifItems.isEmpty {
                        Text("Record or import a GIF to populate this studio.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(gifItems) { item in
                            AtlasOpenArtifactRow(item: item) {
                                guard let url = history.primaryURL(for: item) else { return }
                                history.markOpened(item)
                                try? ProjectWindowRouter.openGIF(at: url)
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1_060, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .accessibilityIdentifier("atlas.surface.gifStudio")
    }

    private func openLatestGIF() {
        guard let item = gifItems.first, let url = history.primaryURL(for: item) else { return }
        history.markOpened(item)
        try? ProjectWindowRouter.openGIF(at: url)
    }

    private var gifStage: some View {
        AtlasMockupCanvas(title: "GIF Studio", status: "reticle-intent-switch.gif · 00:06.2", menuItems: ["File", "Edit", "Frames", "Window", "Help"]) {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    AtlasMockupWindow(title: "reticle-intent-switch.gif") {
                        ZStack {
                            LinearGradient(colors: [SettingsTheme.accent.opacity(0.20), AeroTokens.ColorRole.information.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            Circle().stroke(SettingsTheme.accent, lineWidth: 2).frame(width: 72, height: 72)
                            Image(systemName: "scope").font(.system(size: 28, weight: .light)).foregroundStyle(SettingsTheme.accent)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: 430, height: 215)
                    VStack(alignment: .leading, spacing: 8) {
                        AtlasWorkbenchPill(text: "LOOP · FOREVER", color: SettingsTheme.accent, symbol: "repeat")
                        AtlasValueRow(title: "Selected frame", value: "08 / 14")
                        AtlasValueRow(title: "Frame time", value: "220 ms")
                        AtlasValueRow(title: "Captions", value: "On")
                        AtlasWorkbenchPill(text: "DUPLICATES MERGED", color: SettingsTheme.success, symbol: "checkmark")
                    }
                    .padding(14)
                    .frame(width: 220)
                    .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                AtlasTimelinePreview(frameCount: 14, accent: SettingsTheme.accent)
                    .padding(.horizontal, 12)
            }
            .padding(18)
        }
        .frame(height: 325)
    }
}

struct AtlasMediaStudioSurface: View {
    let appState: AppState
    @EnvironmentObject private var history: HistoryStore

    private var recordings: [HistoryItem] {
        history.items.filter { ($0.kind == .recording || $0.kind == .project) && history.primaryURL(for: $0) != nil }.prefix(8).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                AtlasWorkbenchPanel(title: "Media Studio", subtitle: "the recording knows what happened", symbol: "film.stack") {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            AtlasWorkbenchTag(text: "SPACE PLAY · SPLIT AT PLAYHEAD · COLLAPSE GAPS", color: SettingsTheme.accent)
                            Spacer(minLength: 0)
                            AtlasWorkbenchPill(text: "EVENT TRACKS", color: SettingsTheme.success, symbol: "cursorarrow.click")
                        }
                        Text("Edit the evidence, not just the pixels.")
                            .font(.system(size: 29, weight: .semibold, design: .rounded))
                        Text("Cursor motion, clicks, idle gaps, audio, and overlays stay attached to the recording so export decisions can be explained and reversed.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 650, alignment: .leading)
                    }
                }

                mediaStage

                HStack(alignment: .top, spacing: 14) {
                    AtlasWorkbenchPanel(title: "Timeline", subtitle: "01:18.400 · slice B selected", symbol: "timeline.selection") {
                        VStack(alignment: .leading, spacing: 10) {
                            AtlasTimelinePreview(frameCount: 18, accent: AeroTokens.ColorRole.information)
                            HStack(spacing: 8) {
                                AtlasWorkbenchTag(text: "VIDEO", color: SettingsTheme.accent)
                                AtlasWorkbenchTag(text: "MIC", color: AeroTokens.ColorRole.information)
                                AtlasWorkbenchTag(text: "EVENTS", color: SettingsTheme.success)
                                AtlasWorkbenchTag(text: "OVERLAYS", color: AeroTokens.ColorRole.warning)
                            }
                            Text("Split ⌥S   ·   Ripple delete   ·   + Callout   ·   Crop")
                                .font(SettingsTheme.typeMicro(design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    AtlasWorkbenchPanel(title: "Presentation effects", subtitle: "recorded signals", symbol: "cursorarrow.rays") {
                        VStack(alignment: .leading, spacing: 8) {
                            AtlasValueRow(title: "Cursor emphasis", value: "1.38×")
                            AtlasValueRow(title: "Click emphasis", value: "9 events")
                            AtlasValueRow(title: "Idle gaps", value: "3 · > 1.5s")
                            AtlasValueRow(title: "Reframe", value: "9:16 follows cursor")
                        }
                    }
                }

                AtlasWorkbenchPanel(title: "Open a recording", subtitle: "real project routing", symbol: "play.rectangle") {
                    if recordings.isEmpty {
                        Text("Record a screen or open a .aeroshot video project to populate Media Studio.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recordings) { item in
                            AtlasOpenArtifactRow(item: item) {
                                open(item)
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1_060, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .accessibilityIdentifier("atlas.surface.mediaStudio")
    }

    private var mediaStage: some View {
        AtlasMockupCanvas(title: "Media Studio", status: "selection-overlay-demo.mp4 · 01:18.4", menuItems: ["File", "Edit", "Timeline", "Window", "Help"]) {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    AtlasMockupWindow(title: "selection-overlay-demo.mp4") {
                        ZStack {
                            LinearGradient(colors: [AeroTokens.ColorRole.information.opacity(0.20), SettingsTheme.accent.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(.white.opacity(0.36), lineWidth: 1)
                                .padding(30)
                            Circle().stroke(AeroTokens.ColorRole.warning, lineWidth: 3).frame(width: 26, height: 26).offset(x: 74, y: -42)
                            Text("PUNCH-IN 1.38×")
                                .font(SettingsTheme.typeMicro(weight: .bold, design: .monospaced))
                                .foregroundStyle(SettingsTheme.accent)
                                .padding(5)
                                .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .offset(x: 86, y: -80)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, minHeight: 205)
                    VStack(alignment: .leading, spacing: 8) {
                        AtlasWorkbenchTag(text: "REFRAME FOLLOWS CURSOR", color: SettingsTheme.accent)
                        AtlasValueRow(title: "Cursor events", value: "9")
                        AtlasValueRow(title: "Click events", value: "9")
                        AtlasValueRow(title: "Idle gaps", value: "3")
                        AtlasValueRow(title: "Webcam", value: "Off")
                    }
                    .padding(14)
                    .frame(width: 210)
                    .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                AtlasTimelinePreview(frameCount: 20, accent: AeroTokens.ColorRole.information)
                    .padding(.horizontal, 12)
            }
            .padding(18)
        }
        .frame(height: 325)
    }

    private func open(_ item: HistoryItem) {
        guard let url = history.primaryURL(for: item) else { return }
        history.markOpened(item)
        if item.kind == .project {
            _ = try? ProjectWindowRouter.openProject(at: url, appState: appState)
        } else {
            Task { @MainActor in
                try? await ProjectWindowRouter.openRecording(at: url)
            }
        }
    }
}

struct AtlasStudioSurface: View {
    let appState: AppState
    @EnvironmentObject private var history: HistoryStore
    @State private var brief = AtlasStudioBrief.slack

    private var recording: HistoryItem? {
        history.items.first { ($0.kind == .recording || $0.kind == .project) && history.primaryURL(for: $0) != nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                AtlasWorkbenchPanel(title: "Studio", subtitle: "state the brief · negotiate the plan", symbol: "wand.and.stars") {
                    VStack(alignment: .leading, spacing: 9) {
                        AtlasWorkbenchTag(text: "NON-DESTRUCTIVE PLAN", color: SettingsTheme.accent)
                        Text("Tell Aeroshot what the recording is for.")
                            .font(.system(size: 29, weight: .semibold, design: .rounded))
                        Text("Every accepted proposal becomes a reversible move in Media Studio. Nothing touches the source until you accept the plan.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 650, alignment: .leading)
                    }
                }

                AtlasWorkbenchPanel(title: "The brief", subtitle: "what is this for?", symbol: "text.bubble") {
                    Picker("Destination", selection: $brief) {
                        ForEach(AtlasStudioBrief.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(brief.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                studioStage

                AtlasWorkbenchPanel(title: "Plan", subtitle: "proposals derived from the recording events", symbol: "list.bullet.rectangle") {
                    VStack(spacing: 8) {
                        ForEach(AtlasStudioProposal.allCases) { proposal in
                            HStack(spacing: 10) {
                                Image(systemName: proposal.symbol)
                                    .foregroundStyle(proposal.tint)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(proposal.title).font(.system(size: 12, weight: .semibold))
                                    Text(proposal.detail).font(SettingsTheme.typeMicro()).foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 0)
                                AtlasWorkbenchTag(text: proposal.delta, color: proposal.tint)
                            }
                            .padding(10)
                            .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }
                }

                HStack {
                    AtlasWorkbenchPill(text: recording == nil ? "NO SOURCE OPEN" : "SOURCE READY", color: recording == nil ? .secondary : SettingsTheme.success, symbol: recording == nil ? "questionmark" : "checkmark")
                    Spacer(minLength: 0)
                    AtlasWorkbenchActionButton(title: "Open in Media Studio", symbol: "arrow.up.right", kind: .primary) {
                        guard let recording else { return }
                        if recording.kind == .project, let url = history.primaryURL(for: recording) {
                            _ = try? ProjectWindowRouter.openProject(at: url, appState: appState)
                        } else if let url = history.primaryURL(for: recording) {
                            Task { @MainActor in try? await ProjectWindowRouter.openRecording(at: url) }
                        }
                    }
                    .frame(width: 210)
                    .disabled(recording == nil)
                }
            }
            .padding(28)
            .frame(maxWidth: 1_060, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .accessibilityIdentifier("atlas.surface.studio")
    }

    private var studioStage: some View {
        AtlasMockupCanvas(title: "Studio", status: "retention-dashboard.aeroshot · PLAN READY", menuItems: ["File", "Edit", "Plan", "Window", "Help"]) {
            HStack(alignment: .top, spacing: 14) {
                AtlasMockupWindow(title: "selection-overlay-demo.mp4") {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            Text("THE BRIEF")
                                .font(SettingsTheme.typeMicro(weight: .bold, design: .monospaced))
                                .foregroundStyle(SettingsTheme.accent)
                            Spacer()
                            AtlasWorkbenchPill(text: "PUNCH-IN", color: AeroTokens.ColorRole.information, symbol: "plus.magnifyingglass")
                        }
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(LinearGradient(colors: [SettingsTheme.accent.opacity(0.18), AeroTokens.ColorRole.information.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(height: 118)
                            .overlay {
                                HStack(spacing: 8) {
                                    ForEach(0..<10, id: \.self) { index in
                                        Capsule().fill(.white.opacity(index == 5 ? 0.85 : 0.26)).frame(width: 7, height: CGFloat(28 + (index % 4) * 15))
                                    }
                                }
                            }
                        AtlasTimelinePreview(frameCount: 18, accent: SettingsTheme.accent)
                    }
                    .padding(18)
                }
                .frame(maxWidth: .infinity, minHeight: 240)
                VStack(alignment: .leading, spacing: 9) {
                    AtlasWorkbenchTag(text: "SOLVING PLAN", color: SettingsTheme.accent)
                    Text("5 moves")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                    AtlasValueRow(title: "Length", value: "−52.2s")
                    AtlasValueRow(title: "Size", value: "−70%")
                    AtlasValueRow(title: "Format", value: brief.title)
                }
                .padding(15)
                .frame(width: 190)
                .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(18)
        }
        .frame(height: 320)
    }
}

private enum AtlasStudioBrief: String, CaseIterable, Identifiable {
    case slack, social, docs, pr
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var detail: String {
        switch self {
        case .slack: "Keep it short, legible, and muted for a team channel."
        case .social: "Reframe the strongest click for a vertical feed."
        case .docs: "Preserve the full context and add chapters."
        case .pr: "Ship a compact GIF that renders inline."
        }
    }
}

private enum AtlasStudioProposal: String, CaseIterable, Identifiable {
    case gaps, lead, punch, scale, chapters
    var id: String { rawValue }
    var title: String {
        switch self {
        case .gaps: "Collapse 3 idle gaps"
        case .lead: "Trim the 4.2s lead-in"
        case .punch: "Punch in on 9 clicks"
        case .scale: "Downscale to 1280 × 800"
        case .chapters: "Add 3 chapter markers"
        }
    }
    var detail: String {
        switch self {
        case .gaps: "No clicks or cursor motion; static frames are safe to skip."
        case .lead: "The viewer sees a still frame before the first action."
        case .punch: "Recorded click positions make the zooms safe to place."
        case .scale: "Text stays legible while the file drops under the ceiling."
        case .chapters: "Topic changes line up with recorded pauses."
        }
    }
    var delta: String {
        switch self {
        case .gaps: "−48s"
        case .lead: "−4.2s"
        case .punch: "+1.04×"
        case .scale: "−70%"
        case .chapters: "+3"
        }
    }
    var symbol: String {
        switch self {
        case .gaps: "scissors"
        case .lead: "backward.end"
        case .punch: "plus.magnifyingglass"
        case .scale: "arrow.down.right.and.arrow.up.left"
        case .chapters: "bookmark"
        }
    }
    var tint: Color {
        switch self {
        case .gaps, .lead: AeroTokens.ColorRole.warning
        case .punch, .chapters: SettingsTheme.accent
        case .scale: AeroTokens.ColorRole.information
        }
    }
}

struct AtlasMenuBarSurface: View {
    let appState: AppState

    private var hotkeys: [HotkeyAction: Hotkey] { appState.settings.hotkeys() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        AtlasWorkbenchTag(text: "MENU BAR · FRONTMOST APP AWARE", color: SettingsTheme.accent)
                        Text("The menu knows what you are looking at.")
                            .font(.system(size: 31, weight: .semibold, design: .rounded))
                        Text("The real status item follows the active capture profile and the hotkeys in Settings. These controls call the same AppDelegate actions.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 620, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                    AtlasWorkbenchPill(text: appState.settings.showInMenuBar ? "MENU BAR ON" : "MENU BAR OFF", color: appState.settings.showInMenuBar ? SettingsTheme.success : .secondary, symbol: "menubar.arrow.up.rectangle")
                }

                menuBarStage

                HStack(alignment: .top, spacing: 14) {
                    AtlasWorkbenchPanel(title: "Capture", subtitle: "production commands", symbol: "camera.viewfinder") {
                        VStack(spacing: 8) {
                            AtlasMenuCommand(title: "Capture area", symbol: "rectangle.dashed", hotkey: hotkeys[.captureArea]) { appState.captureController.beginAreaCapture() }
                            AtlasMenuCommand(title: "Capture window", symbol: "macwindow", hotkey: hotkeys[.captureWindow]) { appState.captureController.beginWindowCapture() }
                            AtlasMenuCommand(title: "Capture screen", symbol: "display", hotkey: hotkeys[.captureScreen]) { appState.captureController.captureFullScreen() }
                            AtlasMenuCommand(title: "Scrolling capture", symbol: "arrow.down.to.line", hotkey: hotkeys[.captureScrolling]) { appState.scrollingCaptureController.begin() }
                        }
                    }
                    AtlasWorkbenchPanel(title: "Recording", subtitle: "media commands", symbol: "record.circle") {
                        VStack(spacing: 8) {
                            AtlasMenuCommand(title: "Record area", symbol: "record.circle", hotkey: hotkeys[.recordArea]) { appState.recordingController.beginAreaRecording() }
                            AtlasMenuCommand(title: "Record screen", symbol: "display", hotkey: hotkeys[.recordScreen]) { appState.recordingController.beginScreenRecording() }
                            AtlasMenuCommand(title: "Open tray", symbol: "tray.full", hotkey: hotkeys[.showHistory]) { appState.showHistoryWindow() }
                        }
                    }
                }

                AtlasWorkbenchPanel(title: "Active profile", subtitle: "same preferences used by capture and the status item", symbol: appState.settings.activeCaptureProfile.symbol) {
                    HStack(spacing: 12) {
                        Image(systemName: appState.settings.activeCaptureProfile.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(SettingsTheme.accent)
                            .frame(width: 40, height: 40)
                            .background(SettingsTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(appState.settings.activeCaptureProfile.name)
                                .font(.system(size: 14, weight: .semibold))
                            Text(appState.settings.activeCaptureProfile.summary)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        AtlasWorkbenchTag(text: appState.settings.imageFormat.displayName.uppercased(), color: AeroTokens.ColorRole.information)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1_060, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .accessibilityIdentifier("atlas.surface.menuBar")
    }

    private var menuBarStage: some View {
        AtlasMockupCanvas(title: "Menu Bar", status: "PAUSED · 100% · SAT 15:20") {
            HStack(alignment: .top) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Image(systemName: "camera.viewfinder").foregroundStyle(SettingsTheme.accent)
                        Text("Aeroshot")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("CAPTURE")
                            .font(SettingsTheme.typeMicro(weight: .bold, design: .monospaced))
                            .foregroundStyle(SettingsTheme.accent)
                    }
                    .padding(12)
                    Divider().opacity(0.4)
                    Text("CAPTURE")
                        .font(SettingsTheme.typeMicro(weight: .bold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, 9)
                    ForEach(["Capture area", "Capture window", "Capture screen", "Scrolling capture"], id: \.self) { item in
                        HStack {
                            Text(item)
                            Spacer()
                            Text("⌃⌥1")
                                .font(SettingsTheme.typeMicro(design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    }
                    Divider().opacity(0.4)
                    AtlasMenuCommand(title: "Open Atlas Workspace", symbol: "square.grid.2x2", hotkey: nil) { appState.showAtlasWorkbench() }
                        .padding(7)
                }
                .frame(width: 264)
                .background(.regularMaterial.opacity(0.95), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.50), radius: 20, y: 10)
                .padding(.top, 35)
                .padding(.trailing, 76)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(height: 315)
    }
}

private struct AtlasMenuCommand: View {
    let title: String
    let symbol: String
    let hotkey: Hotkey?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .foregroundStyle(SettingsTheme.accent)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Text(hotkey?.displayString ?? "—")
                    .font(SettingsTheme.typeMicro(design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct AtlasOpenArtifactRow: View {
    let item: HistoryItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.kind.atlasSymbol)
                    .foregroundStyle(item.kind.atlasColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName.isEmpty ? item.kind.rawValue.capitalized : item.fileName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(item.atlasDetail)
                        .font(SettingsTheme.typeMicro(design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct AtlasTimelinePreview: View {
    let frameCount: Int
    let accent: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<frameCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(accent.opacity(index == 4 ? 0.95 : 0.25 + Double(index % 3) * 0.08))
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(index % 5 == 0 ? .white.opacity(0.6) : .clear)
                            .frame(height: 2)
                    }
            }
        }
        .frame(height: 42)
        .padding(7)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AtlasValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }
}

private extension HistoryCaptureKind {
    var atlasSymbol: String {
        switch self {
        case .image: "photo"
        case .text: "text.alignleft"
        case .recording: "film"
        case .gif: "rectangle.on.rectangle"
        case .project: "shippingbox"
        }
    }

    var atlasColor: Color {
        switch self {
        case .image: SettingsTheme.accent
        case .text: AeroTokens.ColorRole.information
        case .recording: AeroTokens.ColorRole.danger
        case .gif: AeroTokens.ColorRole.warning
        case .project: SettingsTheme.success
        }
    }
}

private extension HistoryItem {
    var atlasDetail: String {
        let dimensions = pixelWidth > 0 && pixelHeight > 0 ? "\(pixelWidth) × \(pixelHeight)" : nil
        let duration = durationSeconds.map { String(format: "%.1fs", $0) }
        return [kind.rawValue.uppercased(), dimensions, duration, checksum.map { "#\($0.prefix(8))" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

private extension NSImage {
    var cgImageForAtlas: CGImage? {
        var proposed = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &proposed, context: nil, hints: nil)
    }
}
