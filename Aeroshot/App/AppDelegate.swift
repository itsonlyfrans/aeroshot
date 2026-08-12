import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    lazy var automationRouter = AutomationRouter(host: self)

    private var statusItem: NSStatusItem?
    private var statusPopover: NSPopover?
    private var recordingObserver: AnyCancellable?
    private var settingsObserver: AnyCancellable?
    private var workspaceObserver: NSObjectProtocol?
    private var statusClockTimer: Timer?
    private var recordingStartedAt: Date?
    private var hotkeysPaused = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        processAutomationLaunchArguments()
        appState.settings.sanitizeStoredHotkeys()
        setupMainMenu()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.applyAppPresence()
            }
        }
        registerHotkeys()
        _ = appState.permissions.preflight()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.appState.showPermissionWizardIfNeeded()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateStatusItemAppearance()
                HotkeyManager.shared.refreshMonitors()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .settingsProfileDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleSettingsProfileSideEffects()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .appPresenceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleAppPresenceUpdate()
            }
        }

        recordingObserver = appState.$isRecording.sink { [weak self] isRecording in
            MainActor.assumeIsolated {
                self?.recordingStateDidChange(isRecording)
            }
        }
        settingsObserver = appState.settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.applyAppPresence()
                }
            }
        }

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleHotkeyRebindIfNeeded()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == "aeroshot" {
            do {
                let action = try AutomationActionParser.parse(url: url)
                guard action.allowsExternalURL(using: confirmExternalCapture) else { continue }
                _ = automationRouter.route(action)
            }
            catch { NSSound.beep() }
        }
    }

    private func confirmExternalCapture(_ mode: AutomationCaptureMode) -> Bool {
        let isRecording = mode == .recordArea || mode == .recordScreen
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = isRecording ? "Start screen recording?" : "Start screenshot capture?"
        alert.informativeText = "Another app or website asked Aeroshot to start \(mode.displayName.lowercased()). Continue only if you expected this request."
        alert.addButton(withTitle: isRecording ? "Start Recording" : "Start Capture")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func processAutomationLaunchArguments() {
        do {
            guard let action = try AutomationActionParser.parse(arguments: ProcessInfo.processInfo.arguments) else { return }
            let result = automationRouter.route(action)
            FileHandle.standardOutput.write(Data((result.message + "\n").utf8))
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
        }
    }

    private var lastHotkeyBundleID: String?
    private var lastEffectiveHotkeys: [HotkeyAction: Hotkey]?

    private func scheduleHotkeyRebindIfNeeded() {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let hotkeys = appState.settings.effectiveHotkeys(for: bundleID)
        if statusItem != nil {
            refreshStatusPopover()
            updateStatusItemAppearance()
        }
        guard hotkeys != lastEffectiveHotkeys else {
            lastHotkeyBundleID = bundleID
            return
        }
        lastHotkeyBundleID = bundleID
        lastEffectiveHotkeys = hotkeys
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.rebindHotkeys()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if appState.settings.runsHeadless || !flag {
            appState.showSettingsWindow()
        }
        return true
    }

    // MARK: - Main menu (enables shortcuts while the app is active)

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Aeroshot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let fileMenu = NSMenu(title: "File")
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let openProjectItem = NSMenuItem(title: "Open Project…", action: #selector(openProjectDocument), keyEquivalent: "o")
        openProjectItem.target = self
        fileMenu.addItem(openProjectItem)
        fileMenu.addItem(.separator())
        // nil-target items resolve through the responder chain, so they are
        // enabled only while a window implementing the selector is key.
        fileMenu.addItem(NSMenuItem(
            title: "Save Project",
            action: #selector(EditorWindowController.saveProjectDocument(_:)),
            keyEquivalent: "s"
        ))
        let saveAsItem = NSMenuItem(
            title: "Save Project As…",
            action: #selector(EditorWindowController.saveProjectDocumentAs(_:)),
            keyEquivalent: "S"
        )
        fileMenu.addItem(saveAsItem)
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        let editMenu = NSMenu(title: "Edit")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        editMenu.addItem(NSMenuItem(title: "Copy Annotation", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste Annotation", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenu.addItem(NSMenuItem(title: "Duplicate Annotation", action: #selector(EditorWindowController.duplicateAnnotation(_:)), keyEquivalent: "d"))

        let toolsMenu = NSMenu(title: "Tools")
        let toolsItem = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
        toolsItem.submenu = toolsMenu
        mainMenu.addItem(toolsItem)
        for shortcut in EditorToolKeymap.shortcuts {
            let item = NSMenuItem(
                title: "\(shortcut.tool.displayName) (\(shortcut.key.uppercased()))",
                action: #selector(EditorWindowController.chooseAnnotationTool(_:)),
                keyEquivalent: ""
            )
            item.representedObject = shortcut.tool.rawValue
            toolsMenu.addItem(item)
        }

        let captureMenu = NSMenu(title: "Capture")
        let captureItem = NSMenuItem(title: "Capture", action: nil, keyEquivalent: "")
        captureItem.submenu = captureMenu
        mainMenu.addItem(captureItem)

        let hotkeys = appState.settings.hotkeys()
        func addCaptureItem(_ title: String, action: Selector, actionKey: HotkeyAction) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if let hk = hotkeys[actionKey] {
                hk.applyToMenuItem(item, title: title)
            }
            item.image = NSImage(systemSymbolName: actionKey.symbol, accessibilityDescription: nil)
            captureMenu.addItem(item)
        }

        addCaptureItem("All-in-One…", action: #selector(showAllInOne), actionKey: .allInOne)
        captureMenu.addItem(.separator())
        addCaptureItem("Capture Area", action: #selector(captureArea), actionKey: .captureArea)
        addCaptureItem("Capture Window", action: #selector(captureWindow), actionKey: .captureWindow)
        addCaptureItem("Capture Full Screen", action: #selector(captureScreen), actionKey: .captureScreen)
        addCaptureItem("Capture Last Region", action: #selector(captureLastRegion), actionKey: .captureLastRegion)
        addCaptureItem("Scrolling Capture", action: #selector(captureScrolling), actionKey: .captureScrolling)
        addCaptureItem("Capture Text (OCR)", action: #selector(captureOCR), actionKey: .captureOCR)
        captureMenu.addItem(.separator())
        addCaptureItem("Record Area", action: #selector(recordArea), actionKey: .recordArea)
        addCaptureItem("Record Screen", action: #selector(recordScreen), actionKey: .recordScreen)
        captureMenu.addItem(.separator())
        addCaptureItem("History", action: #selector(showHistory), actionKey: .showHistory)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Status item

    private func scheduleSettingsProfileSideEffects() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.rebindHotkeys()
                self?.applyAppPresence()
            }
        }
    }

    private func scheduleAppPresenceUpdate() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.applyAppPresence()
            }
        }
    }

    func applyAppPresence() {
        let settings = appState.settings

        NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)

        if settings.showInMenuBar {
            if statusItem == nil {
                setupStatusItem()
            } else {
                refreshStatusPopover()
            }
            updateStatusItemAppearance()
        } else {
            tearDownStatusItem()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(toggleStatusPopover)
        button.sendAction(on: [.leftMouseUp])
        button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Aeroshot")
        statusItem = item
        refreshStatusPopover()
        updateStatusItemAppearance()
    }

    private func tearDownStatusItem() {
        statusPopover?.performClose(nil)
        statusPopover = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func makeStatusPopoverView() -> StatusMenuPopoverView {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let bundleID = frontmostApp?.bundleIdentifier
        let appIcon = frontmostApp?.icon?.copy() as? NSImage
        let hotkeyProfile = HotkeyProfileStore.profile(for: bundleID, in: appState.settings.hotkeyProfiles())
        return StatusMenuPopoverView(
            appState: appState,
            frontmostName: frontmostApp?.localizedName ?? "No app",
            frontmostBundleID: bundleID,
            frontmostIcon: appIcon,
            hotkeyProfile: hotkeyProfile,
            recordingStartedAt: recordingStartedAt,
            hotkeysPaused: hotkeysPaused,
            actions: StatusMenuActions(
                allInOne: { [weak self] in self?.runStatusAction { self?.showAllInOne() } },
                captureArea: { [weak self] in self?.runStatusAction { self?.captureArea() } },
                captureWindow: { [weak self] in self?.runStatusAction { self?.captureWindow() } },
                captureScreen: { [weak self] in self?.runStatusAction { self?.captureScreen() } },
                captureLastRegion: { [weak self] in self?.runStatusAction { self?.captureLastRegion() } },
                captureScrolling: { [weak self] in self?.runStatusAction { self?.captureScrolling() } },
                captureOCR: { [weak self] in self?.runStatusAction { self?.captureOCR() } },
                recordArea: { [weak self] in self?.runStatusAction { self?.recordArea() } },
                recordScreen: { [weak self] in self?.runStatusAction { self?.recordScreen() } },
                selectProfile: { [weak self] profile in
                    guard let self else { return }
                    self.appState.settings.applyCaptureProfile(profile)
                    self.refreshStatusPopover()
                },
                showHistory: { [weak self] in self?.runStatusAction { self?.showHistory() } },
                showEditor: { [weak self] in self?.runStatusAction { self?.showEditor() } },
                showSettings: { [weak self] in self?.runStatusAction { self?.showSettings() } },
                toggleHotkeys: { [weak self] in self?.toggleHotkeys() },
                openRecent: { [weak self] item in self?.runStatusAction { self?.openRecent(item) } },
                quit: { NSApp.terminate(nil) }
            )
        )
    }

    private func runStatusAction(_ action: () -> Void) {
        closeStatusPopover()
        action()
    }

    @objc private func toggleStatusPopover() {
        guard let button = statusItem?.button else { return }
        if let statusPopover, statusPopover.isShown {
            statusPopover.performClose(nil)
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentSize = NSSize(width: 448, height: 760)
        popover.contentViewController = NSHostingController(rootView: makeStatusPopoverView())
        statusPopover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func closeStatusPopover() {
        statusPopover?.performClose(nil)
    }

    private func refreshStatusPopover() {
        guard let statusPopover, statusPopover.isShown else { return }
        statusPopover.contentViewController = NSHostingController(rootView: makeStatusPopoverView())
    }

    // MARK: - Hotkeys

    private func registerHotkeys() {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let hotkeys = appState.settings.effectiveHotkeys(for: bundleID)
        var bindings: [HotkeyAction: (hotkey: Hotkey, handler: () -> Void)] = [:]
        bindings.reserveCapacity(hotkeys.count)
        for (action, hotkey) in hotkeys {
            bindings[action] = (hotkey, { [weak self] in
                self?.perform(hotkeyAction: action)
            })
        }
        HotkeyManager.shared.setBindings(bindings)
        lastHotkeyBundleID = bundleID
        lastEffectiveHotkeys = hotkeys

        // Do not interrupt launches with a modal Accessibility prompt. The
        // System Settings pane and shortcut settings surface the missing access
        // without blocking capture or automated UI tests.
    }

    func rebindHotkeys() {
        HotkeyManager.shared.unregisterAll()
        registerHotkeys()
        setupMainMenu()
        refreshStatusPopover()
    }

    private func perform(hotkeyAction: HotkeyAction) {
        // A global hotkey can arrive while the status popover is still open;
        // close it before capture so the transient chrome cannot be sampled.
        closeStatusPopover()
        switch hotkeyAction {
        case .captureArea: captureArea()
        case .captureWindow: captureWindow()
        case .captureScreen: captureScreen()
        case .captureLastRegion: captureLastRegion()
        case .captureScrolling: captureScrolling()
        case .captureOCR: captureOCR()
        case .allInOne: showAllInOne()
        case .recordArea: recordArea()
        case .recordScreen: recordScreen()
        case .showHistory: showHistory()
        }
    }

    // MARK: - Actions

    @objc private func showAllInOne() {
        appState.allInOneController.begin()
    }

    @objc private func captureOCR() {
        appState.ocrCaptureController.begin()
    }

    @objc private func captureArea() {
        appState.captureController.beginAreaCapture()
    }

    @objc private func captureWindow() {
        appState.captureController.beginWindowCapture()
    }

    @objc private func captureScreen() {
        appState.captureController.captureFullScreen()
    }

    @objc private func captureLastRegion() {
        appState.captureController.captureLastRegion()
    }

    @objc private func captureScrolling() {
        appState.scrollingCaptureController.begin()
    }

    @objc private func recordArea() {
        appState.recordingController.beginAreaRecording()
    }

    @objc private func recordScreen() {
        appState.recordingController.beginScreenRecording()
    }

    @objc private func showHistory() {
        appState.toggleHistoryWindow()
    }

    @objc private func showEditor() {
        guard let item = appState.history.items.first(where: { $0.kind == .image }),
              let image = NSImage(contentsOf: appState.history.fileURL(for: item)),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            appState.showHistoryWindow()
            ToastController.shared.show("Capture an image to open it in Editor", symbol: "photo")
            return
        }
        appState.history.markOpened(item)
        appState.openEditor(with: cgImage)
    }

    private func openRecent(_ item: HistoryItem) {
        switch item.kind {
        case .image:
            guard let image = NSImage(contentsOf: appState.history.fileURL(for: item)),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                appState.showHistoryWindow()
                return
            }
            appState.history.markOpened(item)
            appState.openEditor(with: cgImage)
        case .project:
            guard let url = item.projectURL else {
                appState.showHistoryWindow()
                return
            }
            do {
                try ProjectWindowRouter.openProject(at: url, appState: appState)
            } catch {
                appState.showHistoryWindow()
            }
        default:
            appState.showHistoryWindow()
        }
    }

    @objc private func toggleHotkeys() {
        hotkeysPaused.toggle()
        HotkeyManager.shared.setEnabled(!hotkeysPaused)
        refreshStatusPopover()
        updateStatusItemAppearance()
    }

    @objc private func openProjectDocument() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let type = UTType(filenameExtension: "aeroshot") {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ProjectWindowRouter.openProject(at: url, appState: appState)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t Open Project"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc func showSettings() {
        appState.showSettingsWindow()
    }

    private func recordingStateDidChange(_ isRecording: Bool) {
        if isRecording {
            if recordingStartedAt == nil { recordingStartedAt = Date() }
            if statusClockTimer == nil {
                let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateStatusItemAppearance() }
                }
                RunLoop.main.add(timer, forMode: .common)
                statusClockTimer = timer
            }
        } else {
            statusClockTimer?.invalidate()
            statusClockTimer = nil
            recordingStartedAt = nil
        }
        refreshStatusPopover()
        updateStatusItemAppearance()
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem?.button else { return }

        let symbolName: String
        if appState.isRecording {
            symbolName = "record.circle.fill"
        } else if hotkeysPaused {
            symbolName = "pause.circle"
        } else if !SettingsPermissions.allGranted {
            symbolName = "exclamationmark.shield.fill"
        } else {
            symbolName = "camera.viewfinder"
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Aeroshot")
        button.image = image

        if appState.isRecording {
            button.contentTintColor = .systemRed
            let elapsed = Int(Date().timeIntervalSince(recordingStartedAt ?? Date()))
            button.title = String(format: " %d:%02d", elapsed / 60, elapsed % 60)
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            button.imagePosition = .imageLeading
            statusItem?.length = NSStatusItem.variableLength
        } else if hotkeysPaused {
            button.contentTintColor = .secondaryLabelColor
            button.title = ""
            button.imagePosition = .imageOnly
            statusItem?.length = NSStatusItem.squareLength
        } else if !SettingsPermissions.allGranted {
            button.contentTintColor = .systemOrange
            button.title = ""
            button.imagePosition = .imageOnly
            statusItem?.length = NSStatusItem.squareLength
        } else {
            button.contentTintColor = nil
            button.title = ""
            button.imagePosition = .imageOnly
            statusItem?.length = NSStatusItem.squareLength
        }
    }
}

@MainActor
private struct StatusMenuActions {
    let allInOne: @MainActor () -> Void
    let captureArea: @MainActor () -> Void
    let captureWindow: @MainActor () -> Void
    let captureScreen: @MainActor () -> Void
    let captureLastRegion: @MainActor () -> Void
    let captureScrolling: @MainActor () -> Void
    let captureOCR: @MainActor () -> Void
    let recordArea: @MainActor () -> Void
    let recordScreen: @MainActor () -> Void
    let selectProfile: @MainActor (CaptureProfile) -> Void
    let showHistory: @MainActor () -> Void
    let showEditor: @MainActor () -> Void
    let showSettings: @MainActor () -> Void
    let toggleHotkeys: @MainActor () -> Void
    let openRecent: @MainActor (HistoryItem) -> Void
    let quit: @MainActor () -> Void
}

private struct StatusMenuIntent: Identifiable {
    let id: String
    let label: String
    let hint: String
    let symbol: String
    let hotkey: HotkeyAction
    let run: @MainActor () -> Void
}

@MainActor
private struct StatusMenuPopoverView: View {
    @ObservedObject private var appState: AppState
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var history: HistoryStore

    private let frontmostName: String
    private let frontmostBundleID: String?
    private let frontmostIcon: NSImage?
    private let hotkeyProfile: HotkeyProfile?
    private let recordingStartedAt: Date?
    private let hotkeysPaused: Bool
    private let actions: StatusMenuActions

    init(
        appState: AppState,
        frontmostName: String,
        frontmostBundleID: String?,
        frontmostIcon: NSImage?,
        hotkeyProfile: HotkeyProfile?,
        recordingStartedAt: Date?,
        hotkeysPaused: Bool,
        actions: StatusMenuActions
    ) {
        self.appState = appState
        self.settings = appState.settings
        self.history = appState.history
        self.frontmostName = frontmostName
        self.frontmostBundleID = frontmostBundleID
        self.frontmostIcon = frontmostIcon
        self.hotkeyProfile = hotkeyProfile
        self.recordingStartedAt = recordingStartedAt
        self.hotkeysPaused = hotkeysPaused
        self.actions = actions
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView {
                VStack(spacing: 0) {
                    header(elapsedAt: context.date)
                    section("CAPTURE") {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)],
                            spacing: 5
                        ) {
                            ForEach(captureIntents) { intent in intentButton(intent) }
                        }
                    }
                    section("RECORDING") {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)],
                            spacing: 5
                        ) {
                            ForEach(recordingIntents) { intent in intentButton(intent, recording: true) }
                        }
                    }
                    profileSection
                    recentSection
                    footer
                }
                .padding(.bottom, 7)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: 448, height: 760)
        .background(StatusMenuColor.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func header(elapsedAt date: Date) -> some View {
        HStack(spacing: 11) {
            Group {
                if let frontmostIcon {
                    Image(nsImage: frontmostIcon)
                        .resizable()
                        .scaledToFit()
                        .padding(7)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(StatusMenuColor.accent)
                }
            }
            .frame(width: 32, height: 32)
            .background(StatusMenuColor.accent.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text("\(frontmostName) is in front")
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    if appState.isRecording {
                        badge("● \(elapsedText(at: date))", color: StatusMenuColor.recording)
                    } else if hotkeysPaused {
                        badge("HOTKEYS PAUSED", color: StatusMenuColor.tertiary)
                    } else if settings.shareSafeAutoRedactAfterCapture || settings.shareSafeRedactBeforeSharing {
                        badge("SHARESAFE", color: StatusMenuColor.success)
                    }
                }
                Text(profileLine)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let hotkeyProfile, !hotkeyProfile.hotkeys.isEmpty {
                badge("\(hotkeyProfile.hotkeys.count) overrides", color: StatusMenuColor.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { Divider().overlay(StatusMenuColor.border) }
    }

    private var profileLine: String {
        if hotkeyProfile != nil {
            return "HotkeyProfile · \(frontmostBundleID ?? "Unknown")"
        }
        return "HotkeyProfile.globalDefault · Default (all apps)"
    }

    private var captureIntents: [StatusMenuIntent] {
        [
            .init(id: "allInOne", label: "All-in-One", hint: "the HUD", symbol: "rectangle.on.rectangle", hotkey: .allInOne, run: actions.allInOne),
            .init(id: "captureArea", label: "Capture Area", hint: "drag a region", symbol: "rectangle.dashed", hotkey: .captureArea, run: actions.captureArea),
            .init(id: "captureWindow", label: "Capture Window", hint: "click a window", symbol: "macwindow", hotkey: .captureWindow, run: actions.captureWindow),
            .init(id: "captureScreen", label: "Full Screen", hint: "whole display", symbol: "rectangle.inset.filled", hotkey: .captureScreen, run: actions.captureScreen),
            .init(id: "captureLastRegion", label: "Last Region", hint: "repeat the last rect", symbol: "arrow.counterclockwise", hotkey: .captureLastRegion, run: actions.captureLastRegion),
            .init(id: "captureScrolling", label: "Scrolling Capture", hint: "stitch a long pane", symbol: "arrow.down.to.line", hotkey: .captureScrolling, run: actions.captureScrolling),
            .init(id: "captureOCR", label: "Capture Text (OCR)", hint: "text to clipboard", symbol: "text.viewfinder", hotkey: .captureOCR, run: actions.captureOCR)
        ]
    }

    private var recordingIntents: [StatusMenuIntent] {
        [
            .init(id: "recordArea", label: "Record Area", hint: "region video", symbol: "record.circle", hotkey: .recordArea, run: actions.recordArea),
            .init(id: "recordScreen", label: "Record Screen", hint: "whole display", symbol: "rectangle.inset.filled.and.person.filled", hotkey: .recordScreen, run: actions.recordScreen)
        ]
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(StatusMenuColor.tertiary)
                .padding(.leading, 3)
            content()
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }

    private func intentButton(_ intent: StatusMenuIntent, recording: Bool = false) -> some View {
        Button(action: intent.run) {
            HStack(spacing: 8) {
                Image(systemName: intent.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background((recording ? StatusMenuColor.recording : StatusMenuColor.accent).opacity(0.16))
                    .foregroundStyle(recording ? StatusMenuColor.recording : StatusMenuColor.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(intent.label)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Text(intent.hint)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(StatusMenuColor.secondary.opacity(0.7))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(hotkey(for: intent.hotkey))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(StatusMenuColor.tertiary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 49, alignment: .leading)
            .background(StatusMenuColor.surface2)
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(StatusMenuColor.border))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var profileSection: some View {
        section("CAPTURE PROFILE") {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    ForEach(CaptureProfile.builtIn) { profile in
                        Button {
                            actions.selectProfile(profile)
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName: profile.symbol)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(profile.name)
                                    .font(.system(size: 10, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(settings.activeCaptureProfileID == profile.id ? StatusMenuColor.background : StatusMenuColor.text)
                            .background(settings.activeCaptureProfileID == profile.id ? StatusMenuColor.accent : StatusMenuColor.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(settings.activeCaptureProfile.summary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(StatusMenuColor.secondary)
                    Text(settings.filenameTemplate)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(StatusMenuColor.tertiary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StatusMenuColor.surface2)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(StatusMenuColor.border))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }

    private var recentSection: some View {
        section("RECENT") {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Spacer()
                    Button("Open library", action: actions.showHistory)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(StatusMenuColor.accent)
                        .buttonStyle(.plain)
                }
                HStack(spacing: 6) {
                    ForEach(Array(history.items.prefix(4))) { item in
                        Button { actions.openRecent(item) } label: {
                            StatusMenuRecentCapture(item: item, url: history.primaryURL(for: item) ?? history.fileURL(for: item))
                        }
                        .buttonStyle(.plain)
                    }
                    if history.items.isEmpty {
                        Text("No captures yet")
                            .font(.system(size: 10.5))
                            .foregroundStyle(StatusMenuColor.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().overlay(StatusMenuColor.border)
            footerRow(symbol: "clock.arrow.circlepath", title: "Show History", key: hotkey(for: .showHistory), action: actions.showHistory)
            footerRow(symbol: "pencil.and.outline", title: "Editor", key: "⌘⇧E", action: actions.showEditor)
            footerRow(symbol: "gearshape", title: "Settings…", key: "⌘,", action: actions.showSettings)
            footerRow(symbol: hotkeysPaused ? "play.fill" : "pause.fill", title: hotkeysPaused ? "Resume hotkeys" : "Pause hotkeys", key: "", action: actions.toggleHotkeys)
            footerRow(symbol: "power", title: "Quit Aeroshot", key: "⌘Q", action: actions.quit)
        }
        .padding(.horizontal, 7)
        .padding(.top, 7)
    }

    private func footerRow(symbol: String, title: String, key: String, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(StatusMenuColor.tertiary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(StatusMenuColor.text)
                Spacer(minLength: 0)
                Text(key)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(StatusMenuColor.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .padding(.horizontal, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(color.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func hotkey(for action: HotkeyAction) -> String {
        settings.effectiveHotkeys(for: frontmostBundleID)[action]?.displayString ?? ""
    }

    private func elapsedText(at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(recordingStartedAt ?? date)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct StatusMenuRecentCapture: View {
    let item: HistoryItem
    let url: URL
    private let image: NSImage?

    init(item: HistoryItem, url: URL) {
        self.item = item
        self.url = url
        self.image = NSImage(contentsOf: url)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [StatusMenuColor.accent.opacity(0.32), StatusMenuColor.surface2],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: item.kind == .recording || item.kind == .gif ? "record.circle" : "doc")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StatusMenuColor.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(item.fileName.isEmpty ? item.kind.rawValue.capitalized : item.fileName)
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundStyle(StatusMenuColor.secondary)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StatusMenuColor.background.opacity(0.82))
        }
        .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56)
        .background(StatusMenuColor.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(StatusMenuColor.border))
    }
}

private enum StatusMenuColor {
    static let background = Color(red: 0.063, green: 0.075, blue: 0.098)
    static let surface2 = Color(red: 0.098, green: 0.110, blue: 0.133)
    static let text = Color(red: 0.929, green: 0.933, blue: 0.945)
    static let secondary = Color(red: 0.612, green: 0.631, blue: 0.671)
    static let tertiary = Color(red: 0.400, green: 0.420, blue: 0.459)
    static let accent = Color(red: 1.0, green: 0.541, blue: 0.420)
    static let recording = Color(red: 0.898, green: 0.282, blue: 0.302)
    static let success = Color(red: 0.373, green: 0.827, blue: 0.627)
    static let border = Color.white.opacity(0.075)
}
