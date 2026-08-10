import Foundation
import Testing
@testable import Aeroshot

struct SettingsAtlasTests {
    @MainActor
    @Test func catalogCoversTheFourAtlasBands() {
        #expect(SettingsAtlasCategory.all.count == 15)
        #expect(SettingsAtlasBand.allCases.allSatisfy { !SettingsAtlasCategory.categories(in: $0).isEmpty })
        #expect(SettingsAtlasCategory.category(for: .capture).pane == .capture)
        #expect(SettingsAtlasCategory.category(for: .hotkeys).pane == .shortcuts)
    }

    @MainActor
    @Test func liveChipsReflectTheRealSettingsStore() {
        let settings = SettingsStore()
        let chips = SettingsAtlasCategory.category(for: .capture).liveChips(settings: settings)

        #expect(chips.count == 3)
        #expect(chips.contains { !$0.isEmpty })
    }

    @MainActor
    @Test func paletteSearchKeepsSettingEntriesReachable() {
        let results = SettingsSearchEntry.results(for: "clipboard")

        #expect(results.contains { $0.id == "clipboard" })
        #expect(SettingsAtlasRoute.category(.capture) != .atlas)
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

    @Test func atlasDoesNotAdvertiseUnavailableExportOrUploadProtection() throws {
        let source = try atlasSource()
        let model = try atlasModelSource()
        let exportContent = try section(named: "exportContent", in: source)
        let privacyContent = try section(named: "privacyContent", in: source)

        for label in [
            "Export presets",
            "Show preset picker on export",
        ] {
            #expect(!exportContent.contains(label))
        }
        for label in [
            "Local-only mode",
            "Block uploads on untrusted networks",
            "Encrypt uploads at rest",
        ] {
            #expect(!privacyContent.contains(label))
        }
        let atlas = (source + model).lowercased()
        for claim in [
            "export preset",
            "local-only",
            "expiry",
            "password",
            "connected services",
            "upload history",
            "retry failed",
        ] {
            #expect(!atlas.contains(claim))
        }
    }

    private func atlasSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: "Aeroshot/Settings/Atlas/SettingsAtlasComponents.swift"))
    }

    private func atlasModelSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: "Aeroshot/Settings/Atlas/SettingsAtlasModel.swift"))
    }

    private func section(named name: String, in source: String) throws -> Substring {
        let start = try #require(source.range(of: "private var \(name)"))
        let end = source.range(of: "    @ViewBuilder", range: start.upperBound..<source.endIndex)?.lowerBound ?? source.endIndex
        return source[start.lowerBound..<end]
    }
}
