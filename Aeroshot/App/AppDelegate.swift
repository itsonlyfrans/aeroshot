import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    lazy var automationRouter = AutomationRouter(host: self)

    private var statusItem: NSStatusItem?
    private var recordingObserver: AnyCancellable?
    private var workspaceObserver: NSObjectProtocol?

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

        recordingObserver = appState.$isRecording.sink { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateStatusItemAppearance()
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
        let atlasItem = NSMenuItem(title: "Atlas Workspace…", action: #selector(showAtlasWorkspace), keyEquivalent: "0")
        atlasItem.target = self
        appMenu.addItem(atlasItem)
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
                statusItem?.menu = buildMenu()
            }
            updateStatusItemAppearance()
        } else {
            tearDownStatusItem()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Aeroshot")
        item.menu = buildMenu()
        statusItem = item
    }

    private func tearDownStatusItem() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let hotkeys = appState.settings.hotkeys()

        func addItem(_ title: String, action: Selector, hotkey: Hotkey?, symbol: String? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if let hotkey {
                hotkey.applyToMenuItem(item, title: title)
            }
            if let symbol {
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
            menu.addItem(item)
        }

        addItem("All-in-One…", action: #selector(showAllInOne), hotkey: hotkeys[.allInOne], symbol: HotkeyAction.allInOne.symbol)
        menu.addItem(.separator())
        addItem("Capture Area", action: #selector(captureArea), hotkey: hotkeys[.captureArea], symbol: HotkeyAction.captureArea.symbol)
        addItem("Capture Window", action: #selector(captureWindow), hotkey: hotkeys[.captureWindow], symbol: HotkeyAction.captureWindow.symbol)
        addItem("Capture Full Screen", action: #selector(captureScreen), hotkey: hotkeys[.captureScreen], symbol: HotkeyAction.captureScreen.symbol)
        addItem("Capture Last Region", action: #selector(captureLastRegion), hotkey: hotkeys[.captureLastRegion], symbol: HotkeyAction.captureLastRegion.symbol)
        addItem("Scrolling Capture", action: #selector(captureScrolling), hotkey: hotkeys[.captureScrolling], symbol: HotkeyAction.captureScrolling.symbol)
        addItem("Capture Text (OCR)", action: #selector(captureOCR), hotkey: hotkeys[.captureOCR], symbol: HotkeyAction.captureOCR.symbol)
        menu.addItem(.separator())
        addItem("Record Area", action: #selector(recordArea), hotkey: hotkeys[.recordArea], symbol: HotkeyAction.recordArea.symbol)
        addItem("Record Screen", action: #selector(recordScreen), hotkey: hotkeys[.recordScreen], symbol: HotkeyAction.recordScreen.symbol)
        menu.addItem(.separator())
        addItem("History…", action: #selector(showHistory), hotkey: hotkeys[.showHistory], symbol: HotkeyAction.showHistory.symbol)
        addItem("Settings…", action: #selector(showSettings), hotkey: nil)
        addItem("Atlas Workspace…", action: #selector(showAtlasWorkspace), hotkey: nil, symbol: "square.grid.2x2")
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Aeroshot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
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
        if appState.settings.showInMenuBar {
            statusItem?.menu = buildMenu()
        }
    }

    private func perform(hotkeyAction: HotkeyAction) {
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
        appState.showHistoryWindow()
    }

    @objc private func showAtlasWorkspace() {
        appState.showAtlasWorkbench()
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

    private func updateStatusItemAppearance() {
        guard let button = statusItem?.button else { return }

        let symbolName: String
        if appState.isRecording {
            symbolName = "record.circle.fill"
        } else if !SettingsPermissions.allGranted {
            symbolName = "exclamationmark.shield.fill"
        } else {
            symbolName = "camera.viewfinder"
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Aeroshot")
        button.image = image

        if appState.isRecording {
            button.contentTintColor = .systemRed
        } else if !SettingsPermissions.allGranted {
            button.contentTintColor = .systemOrange
        } else {
            button.contentTintColor = nil
        }
    }
}
