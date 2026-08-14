import Foundation
import Testing
@testable import Aeroshot

struct SettingsAtlasTests {
    @MainActor
    @Test func onboardingStatusNeverClaimsReadyWithoutScreenPermission() {
        #expect(OnboardingReadiness(screenRecordingGranted: true).title == "Ready")
        #expect(OnboardingReadiness(screenRecordingGranted: false).title == "Needs Attention")
    }

    @MainActor
    @Test func catalogContainsOnlySupportedCategories() {
        #expect(SettingsAtlasCategory.all.count == SettingsAtlasCategoryID.allCases.count)
        #expect(SettingsAtlasBand.allCases.allSatisfy { !SettingsAtlasCategory.categories(in: $0).isEmpty })
        #expect(SettingsAtlasCategory.category(for: .capture).pane == .capture)
        #expect(SettingsAtlasCategory.category(for: .hotkeys).pane == .shortcuts)
    }

    @MainActor
    @Test func atlasCatalogMatchesBackedRowsAndActions() throws {
        let sources = try atlasSources()
        let components = try #require(sources["SettingsAtlasComponents.swift"])
        let navigation = try #require(sources["SettingsNavigation.swift"])
        let window = try #require(sources["SettingsAtlasWindow.swift"])
        let model = try #require(sources["SettingsAtlasModel.swift"])

        let requiredRows: Set<String> = [
            "advanced.automation", "advanced.export", "advanced.reset",
            "capture.aspect", "capture.clipboard", "capture.delay", "capture.editor", "capture.freeze", "capture.last-region", "capture.retina", "capture.save", "capture.scroll", "capture.sound", "capture.sound-effect", "capture.thumbnail", "capture.thumbnail-actions", "capture.thumbnail-actions-always", "capture.thumbnail-duration", "capture.thumbnail-swipe-fingers", "capture.thumbnail-swipe.\\(settings.thumbnailSwipeFingerCount.rawValue).\\(direction.rawValue)",
            "editor.aspect", "editor.beautify", "editor.gradient", "editor.padding", "editor.radius", "editor.shadow",
            "export.destination", "export.image-format", "export.quality", "export.recording-template", "export.template",
            "general.dock", "general.menu-bar", "general.profile",
            "gif.fps", "gif.frames", "hotkey.\\(action.rawValue)", "library.ocr", "permission.\\(title)",
            "capture.auto-redact", "capture.share-safe", "privacy.before-share", "privacy.detection", "privacy.redaction", "share.warn",
            "rec.click-highlight", "rec.container", "rec.history", "rec.microphone", "rec.system-audio", "rec.webcam",
            "share.copy", "share.endpoint", "share.upload"
        ]
        let rows = try captures(in: components, pattern: #"id:\s*\"([^\"]+)\""#)
        #expect(requiredRows.isSubset(of: Set(rows)))
        #expect(Dictionary(grouping: rows, by: \.self).values.allSatisfy { $0.count == 1 })
        #expect(components.contains(#"row("Sensitive-information detection", "Emails, tokens, card numbers, and addresses", id: "privacy.detection")"#))
        #expect(components.contains(#"row("Auto-redact captures", "Scan and redact saved and copied captures automatically", id: "capture.auto-redact")"#))
        #expect(components.contains(#"row("Auto-redact Share Safe", "When off, Share Safe asks before each flagged original. When on, it shares a redacted copy.", id: "capture.share-safe")"#))
        #expect(components.contains(#"row("Protect automatic uploads", "Redact flagged captures before a background upload", id: "share.warn")"#))

        let catalogIDs = try captures(in: navigation, pattern: #"\.init\(id:\s*\"([^\"]+)\""#)
        #expect(catalogIDs.count == Set(catalogIDs).count)
        #expect(Set(SettingsSearchEntry.catalog.map(\.id)) == Set(catalogIDs))
        #expect(SettingsSearchEntry.catalog.allSatisfy { entry in
            guard let destination = entry.atlasDestination else { return false }
            return rows.contains(destination.rowID)
                || destination.rowID.hasPrefix("hotkey.")
                || destination.rowID.hasPrefix("permission.")
        })

        let expectedCategories = Set(SettingsAtlasCategoryID.allCases.map(\.rawValue))
        let categoryIDs = try captures(in: model, pattern: #"\.init\(\s*id:\s*\.([A-Za-z]+),"#)
        #expect(Set(categoryIDs) == expectedCategories)
        #expect(categoryIDs.count == expectedCategories.count)
        #expect(Set(SettingsAtlasCategory.all.map { $0.id.rawValue }) == expectedCategories)
        #expect(window.contains("case let .category(id):"))
        #expect(window.contains("route = .category(destination.categoryID)"))
        #expect(window.contains("highlightedRowID = destination.rowID"))
        #expect(window.contains("SettingsAtlasTerritoryView(category: category.id, highlightedRowID: $highlightedRowID)"))

        let expectedPermissions: Set<String> = ["Accessibility", "Camera", "Microphone", "Screen Recording"]
        let permissionTitles = try captures(in: components, pattern: #"permissionRow\(\"([^\"]+)\""#)
        #expect(Set(permissionTitles) == expectedPermissions)
        #expect(permissionTitles.sorted() == ["Accessibility", "Camera", "Microphone", "Screen Recording"])
        #expect(components.contains("id: \"permission.\\(title)\""))

        let expectedHotkeyActions: Set<String> = ["allInOne", "captureArea", "captureLastRegion", "captureOCR", "captureScreen", "captureScrolling", "captureWindow", "recordArea", "recordScreen", "showHistory"]
        #expect(Set(HotkeyAction.allCases.map(\.rawValue)) == expectedHotkeyActions)
        #expect(components.components(separatedBy: "HotkeyAction.allCases.filter").count == 3)

        let expectedThumbnailActions: Set<String> = ["copy", "edit", "ocr", "pin", "reveal", "save", "share", "shareSafe"]
        let expectedSwipeActions: Set<String> = ["copy", "dismiss", "edit", "keep", "none", "ocr", "pin", "reveal", "save", "share", "shareSafe", "tuck"]
        #expect(Set(ThumbnailAction.allCases.map(\.rawValue)) == expectedThumbnailActions)
        #expect(Set(ThumbnailGestureAction.allCases.map(\.rawValue)) == expectedSwipeActions)
        #expect(Set(ThumbnailSwipeDirection.allCases.map(\.rawValue)) == ["down", "left", "right", "up"])
        #expect(Set(ThumbnailSwipeFingerCount.allCases.map(\.rawValue)) == [2, 3])

        for binding in [
            "settings.setThumbnailAction(action, visible: !selected)",
            "toggle($settings.showThumbnailActionsAlways)",
            "settings.setThumbnailSwipeAction($0, fingers: fingers, direction: direction)",
            "toggle($settings.addOCRCapturesToHistory)"
        ] {
            #expect(components.contains(binding))
        }

        let expectedToggleIDs: Set<String> = ["clipboard", "click-highlight", "dock-presence", "editor-open", "menu-bar-presence", "microphone", "ocr-history", "save-disk", "sound", "system-audio", "thumbnail", "webcam-overlay"]
        let expectedValueIDs = expectedToggleIDs.union(["capture-delay", "format", "recording-format", "save-folder"])
        let toggleableIDs = try captures(in: functionSource(window, named: "canToggle"), pattern: #"\"([^\"]+)\""#)
        let valueIDs = try captures(in: functionSource(window, named: "value"), pattern: #"case\s+\"([^\"]+)\":"#)
        let toggledIDs = try captures(in: functionSource(window, named: "toggle"), pattern: #"case\s+\"([^\"]+)\":"#)
        #expect(Set(toggleableIDs) == expectedToggleIDs)
        #expect(toggleableIDs.count == expectedToggleIDs.count)
        #expect(Set(valueIDs) == expectedValueIDs)
        #expect(valueIDs.count == expectedValueIDs.count)
        #expect(Set(toggledIDs) == expectedToggleIDs)
        #expect(toggledIDs.count == expectedToggleIDs.count)

        let unsupportedPermission = components.replacingOccurrences(of: "permissionRow(\"Camera\"", with: "permissionRow(\"Bluetooth\"")
        #expect(Set(try captures(in: unsupportedPermission, pattern: #"permissionRow\(\"([^\"]+)\""#)) != expectedPermissions)
    }

    @MainActor
    @Test func paletteDestinationsPointToRenderedRows() throws {
        let source = try #require(atlasSources()["SettingsAtlasComponents.swift"])
        let expression = try NSRegularExpression(pattern: #"id:\s*\"([^\"]+)\""#)
        let range = NSRange(source.startIndex..., in: source)
        let staticRows = Set(expression.matches(in: source, range: range).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        })

        #expect(SettingsSearchEntry.catalog.allSatisfy { entry in
            guard let destination = entry.atlasDestination else { return false }
            return staticRows.contains(destination.rowID)
                || destination.rowID.hasPrefix("hotkey.")
                || destination.rowID.hasPrefix("permission.")
        })
    }

    @MainActor
    @Test func atlasNavigationListsRenderedSections() {
        #expect(SettingsAtlasTerritoryView.sectionTitles(for: .capture) == ["Modes & memory", "Timing", "Cursor & chrome", "Selection surface", "Displays & resolution", "After capture"])
        #expect(SettingsAtlasTerritoryView.sectionTitles(for: .advanced) == ["Performance", "Storage", "Diagnostics", "Extensibility", "Configuration"])
    }

    @Test func settingsChangesApplyAppPresenceImmediately() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appending(path: "Aeroshot/App/AppDelegate.swift"))
        let start = try #require(source.range(of: "settingsObserver ="))
        let end = try #require(source.range(of: "workspaceObserver =", range: start.upperBound..<source.endIndex))

        #expect(source[start.lowerBound..<end.lowerBound].contains("self?.applyAppPresence()"))
    }

    @Test func statusMenuActionsFinishMouseTrackingBeforeClosing() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appending(path: "Aeroshot/App/AppDelegate.swift"))

