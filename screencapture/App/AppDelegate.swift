import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.settings.sanitizeStoredHotkeys()
        setupMainMenu()
        setupStatusItem()
        HotkeyManager.requestInputMonitoringAccess()
        registerHotkeys()
        Task { await appState.permissions.ensurePermission() }
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
        appMenu.addItem(NSMenuItem(title: "Quit ScreenCapture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let captureMenu = NSMenu(title: "Capture")
        let captureItem = NSMenuItem(title: "Capture", action: nil, keyEquivalent: "")
        captureItem.submenu = captureMenu
        mainMenu.addItem(captureItem)

        let hotkeys = appState.settings.hotkeys()
        func addCaptureItem(_ title: String, action: Selector, actionKey: HotkeyAction) {
            let hk = hotkeys[actionKey]
            let item = NSMenuItem(title: title, action: action, keyEquivalent: hk?.menuKeyEquivalent ?? "")
            item.target = self
            if let hk { item.keyEquivalentModifierMask = hk.nsModifierMask }
            item.image = NSImage(systemSymbolName: actionKey.symbol, accessibilityDescription: nil)
            captureMenu.addItem(item)
        }

        addCaptureItem("All-in-One…", action: #selector(showAllInOne), actionKey: .allInOne)
        captureMenu.addItem(.separator())
        addCaptureItem("Capture Area", action: #selector(captureArea), actionKey: .captureArea)
        addCaptureItem("Capture Window", action: #selector(captureWindow), actionKey: .captureWindow)
        addCaptureItem("Capture Full Screen", action: #selector(captureScreen), actionKey: .captureScreen)
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

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenCapture")
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let hotkeys = appState.settings.hotkeys()

        func addItem(_ title: String, action: Selector, hotkey: Hotkey?, symbol: String? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: hotkey?.menuKeyEquivalent ?? "")
            item.target = self
            if let hotkey {
                item.keyEquivalentModifierMask = hotkey.nsModifierMask
                item.toolTip = hotkey.displayString
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
        addItem("Scrolling Capture", action: #selector(captureScrolling), hotkey: hotkeys[.captureScrolling], symbol: HotkeyAction.captureScrolling.symbol)
        addItem("Capture Text (OCR)", action: #selector(captureOCR), hotkey: hotkeys[.captureOCR], symbol: HotkeyAction.captureOCR.symbol)
        menu.addItem(.separator())
        addItem("Record Area", action: #selector(recordArea), hotkey: hotkeys[.recordArea], symbol: HotkeyAction.recordArea.symbol)
        addItem("Record Screen", action: #selector(recordScreen), hotkey: hotkeys[.recordScreen], symbol: HotkeyAction.recordScreen.symbol)
        menu.addItem(.separator())
        addItem("History…", action: #selector(showHistory), hotkey: hotkeys[.showHistory], symbol: HotkeyAction.showHistory.symbol)
        addItem("Settings…", action: #selector(showSettings), hotkey: nil)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit ScreenCapture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    // MARK: - Hotkeys

    private func registerHotkeys() {
        let hotkeys = appState.settings.hotkeys()
        for (action, hotkey) in hotkeys {
            HotkeyManager.shared.register(action: action, hotkey: hotkey) { [weak self] in
                self?.perform(hotkeyAction: action)
            }
        }

        guard !HotkeyManager.hasInputMonitoringAccess else { return }

        let alert = NSAlert()
        alert.messageText = "Enable Input Monitoring for Global Shortcuts"
        alert.informativeText = """
            Shortcuts like ⌘Space only work in the background when ScreenCapture has Input Monitoring access (same permission CleanShot and Longshot use).

            Open System Settings → Privacy & Security → Input Monitoring, enable ScreenCapture, then relaunch.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            HotkeyManager.openInputMonitoringSettings()
        }
    }

    func rebindHotkeys() {
        HotkeyManager.shared.unregisterAll()
        registerHotkeys()
        setupMainMenu()
        statusItem?.menu = buildMenu()
    }

    private func perform(hotkeyAction: HotkeyAction) {
        switch hotkeyAction {
        case .captureArea: captureArea()
        case .captureWindow: captureWindow()
        case .captureScreen: captureScreen()
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
}
