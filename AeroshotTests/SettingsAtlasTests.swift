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
            "single switch",
        ] {
            #expect(!atlas.contains(claim))
        }
    }

    @Test func atlasPrivacyDoesNotShowUnboundStaticStatuses() throws {
        let privacyContent = try section(named: "privacyContent", in: atlasSource())
        let content = String(privacyContent)

        #expect(!content.contains("Crash reports"))

        let staticStatusRow = try NSRegularExpression(
            pattern: #"row\(\"[^\"]+\",\s*\"[^\"]*\",\s*id:\s*\"privacy\.[^\"]+\"\)\s*\{\s*value\(\"(?:On|Off|None configured)\"\)\s*\}"#
        )
        let range = NSRange(content.startIndex..., in: content)
        #expect(staticStatusRow.firstMatch(in: content, range: range) == nil)
    }

    @Test func atlasDoesNotAdvertiseUnsupportedLifecycleOrCacheControls() throws {
        let source = try atlasSource()
        let model = try atlasModelSource()
        let libraryContent = try section(named: "mediaLibraryContent", in: source)
        let exportContent = try section(named: "exportContent", in: source)
        let advancedContent = try section(named: "advancedContent", in: source)

        for claim in [
            "Retention",
            "Trash retention",
            "Delete temporary files on quit",
        ] {
            #expect(!libraryContent.contains(claim))
        }
        for claim in [
            "Automatic cleanup of scratch renders",
            "Memory ceiling",
            "Cache limit",
            "Temporary directory",
            "Clear cache on quit",
        ] {
            #expect(!exportContent.contains(claim))
            #expect(!advancedContent.contains(claim))
        }

        let atlas = (source + model).lowercased()
        for claim in ["keep forever", "30 days", "8 gb cache", "cache and memory meters are live"] {
            #expect(!atlas.contains(claim))
        }
    }

    @Test func atlasDoesNotAdvertiseDecorativeSettingCountsOrResourceMeters() throws {
        let source = try atlasSource()
        let model = try atlasModelSource()
        let window = try atlasWindowSource()
        let advancedPreview = try section(named: "previewSurface", in: source)

        #expect(!model.contains("settingCount"))
        #expect(!source.contains("settingCount"))
        #expect(!window.contains("settingCount"))
        #expect(!advancedPreview.contains("CACHE"))
        #expect(!advancedPreview.contains("MEMORY CEILING"))
        #expect(!advancedPreview.contains("8 GB"))
    }

    @Test func atlasDoesNotAdvertiseUnsupportedCountsOrGIFBudgeting() throws {
        let atlas = try atlasSource() + atlasModelSource() + atlasWindowSource()

        for claim in [
            "18 settings differ from defaults",
            "value: \"18\"",
            "ESTIMATED SIZE",
            "5 MB",
            "Size ceiling",
            "estimate exceeds the ceiling",
            "When over budget",
            "budget meter",
            "hard size budget",
        ] {
            #expect(!atlas.contains(claim))
        }
    }

    @Test func atlasDoesNotAdvertiseUnsupportedSettingsRoutesOrLiveStatuses() throws {
        let source = try atlasSource()
        let model = try atlasModelSource()

        for claim in ["aeroshot://settings/", "category.deepLink", "00:12.48", "MIC OFF", "Text(\"LIVE\")"] {
            #expect(!(source + model).contains(claim))
        }
        #expect(!model.contains("return [\"System\", \"Coral\", \"Regular density\"]"))
    }

    @Test func atlasNavigationOnlyListsRenderedSections() {
        #expect(!SettingsAtlasTerritoryView.sectionTitles(for: .mediaLibrary).contains("Lifecycle"))
        #expect(!SettingsAtlasTerritoryView.sectionTitles(for: .advanced).contains("Storage"))
    }

    @Test func atlasDoesNotAdvertiseUnsupportedExportNotificationsOrGIFOptimisation() throws {
        let source = try atlasSource()
        let model = try atlasModelSource()
        let exportContent = try section(named: "exportContent", in: source)
        let gifContent = try section(named: "gifRecordingContent", in: source)
        let atlas = source + model

        for claim in [
            "Automatic optimisation",
            "Drop duplicate frames and quantise on the fly",
            "gif.optimise",
            "Optimised",
            "Notify when exports finish",
            "System notification with a reveal action",
            "export.notify",
            "general.notifications",
            "Notifications & confirmations",
        ] {
            #expect(!atlas.contains(claim))
            #expect(!exportContent.contains(claim))
            #expect(!gifContent.contains(claim))
        }
    }

    @Test func atlasAutomationAndFilenameDescriptionsMatchImplementedBehavior() throws {
        let source = try atlasSource()
        let model = try atlasModelSource()
        let advancedContent = try section(named: "advancedContent", in: source)

        #expect(!advancedContent.contains("Automation hooks"))
        #expect(!advancedContent.contains("EmptyView()"))
        #expect(!model.contains("open the system Shortcuts and AppleScript settings"))
        #expect(!source.contains("FILENAME PREVIEW"))
        #expect(!source.contains("Screenshot 2026-08-01 at 14-32-08.png"))
        #expect(!model.contains("filename preview updates as you type"))
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

    private func atlasWindowSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: "Aeroshot/Settings/Atlas/SettingsAtlasWindow.swift"))
    }

    private func section(named name: String, in source: String) throws -> Substring {
        let start = try #require(source.range(of: "private var \(name)"))
        let end = source.range(of: "    @ViewBuilder", range: start.upperBound..<source.endIndex)?.lowerBound ?? source.endIndex
        return source[start.lowerBound..<end]
    }
}