        #expect(source.contains("button.sendAction(on: [.leftMouseDown])"))
        #expect(source.contains("NSStatusBar.system.removeStatusItem(item)"))
        #expect(source.contains("quit: { [weak self] in self?.runStatusAction { self?.quit() } }"))
        #expect(source.contains("private func tearDownStatusItem() {\n        closeStatusPopover()"))
        let start = try #require(source.range(of: "private func runStatusAction"))
        let end = try #require(source.range(of: "@objc private func toggleStatusPopover", range: start.upperBound..<source.endIndex))
        let action = source[start.lowerBound..<end.lowerBound]
        #expect(action.contains("DispatchQueue.main.async"))
        #expect(action.range(of: "closeStatusPopover()")!.lowerBound < action.range(of: "action()")!.lowerBound)

        let quit = try #require(source.range(of: "@objc private func quit()"))
        let quitEnd = try #require(source.range(of: "private func refreshStatusPopover", range: quit.upperBound..<source.endIndex))
        let quitBody = source[quit.lowerBound..<quitEnd.lowerBound]
        #expect(quitBody.contains("NSApp.terminate(nil)"))
        #expect(!quitBody.contains("tearDownStatusItem()"))
        #expect(source.contains("func applicationWillTerminate(_ notification: Notification) {\n        tearDownStatusItem()"))

