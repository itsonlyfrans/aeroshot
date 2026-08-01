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
}
