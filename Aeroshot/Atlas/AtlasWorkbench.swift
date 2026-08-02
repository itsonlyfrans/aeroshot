import AppKit
import SwiftUI

nonisolated enum AtlasWorkbenchSurface: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case app
    case tray
    case selection
    case editor
    case gifStudio
    case mediaStudio
    case studio
    case menuBar
    case onboarding
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app: "Aeroshot App"
        case .tray: "Capture Tray"
        case .selection: "Selection Surface"
        case .editor: "Editor"
        case .gifStudio: "GIF Studio"
        case .mediaStudio: "Media Studio"
        case .studio: "Studio"
        case .menuBar: "Menu Bar"
        case .onboarding: "Onboarding"
        case .settings: "Settings Atlas"
        }
    }

    var tabTitle: String {
        switch self {
        case .app: "Aeroshot App"
        case .tray: "Capture Tray"
        case .selection: "Selection"
        case .editor: "Editor"
        case .gifStudio: "GIF Studio"
        case .mediaStudio: "Media Studio"
        case .studio: "Studio"
        case .menuBar: "Menu Bar"
        case .onboarding: "Onboarding"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .app: "camera.viewfinder"
        case .tray: "tray.full"
        case .selection: "selection.pin.in.out"
        case .editor: "pencil.and.outline"
        case .gifStudio: "rectangle.on.rectangle"
        case .mediaStudio: "film.stack"
        case .studio: "wand.and.stars"
        case .menuBar: "menubar.arrow.up.rectangle"
        case .onboarding: "sparkles"
        case .settings: "square.grid.2x2"
        }
    }

    var eyebrow: String {
        switch self {
        case .app: "CAPTURE SYSTEM"
        case .tray: "THE STACK IS THE LIBRARY"
        case .selection: "DRAG TO SELECT"
        case .editor: "MOVE STACK · NON-DESTRUCTIVE"
        case .gifStudio: "DURATION IS WIDTH"
        case .mediaStudio: "THE RECORDING KNOWS WHAT HAPPENED"
        case .studio: "STATE THE BRIEF · NEGOTIATE THE PLAN"
        case .menuBar: "THE MENU KNOWS WHAT YOU ARE LOOKING AT"
        case .onboarding: "PROVE IT · DO NOT PROMISE IT"
        case .settings: "EVERYTHING AEROSHOT CAN DO"
        }
    }
}

@MainActor
final class AtlasWorkbenchWindowController: NSWindowController, NSWindowDelegate {
    private unowned let appState: AppState

    init(appState: AppState, initialSurface: AtlasWorkbenchSurface = .app) {
        self.appState = appState
        let rootView = AtlasWorkbenchView(appState: appState, initialSurface: initialSurface)
        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.title = "Aeroshot Atlas"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 1_280, height: 820))
        window.minSize = NSSize(width: 1_060, height: 680)
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func show(surface: AtlasWorkbenchSurface? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        if let surface {
            NotificationCenter.default.post(
                name: .atlasWorkbenchSelectSurface,
                object: surface.rawValue
            )
        }
    }

    func windowWillClose(_ notification: Notification) {
        appState.dismissAtlasWorkbench(self)
    }
}

struct AtlasWorkbenchView: View {
    @ObservedObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var surface: AtlasWorkbenchSurface

    init(appState: AppState, initialSurface: AtlasWorkbenchSurface = .app) {
        self.appState = appState
        _surface = State(initialValue: initialSurface)
    }

    var body: some View {
        VStack(spacing: 0) {
            AtlasWorkbenchAppHeader(surface: $surface)
            Divider()
            surfaceContent
        }
        .background(SettingsAtlasBackground())
        .environmentObject(appState.history)
        .environmentObject(appState.settings)
        .animation(SettingsTheme.spring(reducedMotion: reduceMotion), value: surface)
        .onReceive(NotificationCenter.default.publisher(for: .atlasWorkbenchSelectSurface)) { notification in
            guard let raw = notification.object as? String,
                  let requested = AtlasWorkbenchSurface(rawValue: raw) else { return }
            surface = requested
        }
        .accessibilityIdentifier("atlas.workbench")
    }

    @ViewBuilder
    private var surfaceContent: some View {
        switch surface {
        case .app:
            AtlasAppSurface(appState: appState, select: { surface = $0 })
        case .tray:
            AtlasTraySurface(appState: appState)
        case .selection:
            AtlasSelectionSurface(appState: appState)
        case .editor:
            AtlasEditorSurface(appState: appState)
        case .gifStudio:
            AtlasGIFStudioSurface(appState: appState)
        case .mediaStudio:
            AtlasMediaStudioSurface(appState: appState)
        case .studio:
            AtlasStudioSurface(appState: appState)
        case .menuBar:
            AtlasMenuBarSurface(appState: appState)
        case .onboarding:
            AtlasOnboardingSurface(appState: appState)
        case .settings:
            SettingsAtlasWindow()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension Notification.Name {
    static let atlasWorkbenchSelectSurface = Notification.Name("Aeroshot.AtlasWorkbenchSelectSurface")
}