        let rebindStart = try #require(source.range(of: "private func scheduleHotkeyRebindIfNeeded"))
        let rebindEnd = try #require(source.range(of: "func applicationShouldHandleReopen", range: rebindStart.upperBound..<source.endIndex))
        let rebind = source[rebindStart.lowerBound..<rebindEnd.lowerBound]
        #expect(rebind.contains("guard statusPopover?.isShown != true || bundleID != Bundle.main.bundleIdentifier else { return }"))
        #expect(!rebind.contains("NSWorkspace.shared.frontmostApplication"))
        #expect(!rebind.contains("refreshStatusPopover()"))
        #expect(rebind.contains("rebindHotkeys(refreshPopover: false)"))
        #expect(source.contains("notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication"))
    }

    @Test func settingsRowsLabelControlsAndHotkeysRejectConflicts() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appending(path: "Aeroshot/Settings/Atlas/SettingsAtlasComponents.swift"))

        #expect(source.contains(".environment(\\.settingsAtlasControlTitle, title)"))
        #expect(source.contains(".accessibilityLabel(settingTitle ?? \"Setting\")"))
        #expect(source.contains("settings.conflictingAction(for: hotkey, excluding: action)"))
        #expect(source.contains("Text(errorMessage).font(.caption2)"))
    }

    @Test func redactBeforeSharingDoesNotChangeLocalCaptureOutput() {
        #expect(!AppState.captureOutputNeedsRedaction(
            autoRedact: false,
            redactBeforeSharing: true,
            isSharing: false
        ))
        #expect(AppState.captureOutputNeedsRedaction(
            autoRedact: false,
            redactBeforeSharing: true,
            isSharing: true
        ))
        #expect(AppState.captureOutputNeedsRedaction(
            autoRedact: true,
            redactBeforeSharing: false,
            isSharing: false
        ))
    }

    @Test func protectedClipboardOutputDoesNotAttachTheLocalFile() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appending(path: "Aeroshot/App/AppState.swift"))

        #expect(source.contains("let copyFileURL = protectedOutput == nil ? savedURL : nil"))
        #expect(source.contains("sourceScale: sourceScale"))
    }

    @MainActor
    @Test func gifSearchOmitsAudioControlsWithoutChangingMp4Preferences() {
        let defaults = UserDefaults.standard
        let originalFormat = defaults.object(forKey: "recordingFormatRaw")
        let originalSystemAudio = defaults.object(forKey: "recordSystemAudio")
        let originalMicrophone = defaults.object(forKey: "recordMicrophone")
        defer {
            for (key, value) in [
                ("recordingFormatRaw", originalFormat),
                ("recordSystemAudio", originalSystemAudio),
                ("recordMicrophone", originalMicrophone),
            ] {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        let settings = SettingsStore()
        settings.recordingFormat = .mp4
        settings.recordSystemAudio = true
        settings.recordMicrophone = true

        let mp4AudioEntries = SettingsSearchEntry.results(for: "audio", recordingFormat: .mp4).map(\.id)
        let gifAudioEntries = SettingsSearchEntry.results(for: "audio", recordingFormat: .gif).map(\.id)
        #expect(mp4AudioEntries.contains("system-audio"))
        #expect(mp4AudioEntries.contains("microphone"))
        #expect(!gifAudioEntries.contains("system-audio"))
        #expect(!gifAudioEntries.contains("microphone"))
        settings.recordingFormat = .gif
        settings.recordingFormat = .mp4
        #expect(settings.recordSystemAudio)
        #expect(settings.recordMicrophone)
        #expect(SettingsSearchEntry.results(for: "audio", recordingFormat: .mp4).map(\.id) == mp4AudioEntries)
    }

    private func atlasSources() throws -> [String: String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let files = [
            "Aeroshot/Settings/Atlas/SettingsAtlasComponents.swift",
            "Aeroshot/Settings/Atlas/SettingsAtlasModel.swift",
            "Aeroshot/Settings/Atlas/SettingsAtlasWindow.swift",
            "Aeroshot/Settings/Design/SettingsNavigation.swift"
        ]
        return try Dictionary(uniqueKeysWithValues: files.map { path in
            (URL(fileURLWithPath: path).lastPathComponent, try String(contentsOf: root.appending(path: path)))
        })
    }

    private func captures(in source: String, pattern: String) throws -> [String] {
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..., in: source)
        return expression.matches(in: source, range: range).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        }
    }

    private func functionSource(_ source: String, named name: String) -> String {
        guard let start = source.range(of: "private func \(name)(") else { return "" }
        let remainder = source[start.lowerBound...]
        guard let end = remainder.dropFirst().range(of: "\n    private ") else { return String(remainder) }
        return String(remainder[..<end.lowerBound])
    }

    @MainActor
    @Test func paletteSearchRoutesToTheExactAtlasRow() {
        let destination = SettingsSearchEntry.catalog.first { $0.id == "clipboard" }?.atlasDestination

        #expect(destination == .init(categoryID: .capture, rowID: "capture.clipboard"))
    }

    @MainActor
    @Test func everyPaletteSettingHasAnAtlasDestination() {
        #expect(SettingsSearchEntry.catalog.allSatisfy { $0.atlasDestination != nil })
    }

    @MainActor
    @Test func paletteResultDetailsNameTheAtlasDestination() {
        let detail = SettingsSearchEntry.catalog.first { $0.id == "shortcuts-app" }?.atlasResultDetail

        #expect(detail == "Advanced · Shortcuts and AppleScript triggers")
    }
}
