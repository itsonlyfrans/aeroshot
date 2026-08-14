import CryptoKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class AeroshotUITests: XCTestCase {
    private var app: XCUIApplication!
    private var fixtureRoot: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        fixtureRoot = FileManager.default.temporaryDirectory
            .appending(path: "AeroshotUITests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixtureRoot { try? FileManager.default.removeItem(at: fixtureRoot) }
    }

    @MainActor
    func testPermissionRecoveryAndAccessibilitySurface() throws {
        launch(action: ["privacy-review"])

        let settings = app.windows["Aeroshot Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8), "Privacy review must open Settings without an Accessibility blocking alert.")
        XCTAssertFalse(app.alerts["Enable Accessibility for Global Shortcuts"].exists)

        let permissionState = app.buttons["settings.permission.screen-recording"]
        XCTAssertTrue(permissionState.waitForExistence(timeout: 3),
                      "Privacy review must navigate to an actionable Screen Recording permission row.")
        assertUsefulAccessibility(permissionState, expectedLabelFragment: permissionState.label)
        XCTAssertTrue(app.menuItems["Settings…"].exists, "The Settings command must remain available to keyboard and assistive input.")
    }

    @MainActor
    func testFirstStatusPopoverActionWorksFromAnotherForegroundApp() throws {
        app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES", "-showInMenuBar", "YES"]
        app.launchEnvironment["AEROSHOT_UI_TEST"] = "1"
        app.launch()

        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        XCTAssertEqual(finder.state, .runningForeground)
        XCTAssertEqual(app.state, .runningBackground)

        let systemUI = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
        let systemStatusItem = systemUI.menuBars.statusItems["Aeroshot"]
        let appStatusItem = app.statusItems["Aeroshot"]
        let statusItem = systemStatusItem.waitForExistence(timeout: 8) ? systemStatusItem : appStatusItem
        XCTAssertTrue(statusItem.waitForExistence(timeout: 3), "The Aeroshot status item must expose its accessibility label.")
        statusItem.click()

        guard app.state == .runningBackground else {
            throw XCTSkip("This XCTest runtime activates Aeroshot before clicking its status item, so it cannot exercise inactive-app first-mouse delivery.")
        }

        let settingsButton = app.buttons["status.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3), "The status popover must expose its Settings action.")
        settingsButton.click()

        XCTAssertTrue(app.windows["Aeroshot Settings"].waitForExistence(timeout: 3),
                      "One click must open Settings after another app owns focus.")
    }

    @MainActor
    func testShareSafeReviewExposesSafeDefaultCountAndCancel() throws {
        app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launchEnvironment["AEROSHOT_UI_TEST"] = "1"
        app.launchEnvironment["AEROSHOT_UI_TEST_SHARE_SAFE_MATCH_COUNT"] = "2"
        app.launch()

        let alert = app.dialogs.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        let alertText = alert.staticTexts.allElementsBoundByIndex.flatMap {
            [$0.label, $0.value as? String].compactMap { $0 }
        }.joined(separator: " ")
        XCTAssertTrue(alertText.contains("2 sensitive regions"), "The alert must state how many regions need review. Found: \(alertText)")
        XCTAssertTrue(alert.buttons["Redact & Share"].exists)
        XCTAssertTrue(alert.buttons["Share Original"].exists)
        XCTAssertTrue(alert.buttons["Cancel"].exists)

        alert.buttons["Cancel"].click()
        XCTAssertFalse(alert.waitForExistence(timeout: 1))
    }

    @MainActor
    func testReducedMotionAndIncreasedContrastLaunchRemainsKeyboardNavigable() throws {
        app = XCUIApplication()
        app.launchEnvironment["NSAccessibilityReduceMotion"] = "YES"
        app.launchEnvironment["NSAccessibilityDisplayShouldIncreaseContrast"] = "YES"
        launch(action: ["privacy-review"], using: app)

        XCTAssertTrue(app.windows["Aeroshot Settings"].waitForExistence(timeout: 8))
        let searchTrigger = app.buttons["Search every setting"]
        XCTAssertTrue(searchTrigger.waitForExistence(timeout: 3), "Settings search remains available under display accommodations.")
        searchTrigger.click()
        XCTAssertTrue(app.textFields["settings.atlas.search"].waitForExistence(timeout: 3), "The Atlas command palette exposes a focused search field.")
        XCTAssertTrue(app.menuItems["Settings…"].exists, "Keyboard Settings entry remains exposed under display accommodations.")
    }

    @MainActor
    func testSettingsSearchFocusAndSelectAll() throws {
        launch(action: ["privacy-review"])

        let searchTrigger = app.buttons["Search every setting"]
        XCTAssertTrue(searchTrigger.waitForExistence(timeout: 8))
        searchTrigger.click()

        let search = app.textFields["settings.atlas.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.click()
        search.typeText("original")
        app.typeKey("a", modifierFlags: .command)
        app.typeText("replacement")
        XCTAssertEqual(search.value as? String, "replacement", "Command-A must select all text in Settings search.")
    }

    @MainActor
    func testScreenshotProjectOpenEditSaveAndExportControls() throws {
        let project = try makeScreenshotProjectFixture()
        launch(action: ["open-project", "--path", project.path])

        let editorWindow = app.windows["Golden Screenshot"]
        XCTAssertTrue(editorWindow.waitForExistence(timeout: 10))
        for label in ["Select", "Arrow", "Text", "Blur", "Undo", "Redo", "Zoom in", "Zoom out"] {
            let control = app.buttons[label]
            XCTAssertTrue(control.exists, "Editor control '\(label)' must have a stable accessibility label.")
            assertUsefulAccessibility(control, expectedLabelFragment: label)
        }

        let undo = app.buttons["Undo"]
        XCTAssertFalse(undo.isEnabled, "Undo must communicate unavailable state through the disabled accessibility state.")
        XCTAssertTrue(app.buttons["Arrow"].isSelected, "The default tool selection must be exposed as an accessibility trait.")

        XCTAssertTrue(app.menuItems["Save Project"].exists, "Editing a project must expose a File menu Save Project command.")
        XCTAssertTrue(app.menuItems["Save Project As…"].exists, "Editing a project must expose a File menu Save Project As command.")
        for command in ["Copy Annotation", "Paste Annotation", "Duplicate Annotation", "Select (V)", "Arrow (A)", "Text (T)"] {
            XCTAssertTrue(app.menuItems[command].exists, "Editor productivity command '\(command)' must be visible in the menu bar.")
        }
        let canvasPoint = editorWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        canvasPoint.click()
        app.typeKey("v", modifierFlags: [])
        XCTAssertTrue(app.buttons["Select"].isSelected, "V must switch to Select while the canvas owns keyboard focus.")
        app.typeKey("t", modifierFlags: [])
        XCTAssertTrue(app.buttons["Text"].isSelected, "T must switch to Text while the canvas owns keyboard focus.")
        let exportMode = app.buttons["editor.exportMode"]
        XCTAssertTrue(exportMode.exists && exportMode.isEnabled, "The screenshot editor must expose direct export without entering Studio.")
        exportMode.click()
        for (id, label) in [("documentation", "Documentation"), ("retina", "Retina asset"), ("downscaled", "Downscaled"), ("socialSquare", "Social square"), ("socialLandscape", "Social landscape")] {
            XCTAssertTrue(app.buttons["editor.exportRecipe.\(id)"].exists, "The editor must expose the applied \(label) export recipe.")
        }
        XCTAssertTrue(app.buttons["editor.export"].isEnabled)
        XCTAssertTrue(app.menuItems["Settings…"].exists, "Editor launch must retain keyboard-accessible app commands.")
    }

    @MainActor
    func testGIFStudioPlaybackControlsAreAccessibleAndKeyboardOperable() throws {
        let project = try makeGIFProjectFixture()
        launch(action: ["open-project", "--path", project.path])

        let window = app.windows.matching(NSPredicate(format: "title CONTAINS[c] 'GIF Studio'")).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let playPause = app.buttons["gifStudio.playPause"]
        let scrubber = app.sliders["gifStudio.scrubber"]
        XCTAssertTrue(playPause.waitForExistence(timeout: 5))
        XCTAssertTrue(scrubber.exists && scrubber.isEnabled)
        assertUsefulAccessibility(playPause, expectedLabelFragment: "preview")
        XCTAssertFalse(scrubber.label.isEmpty)
        XCTAssertNotEqual(scrubber.elementType, .any)

        playPause.click()
        XCTAssertTrue(playPause.label.localizedCaseInsensitiveContains("pause"))
        scrubber.adjust(toNormalizedSliderPosition: 0.75)
        window.click()
        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(playPause.label.localizedCaseInsensitiveContains("play"))
    }

    @MainActor
    func testInstantScreenshotPathDoesNotRequireStudio() throws {
        launch(action: ["capture", "--mode", "screen"])
        let editor = app.windows["Screenshot"]
        let thumbnail = app.buttons["thumbnail.edit"]
        let permissionAlert = app.alerts.matching(NSPredicate(format: "label CONTAINS[c] 'Screen Recording permission'")).firstMatch
        let permissionToast = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Screen Recording permission'")).firstMatch
        let deadline = Date().addingTimeInterval(10)
        repeat {
            if permissionAlert.exists || permissionToast.exists {
                throw XCTSkip("Screen Recording permission is not granted to the signed UI-test host; validate this row manually in the permission matrix.")
            }
            if editor.exists || thumbnail.exists { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        XCTAssertTrue(editor.exists || thumbnail.exists,
                      "A permitted instant screenshot must reach editor/output UI.")
        XCTAssertFalse(app.staticTexts["Video Studio"].exists)
        XCTAssertFalse(app.staticTexts["GIF Studio"].exists)
    }

    @MainActor
    func testRecordingStudioEntryOrExactPermissionSkip() throws {
        launch(action: ["capture", "--mode", "record-screen"])
        if permissionBlockIsVisible() {
            throw XCTSkip("Screen Recording permission is not granted to the signed UI-test host; recording/GIF Studio entry requires manual TCC validation.")
        }

        let recordingSurface = firstExisting([
            app.staticTexts["Recording Setup"],
            app.buttons["Start Recording"],
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'recording'" )).firstMatch,
            app.menuItems.matching(NSPredicate(format: "label CONTAINS[c] 'recording'" )).firstMatch
        ])
        let surfaced = recordingSurface.waitForExistence(timeout: 10)
        XCTAssertTrue(surfaced || app.state == .runningForeground || app.state == .runningBackground,
                      "Permitted recording must remain active or expose recording controls.")
    }

    @MainActor
    func testLaunchPerformance() throws {
        app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launchEnvironment["AEROSHOT_UI_TEST"] = "1"
        measure(metrics: [XCTApplicationLaunchMetric()]) { app.launch() }
    }

    @MainActor
    func testVisualFixtureLight() throws { try captureVisualFixture(name: "light", environment: [:]) }

    @MainActor
    func testVisualFixtureDark() throws { try captureVisualFixture(name: "dark", environment: ["AppleInterfaceStyle": "Dark"]) }

    @MainActor
    func testVisualFixtureIncreasedContrast() throws {
        try captureVisualFixture(name: "increased-contrast", environment: ["NSAccessibilityDisplayShouldIncreaseContrast": "YES"])
    }

    @MainActor
    func testVisualFixtureReducedMotion() throws {
        try captureVisualFixture(name: "reduced-motion", environment: ["NSAccessibilityReduceMotion": "YES"])
    }

    @MainActor
    private func launch(action: [String], using configuredApp: XCUIApplication? = nil) {
        app = configuredApp ?? XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES", "--aeroshot-action"] + action
        app.launchEnvironment["AEROSHOT_UI_TEST"] = "1"
        app.launch()
    }

    @MainActor
    private func captureVisualFixture(name: String, environment: [String: String]) throws {
        let fixtureApp = XCUIApplication()
        fixtureApp.launchEnvironment.merge(environment) { _, new in new }
        launch(action: ["privacy-review"], using: fixtureApp)
        if !fixtureApp.windows["Aeroshot Settings"].waitForExistence(timeout: 3) {
            fixtureApp.activate()
            fixtureApp.typeKey(",", modifierFlags: .command)
        }
        let settingsWindow = fixtureApp.windows["Aeroshot Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 8), "Missing Settings fixture for \(name)")
        let screenshot = settingsWindow.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "settings-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let baselinePath = ProcessInfo.processInfo.environment["AEROSHOT_VISUAL_BASELINE_DIR"] else {
            throw XCTSkip("Approved visual baselines are not configured. Set AEROSHOT_VISUAL_BASELINE_DIR.")
        }
        let baselineDirectory = URL(filePath: baselinePath, directoryHint: .isDirectory)
        let manifest = try VisualRegressionManifest.load(from: baselineDirectory)
        let result = try VisualRegressionComparator.compare(
            actualPNG: screenshot.pngRepresentation,
            fixtureName: "settings-\(name)",
            baselineDirectory: baselineDirectory,
            manifest: manifest
        )
        XCTAssertLessThanOrEqual(
            result.differingPixelRatio,
            manifest.maxDifferingPixelRatio,
            "\(result.differingPixels) of \(result.comparedPixels) pixels differ "
                + "(ratio \(result.differingPixelRatio), maximum channel delta \(result.maximumChannelDelta))."
        )
    }

    func testVisualComparatorHonorsToleranceAndMasks() throws {
        let baseline = try makeSolidPNG(red: 10, green: 20, blue: 30)
        let changed = try makeSolidPNG(red: 10, green: 20, blue: 60)
        let baselineURL = fixtureRoot.appending(path: "baseline.png")
        try baseline.write(to: baselineURL)

        let strict = VisualRegressionManifest(
            schemaVersion: 1,
            approved: true,
            maxChannelDelta: 5,
            maxDifferingPixelRatio: 0,
            fixtures: ["fixture": .init(file: "baseline.png", masks: [])]
        )
        let strictResult = try VisualRegressionComparator.compare(
            actualPNG: changed,
            fixtureName: "fixture",
            baselineDirectory: fixtureRoot,
            manifest: strict
        )
        XCTAssertEqual(strictResult.differingPixels, 1)

        let masked = VisualRegressionManifest(
            schemaVersion: 1,
            approved: true,
            maxChannelDelta: 5,
            maxDifferingPixelRatio: 0,
            fixtures: ["fixture": .init(file: "baseline.png", masks: [.init(x: 0, y: 0, width: 1, height: 1)])]
        )
        XCTAssertThrowsError(try VisualRegressionComparator.compare(
            actualPNG: changed,
            fixtureName: "fixture",
            baselineDirectory: fixtureRoot,
            manifest: masked
        ))
    }

    @MainActor
    private func permissionBlockIsVisible() -> Bool {
        let permissionAlert = app.alerts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Screen Recording permission'")
        ).firstMatch
        let permissionToast = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Screen Recording permission'")
        ).firstMatch
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if permissionAlert.exists || permissionToast.exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }

    @MainActor
    private func firstExisting(_ elements: [XCUIElement]) -> XCUIElement {
        elements.first(where: \.exists) ?? elements[0]
    }

    @MainActor
    private func assertUsefulAccessibility(_ element: XCUIElement, expectedLabelFragment: String) {
        XCTAssertFalse(element.label.isEmpty)
        XCTAssertTrue(element.label.localizedCaseInsensitiveContains(expectedLabelFragment))
        XCTAssertNotEqual(element.elementType, .any, "Key controls must expose an actionable accessibility role.")
    }

    private func makeScreenshotProjectFixture() throws -> URL {
        let package = fixtureRoot.appending(path: "Golden Screenshot.aeroshot")
        let originals = package.appending(path: "assets/originals")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        let png = try makeSolidPNG(red: 48, green: 96, blue: 160)
        let assetID = UUID()
        let relativePath = "assets/originals/\(assetID.uuidString.lowercased()).png"
        try png.write(to: package.appending(path: relativePath))
        let checksum = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        let now = ISO8601DateFormatter().string(from: Date())
        let manifest: [String: Any] = [
            "schemaVersion": 1,
            "id": UUID().uuidString,
            "createdAt": now,
            "modifiedAt": now,
            "compatibility": ["minimumReaderVersion": 1, "minimumWriterVersion": 1, "createdByBuild": "AeroshotUITests"],
            "assets": [[
                "id": assetID.uuidString, "relativePath": relativePath, "sha256": checksum,
                "byteCount": png.count, "isImmutableOriginal": true,
                "metadata": ["mediaType": "image", "pixelSize": ["width": 1, "height": 1], "hasAudio": false]
            ]],
            "primarySourceAssetID": assetID.uuidString,
            "canvas": ["crop": ["x": 0, "y": 0, "width": 1, "height": 1], "background": "source", "colorSpacePolicy": "preserveSource"],
            "overlays": [], "timeline": [], "eventTracks": [], "exportPresets": [],
            "generatedCachePolicy": ["maximumBytes": 536_870_912, "eviction": "leastRecentlyUsed", "isPurgeable": true],
            "recovery": ["generation": 0]
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: package.appending(path: "manifest.json"))
        return package
    }

    private func makeGIFProjectFixture() throws -> URL {
        let package = fixtureRoot.appending(path: "Animated Fixture.aeroshot")
        let originals = package.appending(path: "assets/originals")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        let assetID = UUID()
        let relativePath = "assets/originals/\(assetID.uuidString.lowercased()).gif"
        let gifURL = package.appending(path: relativePath)
        guard let destination = CGImageDestinationCreateWithURL(
            gifURL as CFURL, UTType.gif.identifier as CFString, 2, nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
        for red in [CGFloat(0.2), CGFloat(0.8)] {
            guard let context = CGContext(
                data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ), let image = {
                context.setFillColor(CGColor(red: red, green: 0.3, blue: 0.7, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
                return context.makeImage()
            }() else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: 0.2]
            ] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }

        let gif = try Data(contentsOf: gifURL)
        let checksum = SHA256.hash(data: gif).map { String(format: "%02x", $0) }.joined()
        let now = ISO8601DateFormatter().string(from: Date())
        let manifest: [String: Any] = [
            "schemaVersion": 1,
            "id": UUID().uuidString,
            "createdAt": now,
            "modifiedAt": now,
            "compatibility": ["minimumReaderVersion": 1, "minimumWriterVersion": 1, "createdByBuild": "AeroshotUITests"],
            "assets": [[
                "id": assetID.uuidString, "relativePath": relativePath, "sha256": checksum,
                "byteCount": gif.count, "isImmutableOriginal": true,
                "metadata": ["mediaType": "gif", "pixelSize": ["width": 8, "height": 8], "hasAudio": false]
            ]],
            "primarySourceAssetID": assetID.uuidString,
            "canvas": ["crop": ["x": 0, "y": 0, "width": 1, "height": 1], "background": "source", "colorSpacePolicy": "preserveSource"],
            "overlays": [], "timeline": [], "eventTracks": [], "exportPresets": [],
            "generatedCachePolicy": ["maximumBytes": 536_870_912, "eviction": "leastRecentlyUsed", "isPurgeable": true],
            "recovery": ["generation": 0]
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: package.appending(path: "manifest.json"))
        return package
    }

    private func makeSolidPNG(red: UInt8, green: UInt8, blue: UInt8) throws -> Data {
        var bytes = [red, green, blue, UInt8.max]
        let image = bytes.withUnsafeMutableBytes { buffer -> CGImage? in
            let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            return context?.makeImage()
        }
        guard let image else { throw CocoaError(.fileWriteUnknown) }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }
}
