import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private var statusItem: NSStatusItem?
    private var recordingObserver: AnyCancellable?
    private var workspaceObserver: NSObjectProtocol?
    private var didShowInputMonitoringGuideThisSession = false

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Aeroshot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

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

        guard !HotkeyManager.hasInputMonitoringAccess else { return }
        guard !appState.settings.hasDismissedInputMonitoringGuide else { return }
        guard !didShowInputMonitoringGuideThisSession else { return }
        didShowInputMonitoringGuideThisSession = true

        let alert = NSAlert()
        alert.messageText = "Enable Input Monitoring for Global Shortcuts"
        alert.informativeText = """
            Shortcuts like ⌘Space only work in the background when Aeroshot has Input Monitoring access (same permission CleanShot and Longshot use).

            Open System Settings → Privacy & Security → Input Monitoring, enable Aeroshot, then relaunch.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            HotkeyManager.openInputMonitoringSettings()
        default:
            appState.settings.hasDismissedInputMonitoringGuide = true
        }
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

    @objc func showSettings() {
        appState.showSettingsWindow()
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem?.button else { return }

        let symbolName: String
        if appState.isRecording {
            symbolName = "record.circle.fill"
        } else if !SettingsPermissions.allGranted {
            symbolName = "camera.viewfinder"
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
