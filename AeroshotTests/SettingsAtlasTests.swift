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
            "share.copy", "share.endpoint", "share.upload", "share.warn"
        ]
        let rowExpression = try NSRegularExpression(pattern: #"id:\s*\"([^\"]+)\""#)
        let range = NSRange(components.startIndex..., in: components)
        let rows = rowExpression.matches(in: components, range: range).compactMap {
            Range($0.range(at: 1), in: components).map { String(components[$0]) }
        }
        #expect(Set(rows) == expectedRows)
        #expect(Dictionary(grouping: rows, by: \.self).values.allSatisfy { $0.count == 1 })

        for binding in [
            "settings.setThumbnailAction(action, visible: !selected)",
            "toggle($settings.showThumbnailActionsAlways)",
            "settings.setThumbnailSwipeAction($0, fingers: settings.thumbnailSwipeFingerCount, direction: direction)",
            "toggle($settings.addOCRCapturesToHistory)"
        ] {
            #expect(components.contains(binding))
        }

        let expectedCatalogIDs: Set<String> = [
            "aspect-lock", "beautify-default", "capture-delay", "capture-profile", "clipboard", "click-highlight", "cloud-upload", "dock-presence", "editor-open", "filename-template", "format", "gif-fps", "hotkeys", "jpeg-quality", "last-region", "menu-bar-presence", "microphone", "ocr-history", "permissions", "recording-format", "reset-settings", "retina", "save-disk", "save-folder", "scrolling", "shortcuts-app", "sound", "system-audio", "thumb-duration", "thumbnail", "thumbnail-actions", "thumbnail-actions-always", "thumbnail-swipes", "webcam-overlay"
        ]
        #expect(Set(SettingsSearchEntry.catalog.map(\.id)) == expectedCatalogIDs)
        #expect(SettingsSearchEntry.catalog.allSatisfy { $0.atlasDestination != nil })

        for source in [navigation, window, model] {
            #expect(!source.contains("mediaLibrary"))
        }
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
}
