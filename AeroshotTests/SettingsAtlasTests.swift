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
    @Test func everyPaletteSettingHasAnAtlasDestination() {
        #expect(SettingsSearchEntry.catalog.allSatisfy { $0.atlasDestination != nil })
    }

    @MainActor
    @Test func paletteDestinationsPointToRenderedRows() throws {
        let source = try atlasSource()
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
    @Test func atlasRowsUseTheVerifiedAllowlist() throws {
        let source = try atlasSource()
        let expression = try NSRegularExpression(pattern: #"id:\s*\"([^\"]+)\""#)
        let range = NSRange(source.startIndex..., in: source)
        let ids = Set(expression.matches(in: source, range: range).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        })

        #expect(ids == Set([
            "advanced.automation", "advanced.export", "advanced.reset",
            "capture.aspect", "capture.clipboard", "capture.delay", "capture.editor", "capture.freeze", "capture.last-region", "capture.retina", "capture.save", "capture.scroll", "capture.sound", "capture.sound-effect", "capture.thumbnail", "capture.thumbnail-duration", "capture.thumbnail-swipe-fingers",
            "editor.aspect", "editor.beautify", "editor.gradient", "editor.padding", "editor.radius", "editor.shadow",
            "export.destination", "export.image-format", "export.quality", "export.recording-template", "export.template",
            "general.dock", "general.menu-bar", "general.profile",
            "gif.fps", "gif.frames", "hotkey.\\(action.rawValue)", "permission.\\(title)",
            "privacy.before-share", "privacy.detection", "privacy.redaction",
            "rec.click-highlight", "rec.container", "rec.history", "rec.microphone", "rec.system-audio", "rec.webcam",
            "share.copy", "share.endpoint", "share.upload", "share.warn"
        ]))
    }

    @MainActor
    @Test func atlasNavigationListsRenderedSections() {
        #expect(SettingsAtlasTerritoryView.sectionTitles(for: .capture) == ["Capture", "After capture"])
        #expect(SettingsAtlasTerritoryView.sectionTitles(for: .advanced) == ["Automation", "Configuration"])
    }

    private func atlasSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: "Aeroshot/Settings/Atlas/SettingsAtlasComponents.swift"))
    }
}
