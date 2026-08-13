import Foundation
import Testing
@testable import Aeroshot

struct SettingsAtlasTests {
    @MainActor
    @Test func catalogContainsOnlySupportedCategories() {
        #expect(SettingsAtlasCategory.all.count == 10)
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

        let expectedRows: Set<String> = [
            "advanced.automation", "advanced.export", "advanced.reset",
            "capture.aspect", "capture.clipboard", "capture.delay", "capture.editor", "capture.freeze", "capture.last-region", "capture.ocr-history", "capture.retina", "capture.save", "capture.scroll", "capture.sound", "capture.sound-effect", "capture.thumbnail", "capture.thumbnail-actions", "capture.thumbnail-actions-always", "capture.thumbnail-duration", "capture.thumbnail-swipe-fingers", "capture.thumbnail-swipe.\\(settings.thumbnailSwipeFingerCount.rawValue).\\(direction.rawValue)",
            "editor.aspect", "editor.beautify", "editor.gradient", "editor.padding", "editor.radius", "editor.shadow",
            "export.destination", "export.image-format", "export.quality", "export.recording-template", "export.template",
            "general.dock", "general.menu-bar", "general.profile",
            "gif.fps", "gif.frames", "hotkey.\\(action.rawValue)", "permission.\\(title)",
            "privacy.before-share", "privacy.detection", "privacy.redaction",
            "rec.click-highlight", "rec.container", "rec.history", "rec.microphone", "rec.system-audio", "rec.webcam",
            "share.copy", "share.endpoint", "share.upload"
        ]
        let rows = try captures(in: components, pattern: #"id:\s*\"([^\"]+)\""#)
        #expect(Set(rows) == expectedRows)
        #expect(Dictionary(grouping: rows, by: \.self).values.allSatisfy { $0.count == 1 })
        #expect(components.contains(#"row("Smart image detection", "Find sensitive information in image captures.", id: "privacy.detection")"#))
        #expect(components.contains(#"row("Protect shared images", "Redact flagged information before copying, sharing, or automatically uploading image captures.", id: "privacy.before-share")"#))
        #expect(!components.contains("id: \"share.warn\""))

        let expectedDestinations: [String: SettingsAtlasSearchDestination] = [
            "capture-delay": .init(categoryID: .capture, rowID: "capture.delay"),
            "last-region": .init(categoryID: .capture, rowID: "capture.last-region"),
            "aspect-lock": .init(categoryID: .capture, rowID: "capture.aspect"),
            "capture-profile": .init(categoryID: .general, rowID: "general.profile"),
            "shortcuts-app": .init(categoryID: .advanced, rowID: "advanced.automation"),
            "clipboard": .init(categoryID: .capture, rowID: "capture.clipboard"),
            "save-disk": .init(categoryID: .capture, rowID: "capture.save"),
            "thumbnail": .init(categoryID: .capture, rowID: "capture.thumbnail"),
            "thumbnail-actions": .init(categoryID: .capture, rowID: "capture.thumbnail-actions"),
            "thumbnail-actions-always": .init(categoryID: .capture, rowID: "capture.thumbnail-actions-always"),
            "sound": .init(categoryID: .capture, rowID: "capture.sound"),
            "thumb-duration": .init(categoryID: .capture, rowID: "capture.thumbnail-duration"),
            "thumbnail-swipes": .init(categoryID: .capture, rowID: "capture.thumbnail-swipe-fingers"),
            "save-folder": .init(categoryID: .export, rowID: "export.destination"),
            "format": .init(categoryID: .export, rowID: "export.image-format"),
            "jpeg-quality": .init(categoryID: .export, rowID: "export.quality"),
            "retina": .init(categoryID: .capture, rowID: "capture.retina"),
            "filename-template": .init(categoryID: .export, rowID: "export.template"),
            "cloud-upload": .init(categoryID: .sharingUploads, rowID: "share.upload"),
            "hotkeys": .init(categoryID: .hotkeys, rowID: "hotkey.allInOne"),
            "recording-format": .init(categoryID: .screenRecording, rowID: "rec.container"),
            "system-audio": .init(categoryID: .screenRecording, rowID: "rec.system-audio"),
            "microphone": .init(categoryID: .screenRecording, rowID: "rec.microphone"),
            "webcam-overlay": .init(categoryID: .screenRecording, rowID: "rec.webcam"),
            "click-highlight": .init(categoryID: .screenRecording, rowID: "rec.click-highlight"),
            "scrolling": .init(categoryID: .capture, rowID: "capture.scroll"),
            "gif-fps": .init(categoryID: .gifRecording, rowID: "gif.fps"),
            "editor-open": .init(categoryID: .capture, rowID: "capture.editor"),
            "beautify-default": .init(categoryID: .screenshotEditor, rowID: "editor.beautify"),
            "permissions": .init(categoryID: .privacy, rowID: "permission.Screen Recording"),
            "menu-bar-presence": .init(categoryID: .general, rowID: "general.menu-bar"),
            "dock-presence": .init(categoryID: .general, rowID: "general.dock"),
            "reset-settings": .init(categoryID: .advanced, rowID: "advanced.reset"),
            "ocr-history": .init(categoryID: .capture, rowID: "capture.ocr-history")
        ]
        let catalogIDs = try captures(in: navigation, pattern: #"\.init\(id:\s*\"([^\"]+)\""#)
        #expect(Set(catalogIDs) == Set(expectedDestinations.keys))
        #expect(catalogIDs.count == expectedDestinations.count)
        #expect(Set(SettingsSearchEntry.catalog.map(\.id)) == Set(expectedDestinations.keys))
        #expect(SettingsSearchEntry.catalog.allSatisfy { expectedDestinations[$0.id] == $0.atlasDestination })
        #expect(expectedDestinations.values.allSatisfy { rows.contains($0.rowID) || $0.rowID.hasPrefix("hotkey.") || $0.rowID.hasPrefix("permission.") })

        let expectedCategories: Set<String> = ["capture", "screenRecording", "gifRecording", "screenshotEditor", "export", "sharingUploads", "general", "hotkeys", "privacy", "advanced"]
        let categoryIDs = try captures(in: model, pattern: #"\.init\(id:\s*\.([A-Za-z]+),"#)
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
        #expect(permissionTitles.sorted() == ["Accessibility", "Accessibility", "Camera", "Microphone", "Screen Recording"])
        #expect(components.contains("id: \"permission.\\(title)\""))

        let expectedHotkeyActions: Set<String> = ["allInOne", "captureArea", "captureLastRegion", "captureOCR", "captureScreen", "captureScrolling", "captureWindow", "recordArea", "recordScreen", "showHistory"]
        #expect(Set(HotkeyAction.allCases.map(\.rawValue)) == expectedHotkeyActions)
        #expect(components.contains("ForEach(HotkeyAction.allCases)"))

        let expectedThumbnailActions: Set<String> = ["copy", "edit", "ocr", "pin", "save", "share", "shareSafe"]
        let expectedSwipeActions: Set<String> = ["copy", "dismiss", "edit", "keep", "none", "ocr", "pin", "save", "share", "shareSafe", "tuck"]
        #expect(Set(ThumbnailAction.allCases.map(\.rawValue)) == expectedThumbnailActions)
        #expect(Set(ThumbnailGestureAction.allCases.map(\.rawValue)) == expectedSwipeActions)
        #expect(Set(ThumbnailSwipeDirection.allCases.map(\.rawValue)) == ["down", "left", "right", "up"])
        #expect(Set(ThumbnailSwipeFingerCount.allCases.map(\.rawValue)) == [2, 3])

        for binding in [
            "settings.setThumbnailAction(action, visible: !selected)",
            "toggle($settings.showThumbnailActionsAlways)",
            "settings.setThumbnailSwipeAction($0, fingers: settings.thumbnailSwipeFingerCount, direction: direction)",
            "toggle($settings.addOCRCapturesToHistory)"
        ] {
            #expect(components.contains(binding))
        }

        let expectedToggleIDs: Set<String> = ["clipboard", "click-highlight", "dock-presence", "editor-open", "menu-bar-presence", "microphone", "ocr-history", "save-disk", "sound", "system-audio", "thumbnail", "thumbnail-actions-always", "webcam-overlay"]
        let expectedValueIDs = expectedToggleIDs.union(["capture-delay", "format", "recording-format", "save-folder", "thumbnail-actions"])
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
        #expect(SettingsAtlasTerritoryView.sectionTitles(for: .capture) == ["Capture", "After capture"])
        #expect(SettingsAtlasTerritoryView.sectionTitles(for: .advanced) == ["Automation", "Configuration"])
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
        #expect(source.contains("quit: { [weak self] in self?.runStatusAction { NSApp.terminate(nil) } }"))
        #expect(source.contains("private func tearDownStatusItem() {\n        closeStatusPopover()"))
        let start = try #require(source.range(of: "private func runStatusAction"))
        let end = try #require(source.range(of: "@objc private func toggleStatusPopover", range: start.upperBound..<source.endIndex))
        let action = source[start.lowerBound..<end.lowerBound]
        #expect(action.contains("DispatchQueue.main.async"))
        #expect(action.range(of: "closeStatusPopover()")!.lowerBound < action.range(of: "action()")!.lowerBound)
    }

    @Test func settingsRowsLabelControlsAndHotkeysRejectConflicts() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appending(path: "Aeroshot/Settings/Atlas/SettingsAtlasComponents.swift"))

        #expect(source.contains("control().accessibilityLabel(Text(title))"))
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
        #expect(source.contains("PasteboardWriter.copy(image: copyOutput, fileURL: copyFileURL)"))
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
