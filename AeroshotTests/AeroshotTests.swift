import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import Aeroshot

@MainActor
struct CaptureWindowRestorationTests {
    @Test func snapshotsOnlyVisibleWindows() {
        let windows = [NSWindow(), NSWindow(), NSWindow()]
        var restored: [ObjectIdentifier] = []
        let snapshot = CaptureWindowRestoration(
            windows: windows,
            isVisible: { $0 === windows[0] || $0 === windows[2] },
            restore: { restored.append(ObjectIdentifier($0)) }
        )

        snapshot.restore()

        #expect(restored == [ObjectIdentifier(windows[0]), ObjectIdentifier(windows[2])])
    }

    @Test func restoresOnlyTheSnapshot() {
        let visible = NSWindow()
        let hidden = NSWindow()
        var restored: [ObjectIdentifier] = []
        let snapshot = CaptureWindowRestoration(
            windows: [visible, hidden],
            isVisible: { $0 === visible },
            restore: { restored.append(ObjectIdentifier($0)) }
        )

        snapshot.restore()

        #expect(restored == [ObjectIdentifier(visible)])
    }

    @Test func restoresTheSnapshotOnce() {
        let window = NSWindow()
        var restoreCount = 0
        let snapshot = CaptureWindowRestoration(
            windows: [window],
            isVisible: { _ in true },
            restore: { _ in restoreCount += 1 }
        )

        snapshot.restore()
        snapshot.restore()

        #expect(restoreCount == 1)
    }

    @Test func existingCaptureDoesNotHideItsWindowsAgain() async {
        let window = NSWindow()
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        let snapshot = CaptureWindowRestoration(windows: [window], isVisible: { _ in true })
        let appState = AppState(captureWindowRestoration: snapshot)

        #expect(await appState.prepareForCaptureOverlay() == nil)
        #expect(window.isVisible)
    }

    @Test func directAreaCancellationRestoresCaptureWindows() {
        let window = NSWindow()
        var restoreCount = 0
        let snapshot = CaptureWindowRestoration(
            windows: [window],
            isVisible: { _ in true },
            restore: { _ in restoreCount += 1 }
        )

        if SelectionOverlayCompletion.cancelled.restoresCaptureWindowsImmediately {
            snapshot.restore(owner: snapshot.owner)
        }

        #expect(restoreCount == 1)
    }

    @Test func directWindowCancellationRestoresCaptureWindows() {
        let window = NSWindow()
        var restoreCount = 0
        let snapshot = CaptureWindowRestoration(
            windows: [window],
            isVisible: { _ in true },
            restore: { _ in restoreCount += 1 }
        )

        if SelectionOverlayCompletion.cancelled.restoresCaptureWindowsImmediately {
            snapshot.restore(owner: snapshot.owner)
        }

        #expect(restoreCount == 1)
    }

    @Test func contextActionDefersCaptureWindowRestoration() {
        let window = NSWindow()
        var restoreCount = 0
        let snapshot = CaptureWindowRestoration(
            windows: [window],
            isVisible: { _ in true },
            restore: { _ in restoreCount += 1 }
        )

        if SelectionOverlayCompletion.continuesCapture.restoresCaptureWindowsImmediately {
            snapshot.restore(owner: snapshot.owner)
        }
        #expect(restoreCount == 0)

        snapshot.restore(owner: snapshot.owner)
        #expect(restoreCount == 1)
    }

    @Test func firstRecordingOwnsCaptureWindows() {
        let window = NSWindow()
        var restoreCount = 0
        let snapshot = CaptureWindowRestoration(
            windows: [window],
            isVisible: { _ in true },
            restore: { _ in restoreCount += 1 }
        )

        #expect(snapshot.restore(owner: snapshot.owner))
        #expect(restoreCount == 1)
    }

    @Test func rejectedRecordingCannotRestoreAnotherOwner() {
        let window = NSWindow()
        var restoreCount = 0
        let snapshot = CaptureWindowRestoration(
            windows: [window],
            isVisible: { _ in true },
            restore: { _ in restoreCount += 1 }
        )

        #expect(!snapshot.restore(owner: CaptureWindowRestorationOwner()))
        #expect(restoreCount == 0)
        #expect(snapshot.restore(owner: snapshot.owner))
        #expect(restoreCount == 1)
    }

    @Test func recordingContinuationKeepsCaptureWindowsHiddenUntilStartup() {
        let window = NSWindow()
        var restoreCount = 0
        let snapshot = CaptureWindowRestoration(
            windows: [window],
            isVisible: { _ in true },
            restore: { _ in restoreCount += 1 }
        )

        #expect(!SelectionOverlayCompletion.continuesCapture.restoresCaptureWindowsImmediately)
        #expect(restoreCount == 0)
        #expect(snapshot.restore(owner: snapshot.owner))
        #expect(restoreCount == 1)
    }

    @Test(arguments: ["preflight failure", "startup failure", "stop", "cancel"])
    func recordingOwnerTerminalPathsRestoreCaptureWindowsOnce(_ path: String) {
        let window = NSWindow()
        var restoreCount = 0
        let snapshot = CaptureWindowRestoration(
            windows: [window],
            isVisible: { _ in true },
            restore: { _ in restoreCount += 1 }
        )

        #expect(snapshot.restore(owner: snapshot.owner), "\(path) must restore the owning capture windows")
        #expect(snapshot.restore(owner: snapshot.owner), "restoration must remain idempotent")

        #expect(restoreCount == 1, "\(path) must restore the capture windows once")
    }

    @Test func ocrCaptureTransfersOwnerAndRestoresItOnEveryTerminalPath() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let ocrSource = try String(contentsOf: root.appending(path: "Aeroshot/OCR/OCRCaptureController.swift"))
        let captureSource = try String(contentsOf: root.appending(path: "Aeroshot/Capture/CaptureController.swift"))
        let allInOneSource = try String(contentsOf: root.appending(path: "Aeroshot/HUD/AllInOneController.swift"))

        #expect(ocrSource.contains("captureWindowOwner: selection.captureWindowOwner"))
        #expect(ocrSource.contains("defer { appState.restoreCaptureWindows(owner: captureWindowOwner) }"))
        #expect(ocrSource.contains("guard let image = try? await ScreenCaptureService.captureArea"))
        #expect(ocrSource.contains("if text.isEmpty"))
        #expect(ocrSource.contains("appState.history.add(textCapture: text) == nil"))
        #expect(ocrSource.contains("Couldn’t add text capture to History."))
        #expect(captureSource.contains("self?.appState.restoreCaptureWindows(owner: inputs.captureWindowOwner)"))
        #expect(allInOneSource.contains("captureWindowOwner: captureWindowOwner"))
    }

    @Test func activeRecordingKeepsCaptureWindowsHidden() throws {
        let configuration = try RecordingSessionConfiguration(
            source: .display(id: "display"),
            dimensions: RecordingDimensions(width: 2, height: 2),
            frameRate: RecordingFrameRate(framesPerSecond: 30),
            cursorMode: .visible,
            audio: RecordingAudioConfiguration(capturesSystemAudio: false),
            webcam: nil,
            countdown: RecordingCountdown(seconds: 0),
            events: RecordingEventConfiguration(capturesClicks: false),
            requiredSpaceEstimateBytes: 1
        )
        let snapshot = RecordingSessionSnapshot(
            sessionID: UUID(),
            configuration: configuration,
            createdAt: Date()
        )

        #expect(RecordingController.hasActiveSession(.recording(snapshot)))
        #expect(!RecordingController.hasActiveSession(.failed(.captureFailed(code: "startup"))))
        #expect(!RecordingController.hasActiveSession(.cancelled))
    }
}

// MARK: - Selection cursor

@MainActor
struct SelectionCursorTests {
    @Test func regionCursorIsACenteredReticle() {
        let cursor = SelectionCursor.crosshair
        #expect(cursor.image.size == NSSize(width: 24, height: 24))
        #expect(cursor.hotSpot == NSPoint(x: 12, y: 12))
    }
}

@MainActor
struct SelectionSurfaceTests {
    @Test func onlyExternalImageSinksRequireProtectedOutput() {
        #expect(SelectionSurfaceAction.copy.requiresProtectedCaptureOutput)
        for action in [SelectionSurfaceAction.save, .annotate, .pin, .shareSafe, .grabText, .record, .dismiss] {
            #expect(!action.requiresProtectedCaptureOutput)
        }
    }

    @Test func contextRailDoesNotAdvertiseFakeDestinations() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let view = try String(contentsOf: root.appending(path: "Aeroshot/Selection/SelectionOverlayView.swift"))
        let controller = try String(contentsOf: root.appending(path: "Aeroshot/Selection/SelectionOverlayController.swift"))
        for label in ["Desktop  ▾", "Clipboard only", "Downloads", "Aeroshot Library", "Ask each time"] {
            #expect(!view.contains(label))
            #expect(!controller.contains(label))
        }
        #expect(!view.contains("destinationIndex"))
        #expect(!controller.contains("case copy, save, destination"))
    }

    @Test func deferredImageSinksUseProtectedOutput() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let thumbnail = try String(contentsOf: root.appending(path: "Aeroshot/Thumbnail/FloatingThumbnailController.swift"))
        let history = try String(contentsOf: root.appending(path: "Aeroshot/History/CaptureTrayView.swift"))
        let appState = try String(contentsOf: root.appending(path: "Aeroshot/App/AppState.swift"))

        #expect(thumbnail.contains("performProtectedAction(image: image, fileURL: fileURL"))
        #expect(history.components(separatedBy: "performProtectedImageAction(item)").count == 3)
        #expect(history.contains("let result = try await appState.prepareCaptureOutput(image)"))
        #expect(history.contains("result.matchCount == 0 ? history.fileURL(for: item) : nil"))
        #expect(appState.contains("else if requiresProtection"))
        #expect(appState.contains("protectedImage = try await ShareSafeService.process("))
    }

    @Test func overlayPrepSkipsFrozenCapturesUnlessRequested() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let capture = try String(contentsOf: root.appending(path: "Aeroshot/Capture/CaptureController.swift"))
        let enumerator = try String(contentsOf: root.appending(path: "Aeroshot/Capture/WindowEnumerator.swift"))

        #expect(capture.contains("WindowEnumerator.overlayContent()"))
        #expect(capture.contains("if includeFrozenImages {"))
        #expect(capture.contains("makeOverlayInputs(includeFrozenImages: false)"))
        #expect(capture.contains("ScreenCaptureService.captureArea(local, on: display)"))
        #expect(enumerator.contains("static func overlayContent() async throws -> OverlayContent"))
    }

    @Test func markupPointsUseTopLeftImagePixels() {
        let point = SelectionMarkupGeometry.imagePoint(
            local: CGPoint(x: 25, y: 30),
            viewSize: CGSize(width: 100, height: 80),
            imageSize: CGSize(width: 200, height: 160)
        )

        #expect(point == CGPoint(x: 50, y: 100))
    }

    @Test func retainedMarkupCaptureUsesFullDisplayBeforeCrop() {
        #expect(RetainedAreaMarkupCapturePolicy.select(
            freezesScreen: true,
            hasFrozenDisplay: true,
            hasAnnotations: true
        ) == .frozenFullDisplay)
        #expect(RetainedAreaMarkupCapturePolicy.select(
            freezesScreen: false,
            hasFrozenDisplay: true,
            hasAnnotations: true
        ) == .liveFullDisplay)
        #expect(RetainedAreaMarkupCapturePolicy.select(
            freezesScreen: false,
            hasFrozenDisplay: true,
            hasAnnotations: false
        ) == .liveArea)
        #expect(!RetainedAreaMarkupCapturePolicy.frozenFullDisplay.requiresCompositorSettle)
        #expect(RetainedAreaMarkupCapturePolicy.liveFullDisplay.requiresCompositorSettle)
        #expect(RetainedAreaMarkupCapturePolicy.liveArea.requiresCompositorSettle)
    }

    @Test func onlyStillAreaEnablesPreselectionMarkup() {
        for intent in CaptureIntent.allCases {
            #expect(AllInOneController.allowsMarkup(for: intent) == (intent == .area))
        }
    }

    @Test func markupUndoNeverFallsBackToAnotherDisplay() {
        let first = CGDirectDisplayID(1)
        let second = CGDirectDisplayID(2)

        #expect(SelectionMarkupUndoRouting.target(
            activeDisplayID: second,
            availableDisplayIDs: [first, second]
        ) == second)
        #expect(SelectionMarkupUndoRouting.target(
            activeDisplayID: nil,
            availableDisplayIDs: [first]
        ) == nil)
        #expect(SelectionMarkupUndoRouting.target(
            activeDisplayID: second,
            availableDisplayIDs: [first]
        ) == nil)
    }

    @Test func initialSelectionKeepsMouseDownAnchor() {
        let bounds = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let anchor = CGPoint(x: 900, y: 500)
        let pointer = CGPoint(x: 100, y: 0)

        let first = SelectionDragGeometry.initialRect(anchor: anchor, pointer: pointer, ratio: 1, bounds: bounds)
        let second = SelectionDragGeometry.initialRect(anchor: anchor, pointer: pointer, ratio: 1, bounds: bounds)

        #expect(first == second)
        #expect(first.maxX == anchor.x)
        #expect(first.maxY == anchor.y)
        #expect(first.minX >= bounds.minX)
        #expect(first.minY >= bounds.minY)
    }

    @Test func retainedMoveUsesOriginalPointerAndRect() {
        let bounds = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let original = CGRect(x: 100, y: 120, width: 300, height: 200)
        let pointerDown = CGPoint(x: 250, y: 220)

        let first = SelectionDragGeometry.translatedRect(
            originalRect: original,
            pointerDown: pointerDown,
            pointer: CGPoint(x: 300, y: 270),
            bounds: bounds
        )
        let second = SelectionDragGeometry.translatedRect(
            originalRect: original,
            pointerDown: pointerDown,
            pointer: CGPoint(x: 350, y: 320),
            bounds: bounds
        )

        #expect(first == CGRect(x: 150, y: 170, width: 300, height: 200))
        #expect(second == CGRect(x: 200, y: 220, width: 300, height: 200))
    }

    @Test func retainedSelectionNudgesByOneOrTenPointsAndClamps() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 80)
        let original = CGRect(x: 80, y: 60, width: 20, height: 20)
        #expect(SelectionDragGeometry.translatedRect(
            originalRect: original,
            pointerDown: .zero,
            pointer: CGPoint(x: -1, y: -1),
            bounds: bounds
        ) == CGRect(x: 79, y: 59, width: 20, height: 20))
        #expect(SelectionDragGeometry.translatedRect(
            originalRect: original,
            pointerDown: .zero,
            pointer: CGPoint(x: 10, y: 10),
            bounds: bounds
        ) == original)
    }

    @Test func anchoredSnapKeepsTheFixedEdge() {
        let rect = CGRect(x: 100, y: 200, width: 395, height: 200)
        let snapped = SelectionDragGeometry.anchoredSnap(
            rect,
            anchor: CGPoint(x: 100, y: 200),
            xTargets: [0, 500, 1_000],
            yTargets: [0, 1_000]
        )

        #expect(snapped.minX == 100)
        #expect(snapped.maxX == 500)
        #expect(snapped.width == 400)
        #expect(snapped.height == rect.height)
    }
}

// MARK: - ScreenCaptureKit frame delivery

struct RegionFrameStreamTests {
    @Test func continuationStoreAllowsConcurrentFrameDeliveryAndFinish() {
        let store = FrameContinuationStore()
        let image = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!.makeImage()!

        _ = AsyncStream<CGImage>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            store.install(continuation)
        }

        // ScreenCaptureKit invokes delivery on its sample queue while the HUD
        // can finish the capture on the main actor. This must never race the
        // continuation's teardown.
        DispatchQueue.concurrentPerform(iterations: 400) { index in
            if index.isMultiple(of: 3) {
                store.finish()
            } else {
                store.yield(image)
            }
        }

        store.finish()
    }
}

@MainActor
struct PinnedWindowTests {
    @Test func imageSurfaceAllowsWindowDragging() {
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let panel = PinPanel(image: context.makeImage()!)

        #expect(panel.contentView?.mouseDownCanMoveWindow == true)
    }
}

@MainActor
struct HybridSelectionTests {
    @Test func onlyScreenshotAreaUsesHybridWindowDetection() {
        #expect(CaptureIntent.area.selectionMode == .hybrid)
        #expect(CaptureIntent.recordArea.selectionMode == .area)
        #expect(CaptureIntent.ocr.selectionMode == .area)
        #expect(CaptureIntent.scrolling.selectionMode == .scrolling)
        #expect(AllInOneController.reviewSelectionMode(for: .area) == .hybrid)
        #expect(AllInOneController.reviewSelectionMode(for: .fullScreen) == .screen)
    }

    @Test func dockHighlightUsesScreenCaptureFrameInsteadOfTransparentBackdrop() {
        let backdrop = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let dock = CGRect(x: 470, y: 900, width: 572, height: 82)

        #expect(WindowEnumerator.selectionFrame(
            ownerName: "Dock",
            cgBounds: backdrop,
            scFrame: dock
        ) == dock)
        #expect(WindowEnumerator.selectionFrame(
            ownerName: "Safari",
            cgBounds: backdrop,
            scFrame: dock
        ) == backdrop)
    }

    @Test func dockCaptureIncludesPaintedChromeThroughTheDisplayEdge() {
        let display = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let accessibilityFrame = CGRect(x: 558, y: 1039, width: 612, height: 68)

        #expect(WindowEnumerator.dockCaptureFrame(
            accessibilityFrame: accessibilityFrame,
            displayFrame: display
        ) == CGRect(x: 556, y: 1037, width: 616, height: 80))
    }

    @Test func transientWindowFallsBackToFrontmostFrozenFrame() {
        let back = CGRect(x: 0, y: 0, width: 800, height: 600)
        let transientFront = CGRect(x: 200, y: 150, width: 400, height: 200)

        #expect(WindowEnumerator.snapshotHitIndex(
            at: CGPoint(x: 300, y: 200),
            frames: [transientFront, back]
        ) == 0)
        #expect(WindowEnumerator.shouldPreferSnapshot(
            snapshotID: 77,
            liveID: 100,
            liveIDs: [100]
        ))
    }

    @Test func compositedSelectionUsesExactChangedPixelBounds() {
        func image(marker: CGRect?) -> CGImage {
            let context = CGContext(
                data: nil,
                width: 6,
                height: 5,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 6, height: 5))
            if let marker {
                context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
                context.fill(marker)
            }
            return context.makeImage()!
        }

        #expect(CaptureController.pixelDifferenceBounds(
            included: image(marker: CGRect(x: 1, y: 0, width: 3, height: 2)),
            excluded: image(marker: nil)
        ) == CGRect(x: 1, y: 0, width: 3, height: 2))
    }

    @Test func companionUIIsDismissedBeforeSelectionCaptureSettles() {
        var dismissed = false
        var completed = false
        let controller = SelectionOverlayController(
            displays: [],
            windows: [],
            frozenImages: [:],
            mode: .hybrid
        ) { _ in completed = true }
        controller.onWillFinish = { dismissed = true }

        controller.dismiss()

        #expect(dismissed)
        #expect(completed)
    }
}

@MainActor
struct HotkeySuppressionTests {
    @Test func allInOneDefaultAvoidsSpotlightAndKeepsStoredHotkeys() {
        let defaultHotkey = HotkeyAction.allInOne.defaultHotkey
        let spotlight = Hotkey(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))
        let stored = Hotkey(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey))

        #expect(defaultHotkey == Hotkey(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)))
        #expect(defaultHotkey != spotlight)
        #expect(defaultHotkey.isValid)
        #expect(SettingsStore.resolvedHotkeys(stored: [HotkeyAction.allInOne.rawValue: stored])[.allInOne] == stored)
    }

    @Test func matchingGlobalShortcutIsConsumedBeforeDelivery() throws {
        let manager = HotkeyManager.shared
        manager.unregisterAll()
        defer { manager.unregisterAll() }

        let hotkey = HotkeyAction.captureArea.defaultHotkey
        var fired = false
        manager.setBindings([.captureArea: (hotkey, { fired = true })])

        let event = try #require(CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(hotkey.keyCode),
            keyDown: true
        ))
        event.flags = [.maskControl, .maskAlternate]

        #expect(manager.handleTapEvent(.keyDown, event: event) == nil)
        #expect(fired)
    }
}

@MainActor
struct ThumbnailSwipeTests {
    @Test func resolvesAllCardinalDirectionsAndRejectsWeakOrDiagonalMotion() {
        #expect(ThumbnailSwipeResolver.direction(for: CGSize(width: -0.1, height: 0.01)) == .left)
        #expect(ThumbnailSwipeResolver.direction(for: CGSize(width: 0.1, height: 0.01)) == .right)
        #expect(ThumbnailSwipeResolver.direction(for: CGSize(width: 0.01, height: 0.1)) == .up)
        #expect(ThumbnailSwipeResolver.direction(for: CGSize(width: 0.01, height: -0.1)) == .down)
        #expect(ThumbnailSwipeResolver.direction(for: CGSize(width: 0.03, height: 0.01)) == nil)
        #expect(ThumbnailSwipeResolver.direction(for: CGSize(width: 0.1, height: 0.1)) == nil)
    }

    @Test func defaultsAreUsefulAndEveryBindingCanBeChanged() {
        var bindings = ThumbnailSwipeBindings.defaults
        #expect(bindings.action(for: .two, direction: .left) == .dismiss)
        #expect(bindings.action(for: .two, direction: .right) == .edit)
        #expect(bindings.action(for: .two, direction: .up) == .copy)
        #expect(bindings.action(for: .two, direction: .down) == .tuck)
        #expect(bindings.action(for: .three, direction: .left) == .none)

        bindings.set(.shareSafe, for: .three, direction: .down)
        #expect(bindings.action(for: .three, direction: .down) == .shareSafe)
    }
}

// MARK: - Share Safe performance guards

struct ShareSafePerformanceTests {
    @Test func privacyFilterRunsOnlyWhenItCanAddNameCorroboration() {
        #expect(!ShareSafeLinePolicy.needsPrivacyFilterReview(
            lineTexts: ["Build succeeded", "sk_live_4eC39HqLyjWDarjtT1zdp7dc"],
            patternMatched: [1]
        ))
        #expect(ShareSafeLinePolicy.needsPrivacyFilterReview(
            lineTexts: ["Jordan Alvarez", "jordan@example.com"],
            patternMatched: [1]
        ))
    }
}

// MARK: - GeometryConversions

@MainActor
struct GeometryConversionsTests {
    @Test func cocoaToCGRoundTrips() {
        let primaryHeight: CGFloat = 1080
        let rect = CGRect(x: 100, y: 200, width: 300, height: 150)
        let cg = GeometryConversions.cocoaToCG(rect, primaryHeight: primaryHeight)
        #expect(cg == CGRect(x: 100, y: 1080 - 200 - 150, width: 300, height: 150))
        let back = GeometryConversions.cgToCocoa(cg, primaryHeight: primaryHeight)
        #expect(back == rect)
    }

    @Test func cocoaPointToCGRoundTrips() {
        let primaryHeight: CGFloat = 1080
        let point = NSPoint(x: 250, y: 400)
        let cg = GeometryConversions.cocoaPointToCG(point, primaryHeight: primaryHeight)
        #expect(cg == CGPoint(x: 250, y: 680))
        let rect = CGRect(x: 100, y: 200, width: 300, height: 150)
        #expect(rect.contains(cg) == rect.contains(CGPoint(x: cg.x, y: cg.y)))
    }

    @Test func pixelSizeRounds() {
        let size = GeometryConversions.pixelSize(for: CGRect(x: 0, y: 0, width: 100.4, height: 50.6), scale: 2)
        #expect(size == CGSize(width: 201, height: 101))
    }

    @Test func frozenScreenCropMapsPointsToPixelsAndClampsToDisplay() {
        let crop = GeometryConversions.imagePixelRect(
            for: CGRect(x: 10, y: 20, width: 30, height: 40),
            displaySize: CGSize(width: 100, height: 100),
            imageSize: CGSize(width: 200, height: 200)
        )
        #expect(crop == CGRect(x: 20, y: 40, width: 60, height: 80))

        let clipped = GeometryConversions.imagePixelRect(
            for: CGRect(x: 90, y: 90, width: 20, height: 20),
            displaySize: CGSize(width: 100, height: 100),
            imageSize: CGSize(width: 200, height: 200)
        )
        #expect(clipped == CGRect(x: 180, y: 180, width: 20, height: 20))

        let oneX = GeometryConversions.imagePixelRect(
            for: CGRect(x: 10, y: 15, width: 30, height: 20),
            displaySize: CGSize(width: 100, height: 80),
            imageSize: CGSize(width: 100, height: 80)
        )
        let twoX = GeometryConversions.imagePixelRect(
            for: CGRect(x: 10, y: 15, width: 30, height: 20),
            displaySize: CGSize(width: 100, height: 80),
            imageSize: CGSize(width: 200, height: 160)
        )
        #expect(oneX == CGRect(x: 10, y: 15, width: 30, height: 20))
        #expect(twoX == CGRect(x: 20, y: 30, width: 60, height: 40))
    }
}

// MARK: - SettingsStore

struct SettingsStoreTests {
    @MainActor
    private func withRestoredSettings(_ body: (SettingsStore) throws -> Void) throws {
        let settings = SettingsStore.shared
        let snapshot = try #require(settings.exportProfile())
        let cloudSettings = (
            settings.uploadWebhookURL,
            settings.uploadAfterCapture,
            settings.copyLinkAfterUpload
        )
        let hasCompletedOnboarding = settings.hasCompletedOnboarding
        defer {
            try? settings.importProfile(from: snapshot)
            settings.uploadWebhookURL = cloudSettings.0
            settings.uploadAfterCapture = cloudSettings.1
            settings.copyLinkAfterUpload = cloudSettings.2
            settings.hasCompletedOnboarding = hasCompletedOnboarding
        }
        try body(settings)
    }

    @MainActor
    @Test func duplicateStoredHotkeyFallsBackToDefault() {
        let duplicate = HotkeyAction.captureArea.defaultHotkey
        let resolved = SettingsStore.resolvedHotkeys(stored: [
            HotkeyAction.showHistory.rawValue: duplicate
        ])
        #expect(resolved[.showHistory] == HotkeyAction.showHistory.defaultHotkey)
    }

    @MainActor
    @Test func profileRoundTripsPrivacyFilter() throws {
        try withRestoredSettings { settings in
            settings.shareSafePrivacyFilter = true
            let profile = try #require(settings.exportProfile())
            settings.shareSafePrivacyFilter = false

            try settings.importProfile(from: profile)

            #expect(settings.shareSafePrivacyFilter)
        }
    }

    @MainActor
    @Test func profilesCannotChangeCloudUploadSettings() throws {
        try withRestoredSettings { settings in
            settings.uploadWebhookURL = "https://local.example/upload"
            settings.uploadAfterCapture = false
            settings.copyLinkAfterUpload = false

            let profile = try #require(settings.exportProfile())
            var json = try #require(JSONSerialization.jsonObject(with: profile) as? [String: Any])
            #expect(json["uploadWebhookURL"] == nil)
            #expect(json["uploadAfterCapture"] == nil)
            #expect(json["copyLinkAfterUpload"] == nil)

            json["uploadWebhookURL"] = "https://attacker.example/upload"
            json["uploadAfterCapture"] = true
            json["copyLinkAfterUpload"] = true
            try settings.importProfile(from: JSONSerialization.data(withJSONObject: json))

            #expect(settings.uploadWebhookURL == "https://local.example/upload")
            #expect(!settings.uploadAfterCapture)
            #expect(!settings.copyLinkAfterUpload)
        }
    }

    @MainActor
    @Test func existingInstallsReceiveQuieterCaptureDefaultsOnce() {
        let defaults = UserDefaults.standard
        let key = SettingsStore.quieterCaptureDefaultsMigrationKey
        let originalMigration = defaults.object(forKey: key)
        let originalCopy = defaults.object(forKey: "copyToClipboardAfterCapture")
        let originalActions = defaults.object(forKey: "showThumbnailActionsAlways")
        let originalCopyLink = defaults.object(forKey: "copyLinkAfterUpload")
        defer {
            for (key, value) in [
                (key, originalMigration),
                ("copyToClipboardAfterCapture", originalCopy),
                ("showThumbnailActionsAlways", originalActions),
                ("copyLinkAfterUpload", originalCopyLink),
            ] {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }

        defaults.removeObject(forKey: key)
        defaults.set(true, forKey: "copyToClipboardAfterCapture")
        defaults.set(true, forKey: "showThumbnailActionsAlways")
        defaults.set(true, forKey: "copyLinkAfterUpload")

        let migrated = SettingsStore()
        #expect(!migrated.copyToClipboardAfterCapture)
        #expect(!migrated.showThumbnailActionsAlways)
        #expect(!migrated.copyLinkAfterUpload)

        migrated.copyToClipboardAfterCapture = true
        let reopened = SettingsStore()
        #expect(reopened.copyToClipboardAfterCapture)
    }

    @MainActor
    @Test func thumbnailActionsAreCappedAndRoundTripThroughProfiles() throws {
        try withRestoredSettings { settings in
            settings.thumbnailVisibleActions = [.edit, .share, .copy, .pin]
            #expect(settings.thumbnailVisibleActions == [.edit, .share, .copy, .pin])

            settings.setThumbnailAction(.ocr, visible: true)
            #expect(settings.thumbnailVisibleActions == [.edit, .share, .copy, .pin])

            let profile = try #require(settings.exportProfile())
            settings.thumbnailVisibleActions = [.pin]
            try settings.importProfile(from: profile)

            #expect(settings.thumbnailVisibleActions == [.edit, .share, .copy, .pin])

            settings.thumbnailVisibleActions = []
            let emptyProfile = try #require(settings.exportProfile())
            settings.thumbnailVisibleActions = [.pin]
            try settings.importProfile(from: emptyProfile)
            #expect(settings.thumbnailVisibleActions.isEmpty)
        }
    }

    @MainActor
    @Test func thumbnailSwipeBindingsResetAndRoundTripThroughProfiles() throws {
        try withRestoredSettings { settings in
            settings.setThumbnailSwipeAction(.save, fingers: .three, direction: .up)
            let profile = try #require(settings.exportProfile())

            settings.resetThumbnailSwipeBindings()
            #expect(settings.thumbnailSwipeBindings.action(for: .three, direction: .up) == .none)

            try settings.importProfile(from: profile)
            #expect(settings.thumbnailSwipeBindings.action(for: .three, direction: .up) == .save)
        }
    }

    @MainActor
    @Test func thumbnailSettingsResetToDefaults() throws {
        try withRestoredSettings { settings in
            settings.thumbnailVisibleActions = [.shareSafe, .ocr, .pin, .copy]
            settings.showThumbnailActionsAlways = true
            settings.thumbnailDuration = 12
            settings.setThumbnailSwipeAction(.share, fingers: .three, direction: .down)

            settings.resetThumbnailSettings()

            #expect(settings.thumbnailVisibleActions == ThumbnailAction.defaultVisibleActions)
            #expect(!settings.showThumbnailActionsAlways)
            #expect(settings.thumbnailDuration == 6.0)
            #expect(settings.thumbnailSwipeBindings == .defaults)
        }
    }

    @MainActor
    @Test func legacyProfileWithoutPrivacyFilterUsesDefault() throws {
        try withRestoredSettings { settings in
            let profile = try #require(settings.exportProfile())
            var json = try #require(JSONSerialization.jsonObject(with: profile) as? [String: Any])
            json.removeValue(forKey: "shareSafePrivacyFilter")
            let legacyProfile = try JSONSerialization.data(withJSONObject: json)
            settings.shareSafePrivacyFilter = true

            try settings.importProfile(from: legacyProfile)

            #expect(!settings.shareSafePrivacyFilter)
        }
    }

    @MainActor
    @Test func legacyProfileCanOmitOtherNewSettings() throws {
        try withRestoredSettings { settings in
            let profile = try #require(settings.exportProfile())
            var json = try #require(JSONSerialization.jsonObject(with: profile) as? [String: Any])
            json.removeValue(forKey: "showInDock")
            let legacyProfile = try JSONSerialization.data(withJSONObject: json)
            settings.showInDock = true

            try settings.importProfile(from: legacyProfile)

            #expect(settings.showInDock)
        }
    }

    @MainActor
    @Test func resetAllResetsPrivacyFilter() throws {
        try withRestoredSettings { settings in
            settings.shareSafePrivacyFilter = true
            settings.hasCompletedOnboarding = true
            settings.hasDismissedInputMonitoringGuide = true
            settings.showThumbnailActionsAlways = false

            settings.resetAllToDefaults()

            #expect(!settings.shareSafePrivacyFilter)
            #expect(!settings.hasCompletedOnboarding)
            #expect(!settings.hasDismissedInputMonitoringGuide)
            #expect(!settings.showThumbnailActionsAlways)
        }
    }

    @MainActor
    @Test(.enabled(if: CGPreflightScreenCaptureAccess(), "Requires Screen Recording permission"))
    func lastCaptureRegionReturnsItsSavedDisplay() async throws {
        let displays = try await WindowEnumerator.shareableDisplays()
        guard let display = displays.first else { return }
        let rect = CGRect(x: 20, y: 30, width: 100, height: 80)
        let settings = SettingsStore.shared
        defer { settings.clearLastCaptureRegion() }

        settings.saveLastCaptureRegion(cocoaRect: rect, displayID: display.displayID)

        let recalled = try #require(settings.lastCaptureRegion(matching: displays))
        #expect(recalled.cocoaRect == rect)
        #expect(recalled.display.displayID == display.displayID)
    }

    @MainActor
    @Test(.enabled(if: CGPreflightScreenCaptureAccess(), "Requires Screen Recording permission"))
    func lastCaptureRegionRejectsMissingSavedDisplay() async throws {
        let displays = try await WindowEnumerator.shareableDisplays()
        guard !displays.isEmpty else { return }
        let missingID = CGDirectDisplayID.max
        #expect(!displays.contains { $0.displayID == missingID })
        let settings = SettingsStore.shared
        defer { settings.clearLastCaptureRegion() }

        settings.saveLastCaptureRegion(cocoaRect: CGRect(x: 20, y: 30, width: 100, height: 80), displayID: missingID)

        #expect(settings.lastCaptureRegion(matching: displays) == nil)
    }

    @MainActor
    @Test func uniqueOutputURLAvoidsExistingAndReservedNames() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appendingPathComponent("Screenshot 2026-07-09 at 12.00.00.png")
        try Data().write(to: original)

        let first = SettingsStore.uniqueOutputURL(
            filename: original.lastPathComponent,
            in: directory,
            reservedPaths: []
        )
        #expect(first.lastPathComponent == "Screenshot 2026-07-09 at 12.00.00-1.png")

        let second = SettingsStore.uniqueOutputURL(
            filename: original.lastPathComponent,
            in: directory,
            reservedPaths: [first.path]
        )
        #expect(second.lastPathComponent == "Screenshot 2026-07-09 at 12.00.00-2.png")
    }
}

struct UploadServiceTests {
    @Test func rejectsUnencryptedWebhook() async {
        let file = URL(fileURLWithPath: "/tmp/aeroshot-upload-test.png")
        await #expect(throws: UploadService.UploadError.invalidWebhook) {
            try await UploadService.upload(fileURL: file, webhookURL: "http://example.com/upload")
        }
    }

    @Test func multipartBodyStreamsTheSourceExactlyOnce() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("capture.bin")
        let destination = directory.appendingPathComponent("body.upload")
        let payload = Data(repeating: 0xA5, count: 1_048_576 + 17)
        try payload.write(to: source)

        try UploadService.writeMultipartBody(fileURL: source, to: destination, boundary: "test-boundary")

        var expected = Data("--test-boundary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"capture.bin\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8)
        expected.append(payload)
        expected.append(Data("\r\n--test-boundary--\r\n".utf8))
        #expect(try Data(contentsOf: destination) == expected)
    }
}

// MARK: - UndoStack

@MainActor
struct UndoStackTests {

    private func makeImage() -> CGImage {
        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    @Test func addUndoRedo() {
        let doc = EditorDocument(image: makeImage())
        let annotation = Annotation(kind: .arrow, points: [.zero, CGPoint(x: 10, y: 10)])
        doc.perform(AddAnnotationCommand(annotation: annotation))
        #expect(doc.annotations.count == 1)
        doc.undo()
        #expect(doc.annotations.isEmpty)
        doc.redo()
        #expect(doc.annotations.count == 1)
    }

    @Test func twentyMixedOpsUndoAll() {
        let doc = EditorDocument(image: makeImage())
        for i in 0..<20 {
            switch i % 4 {
            case 0:
                doc.perform(AddAnnotationCommand(annotation: Annotation(kind: .rectangle, points: [.zero, CGPoint(x: CGFloat(i), y: 5)])))
            case 1:
                doc.perform(SetCropCommand(before: doc.cropRect, after: CGRect(x: 0, y: 0, width: CGFloat(i + 1), height: 2)))
            case 2:
                var b = doc.beautify
                b.padding = CGFloat(i)
                doc.perform(SetBeautifyCommand(before: doc.beautify, after: b))
            default:
                if let last = doc.annotations.last {
                    var modified = last
                    modified.lineWidth = CGFloat(i)
                    doc.perform(ModifyAnnotationCommand(before: last, after: modified))
                }
            }
        }
        #expect(doc.undoStack.canUndo)
        for _ in 0..<20 { doc.undo() }
        #expect(doc.annotations.isEmpty)
        #expect(doc.cropRect == nil)
        #expect(doc.beautify == BeautifySettings())
        #expect(!doc.undoStack.canUndo)
        #expect(doc.undoStack.canRedo)
    }

    @Test func redoClearedByNewCommand() {
        let doc = EditorDocument(image: makeImage())
        doc.perform(AddAnnotationCommand(annotation: Annotation(kind: .line, points: [.zero, CGPoint(x: 1, y: 1)])))
        doc.undo()
        #expect(doc.undoStack.canRedo)
        doc.perform(AddAnnotationCommand(annotation: Annotation(kind: .line, points: [.zero, CGPoint(x: 2, y: 2)])))
        #expect(!doc.undoStack.canRedo)
    }
}

// MARK: - ImageStitcher

struct ScrollingCapturePolicyTests {
    @Test func autoScrollWaitsForTheFirstCapturedFrame() {
        #expect(!ScrollingCapturePolicy.canStartAutoScroll(enabled: true, hasFirstFrame: false))
        #expect(ScrollingCapturePolicy.canStartAutoScroll(enabled: true, hasFirstFrame: true))
    }

    @Test func autoScrollSplitsLargeJumpsIntoSmoothSteps() {
        let cadence = ScrollingCapturePolicy.cadence(configuredPixels: 120)

        #expect(cadence.stepPixels == 20)
        #expect(cadence.intervalMilliseconds == 60)
    }

    @MainActor
    @Test func scrollingCaptureStartsWithRegionSelection() {
        #expect(CaptureIntent.scrolling.selectionMode == .scrolling)
    }

    @Test func retakeAlwaysRequestsAFreshScrollingRegion() {
        #expect(ScrollingCapturePolicy.requestsFreshSelection(after: .retake))
        #expect(!ScrollingCapturePolicy.requestsFreshSelection(after: .done))
        #expect(!ScrollingCapturePolicy.requestsFreshSelection(after: .cancel))
    }

    @Test func currentActiveSessionAcceptsSuspendedWork() {
        #expect(ScrollingCapturePolicy.acceptsActiveWork(
            expectedRevision: 7,
            currentRevision: 7,
            isCapturing: true
        ))
    }

    @Test func finishInvalidatesSuspendedMatching() {
        #expect(!ScrollingCapturePolicy.acceptsActiveWork(
            expectedRevision: 7,
            currentRevision: 8,
            isCapturing: false
        ))
    }

    @Test func newSessionInvalidatesStartupPreviewAndOldFinalDelivery() {
        #expect(!ScrollingCapturePolicy.acceptsActiveWork(
            expectedRevision: 7,
            currentRevision: 8,
            isCapturing: true
        ))
        #expect(!ScrollingCapturePolicy.acceptsFinalDelivery(
            token: 7,
            pendingToken: nil,
            isCapturing: false
        ))
        #expect(ScrollingCapturePolicy.acceptsFinalDelivery(
            token: 7,
            pendingToken: 7,
            isCapturing: false
        ))
    }

    @Test func endDetectionRequiresAConservativeStableRun() {
        #expect(!ScrollingCapturePolicy.shouldPauseAtEnd(
            identicalFrames: ScrollingCapturePolicy.identicalFramesAtEnd - 1,
            hasMatchedFrames: true,
            isAutoScrolling: true
        ))
        #expect(ScrollingCapturePolicy.shouldPauseAtEnd(
            identicalFrames: ScrollingCapturePolicy.identicalFramesAtEnd,
            hasMatchedFrames: true,
            isAutoScrolling: true
        ))
    }

    @Test func autoScrollTargetsTheSelectedContent() throws {
        let target = CGPoint(x: 420, y: 240)
        let event = try #require(ScrollEventPoster.makeScrollEvent(pixels: 20, at: target))

        #expect(event.location == target)
        #expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == -20)
        #expect(event.getIntegerValueField(.scrollWheelEventIsContinuous) == 1)
    }
}

struct ImageStitcherTests {

    /// Renders a tall gradient-with-stripes "page" and returns a viewport crop.
    private func makePage(height: Int) -> CGImage {
        let width = 200
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Deterministic pseudo-random horizontal stripes so correlation locks in.
        var seed: UInt64 = 42
        for y in 0..<height {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let v = CGFloat((seed >> 33) % 256) / 255.0
            ctx.setFillColor(CGColor(red: v, green: 1 - v, blue: v * 0.5, alpha: 1))
            ctx.fill(CGRect(x: 0, y: y, width: width, height: 1))
        }
        return ctx.makeImage()!
    }

    private func viewport(of page: CGImage, top: Int, height: Int) -> CGImage {
        page.cropping(to: CGRect(x: 0, y: top, width: page.width, height: height))!
    }

    @Test func detectsKnownOffsetExactly() {
        let page = makePage(height: 1200)
        let a = viewport(of: page, top: 0, height: 400)
        let b = viewport(of: page, top: 120, height: 400)
        let offset = ImageStitcher.verticalOffset(previous: a, next: b, downsample: 4)
        #expect(offset == 120)  // full-res refinement should be row-exact
    }

    @Test func identicalFramesReportedAsIdentical() {
        let page = makePage(height: 600)
        let a = viewport(of: page, top: 50, height: 400)
        guard case .identical? = ImageStitcher.match(previous: a, next: a) else {
            Issue.record("expected .identical")
            return
        }
    }

    @Test func stickyFooterDetectedAndExcluded() {
        // Two frames scrolled by 100 px sharing an identical 60 px bottom bar.
        let page = makePage(height: 1200)
        let bar = makeSolidBar(width: 200, height: 60)
        let a = compose(top: viewport(of: page, top: 0, height: 340), bottom: bar)
        let b = compose(top: viewport(of: page, top: 100, height: 340), bottom: bar)
        guard case .matched(let m)? = ImageStitcher.match(previous: a, next: b) else {
            Issue.record("no match")
            return
        }
        #expect(m.offset == 100)
        #expect(abs(m.footerRows - 60) <= 2)
        let stitched = ImageStitcher.append(composite: a, next: b,
                                            newContentHeight: m.offset, footerRows: m.footerRows)
        #expect(stitched?.height == 400 + m.offset)
    }

    @Test func stripPipelineKeepsStickyFooterOnlyAtTheBottom() throws {
        let page = makePage(height: 1200)
        let footer = makeSolidBar(width: 200, height: 60)
        let first = compose(top: viewport(of: page, top: 0, height: 340), bottom: footer)
        let next = compose(top: viewport(of: page, top: 100, height: 340), bottom: footer)
        guard case .matched(let match)? = ImageStitcher.match(previous: first, next: next) else {
            Issue.record("no match")
            return
        }

        let initialBody = try #require(ImageStitcher.removingBottomRows(from: first, count: match.footerRows))
        let newRows = try #require(ImageStitcher.newContentStrip(from: next,
                                                                 newContentHeight: match.offset,
                                                                 footerRows: match.footerRows))
        let body = try #require(ImageStitcher.compose(strips: [initialBody, newRows]))
        let finalFooter = try #require(next.cropping(to: CGRect(x: 0,
                                                                y: next.height - match.footerRows,
                                                                width: next.width,
                                                                height: match.footerRows)))
        let final = try #require(ImageStitcher.appendStrip(composite: body, strip: finalFooter))

        #expect(final.height == 400 + match.offset)
    }

    private func makeSolidBar(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    /// Stacks `top` above `bottom` into one image.
    private func compose(top: CGImage, bottom: CGImage) -> CGImage {
        let h = top.height + bottom.height
        let ctx = CGContext(data: nil, width: top.width, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .none
        ctx.draw(top, in: CGRect(x: 0, y: bottom.height, width: top.width, height: top.height))
        ctx.draw(bottom, in: CGRect(x: 0, y: 0, width: bottom.width, height: bottom.height))
        return ctx.makeImage()!
    }

    @Test func rejectsUnrelatedFrames() {
        let pageA = makePage(height: 600)
        var seedPage: CGImage {
            let ctx = CGContext(data: nil, width: 200, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 400))
            return ctx.makeImage()!
        }
        let a = viewport(of: pageA, top: 0, height: 400)
        let offset = ImageStitcher.verticalOffset(previous: a, next: seedPage, minConfidence: 0.9)
        #expect(offset == nil)
    }

    @Test func stitchGrowsComposite() {
        let page = makePage(height: 1000)
        let a = viewport(of: page, top: 0, height: 300)
        let b = viewport(of: page, top: 100, height: 300)
        guard let offset = ImageStitcher.verticalOffset(previous: a, next: b) else {
            Issue.record("offset not found")
            return
        }
        let stitched = ImageStitcher.append(composite: a, next: b, newContentHeight: offset)
        #expect(stitched != nil)
        #expect(stitched?.height == 300 + offset)
        #expect(stitched?.width == 200)
    }

    @Test func stripCompositionBuildsOnceAndBoundsTheLivePreview() throws {
        let first = makeSolidBar(width: 200, height: 300)
        let second = makeSolidBar(width: 200, height: 120)
        let third = makeSolidBar(width: 200, height: 90)
        let composite = try #require(ImageStitcher.compose(strips: [first, second, third]))
        let preview = try #require(ImageStitcher.previewTail(of: composite, maxHeight: 240))

        #expect(composite.width == 200)
        #expect(composite.height == 510)
        #expect(preview.width == 200)
        #expect(preview.height == 240)
    }

    @Test func liveOverviewIncludesTheCompleteCaptureWithinItsBounds() throws {
        let first = makeSolidBar(width: 200, height: 300)
        let second = makeSolidBar(width: 200, height: 120)
        let third = makeSolidBar(width: 200, height: 90)
        let preview = try #require(ImageStitcher.overview(
            strips: [first, second, third],
            maxWidth: 100,
            maxHeight: 240
        ))

        #expect(preview.width == 94)
        #expect(preview.height == 240)
    }

    @Test func finalFooterUsesTheCurrentAcceptedFrame() throws {
        let first = makeSolidBar(width: 200, height: 360)
        let latest = makeSolidBar(width: 200, height: 340)
        let historicalFooter = try #require(ImageStitcher.footer(from: first, rows: 60))
        let currentFooter = try #require(ImageStitcher.footer(from: latest, rows: 40))

        #expect(historicalFooter.height == 60)
        #expect(currentFooter.height == 40)
    }

    /// Worst-case real content: mostly-black page, sparse "text" rows, static
    /// black sidebars, sticky header — like a dark-mode social feed.
    @Test func sparseDarkPageWithSidebarsAndHeader() {
        let width = 400
        let pageHeight = 3000
        let ctx = CGContext(data: nil, width: width, height: pageHeight, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: pageHeight))
        // Sparse content only in the center column (x 120..280), ~every 40 px.
        var seed: UInt64 = 7
        for y in stride(from: 0, to: pageHeight, by: 40) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let v = 0.3 + CGFloat((seed >> 33) % 128) / 255.0
            let lineWidth = 40 + Int((seed >> 40) % 120)
            ctx.setFillColor(CGColor(gray: v, alpha: 1))
            ctx.fill(CGRect(x: 120, y: y, width: lineWidth, height: 6))
        }
        let page = ctx.makeImage()!

        func frame(top: Int) -> CGImage {
            let viewportH = 500
            let body = page.cropping(to: CGRect(x: 0, y: top, width: width, height: viewportH - 50))!
            // Sticky 50 px header stacked on top of the scrolled body.
            let hctx = CGContext(data: nil, width: width, height: viewportH, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            hctx.interpolationQuality = .none
            hctx.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.3, alpha: 1))
            hctx.fill(CGRect(x: 0, y: viewportH - 50, width: width, height: 50))
            hctx.draw(body, in: CGRect(x: 0, y: 0, width: width, height: viewportH - 50))
            return hctx.makeImage()!
        }

        for scroll in [40, 120, 260] {
            guard case .matched(let m)? = ImageStitcher.match(previous: frame(top: 0), next: frame(top: scroll)) else {
                Issue.record("no match at scroll \(scroll)")
                continue
            }
            #expect(m.offset == scroll, "scroll \(scroll)")
        }
    }

    @Test func normalizedCorrelationIdentity() {
        let signal: [Float] = (0..<64).map { Float(sin(Double($0) * 0.3)) }
        #expect(ImageStitcher.normalizedCorrelation(signal, signal) > 0.999)
    }
}

// MARK: - PIIDetector

@MainActor
struct PIIDetectorTests {
    @Test func shareSafeDecisionMatrix() {
        let cases: [(scanSucceeded: Bool, matchCount: Int, autoRedact: Bool, expected: ShareSafeShareAction)] = [
            (false, 0, false, .block),
            (false, 0, true, .block),
            (true, 0, false, .shareOriginal),
            (true, 0, true, .shareOriginal),
            (true, 2, false, .reviewRequired),
            (true, 2, true, .shareRedacted),
        ]

        for testCase in cases {
            #expect(ShareSafeService.shareAction(
                scanSucceeded: testCase.scanSucceeded,
                matchCount: testCase.matchCount,
                redactBeforeSharing: testCase.autoRedact
            ) == testCase.expected)
        }
    }

    @Test func shareSafeReviewAlertHasSafeDefaultAndAccessibleCount() {
        let alert = ShareSafeService.reviewAlert(matchCount: 2)
        #expect(alert.buttons.map(\.title) == ["Redact & Share", "Share Original", "Cancel"])
        #expect(alert.buttons[0].keyEquivalent == "\r")
        #expect(alert.buttons[1].hasDestructiveAction)
        #expect(alert.buttons[2].keyEquivalent == "\u{1b}")
        #expect(alert.informativeText.contains("2 sensitive regions"))
    }

    @Test func solidShareSafeRedactionObscuresTheDetectedRectangle() throws {
        let context = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let original = context.makeImage()!
        let redacted = try ShareSafeService.bakeRedactions(
            on: original,
            rects: [CGRect(x: 1, y: 1, width: 2, height: 2)],
            style: .solid
        )
        let data = try #require(redacted.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        let bytesPerPixel = redacted.bitsPerPixel / 8
        let pixelOffset = redacted.bytesPerRow + bytesPerPixel
        #expect(bytes[pixelOffset] == 0)
        #expect(bytes[pixelOffset + 1] == 0)
        #expect(bytes[pixelOffset + 2] == 0)
        #expect(bytes[pixelOffset + 3] == 255)
    }

    @Test func solidRedactionStyleMapsToOpaqueBlackAnnotation() {
        #expect(ShareSafeRedactionStyle.solid.annotationKind == .redactSolid)
        #expect(ShareSafeRedactionStyle.solid.displayName == "Redact")
        #expect(AnnotationKind.redactSolid.isRedaction)
    }

    @Test func editorPrivacyScanAddsRedactionsBeforeUnlockingExport() {
        let context = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let document = EditorDocument(image: context.makeImage()!)
        let session = EditorProjectSession(document: document)
        document.isPrivacyScanPending = true
        document.finishPrivacyScan(
            redactionRects: [CGRect(x: 1, y: 2, width: 3, height: 4)],
            style: .solid
        )
        #expect(!document.isPrivacyScanPending)
        #expect(document.annotations.map(\.kind) == [.redactSolid])
        #expect(document.undoStack.canUndo)
        #expect(session.isDirty)
        document.undo()
        #expect(document.annotations.isEmpty)
    }

    @Test func detectsEmail() {
        let text = "Contact sarah.chen@acmecorp.com for help"
        let ranges = PIIDetector.sensitiveRanges(in: text)
        #expect(ranges.contains { String(text[$0]).contains("@") })
    }

    @Test func detectsInternalEmail() {
        #expect(PIIDetector.lineShouldBeRedacted("support@company.internal"))
    }

    @Test func detectsSplitEmailTokensOnSameLine() {
        let group = [
            OCRTextObservation(text: "support@company", boundingBox: CGRect(x: 10, y: 20, width: 120, height: 18)),
            OCRTextObservation(text: ".internal", boundingBox: CGRect(x: 132, y: 20, width: 60, height: 18)),
        ]
        let merged = ShareSafeService.groupObservationsByLine(group)
        #expect(merged.count == 1)
        let line = merged[0].map(\.text).joined(separator: " ")
        #expect(PIIDetector.lineShouldBeRedacted(line))
    }

    @Test func detectsPhoneNumber() {
        let text = "Call me at (415) 555-0192 tomorrow"
        let ranges = PIIDetector.sensitiveRanges(in: text)
        #expect(!ranges.isEmpty)
    }

    @Test func detectsPhysicalAddress() {
        #expect(PIIDetector.lineShouldBeRedacted("742 Evergreen Terrace, Springfield, CA 94107"))
    }

    @Test func detectsLabeledNameLine() {
        #expect(PIIDetector.lineShouldBeRedacted("Name Jordan Alvarez"))
    }

    @Test func labeledFieldExpansionRedactsNameValue() async throws {
        let lines = ["Name", "Jordan Alvarez", "Build succeeded"]
        let flagged = try await ShareSafeService.sensitiveLineIndices(from: lines, useSmartScan: false)
        #expect(flagged.contains(1))
        #expect(!flagged.contains(2))
    }

    @Test func detectsSplitAddressHead() {
        #expect(PIIDetector.looksLikePhysicalAddress("742 Evergreen Terrace, Springfiel"))
    }

    @Test func continuationExpansionFlagsSplitAddressWithoutPriorMatch() async throws {
        let lines = [
            "742 Evergreen Terrace, Springfiel",
            "d, CA 94107",
        ]
        let flagged = try await ShareSafeService.sensitiveLineIndices(from: lines, useSmartScan: false)
        #expect(flagged.contains(0))
        #expect(flagged.contains(1))
    }

    @Test func detectsStripeSecret() {
        let text = "key leaked: sk_live_4eC39HqLyjWDarjtT1zdp7dc"
        let ranges = PIIDetector.sensitiveRanges(in: text)
        #expect(ranges.contains { String(text[$0]).contains("sk_live_") })
    }

    @Test func ignoresBenignText() {
        let text = "Build succeeded with no warnings"
        #expect(PIIDetector.sensitiveRanges(in: text).isEmpty)
    }

    @Test func copyImageWritesPNGToPasteboard() {
        let ctx = CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = ctx.makeImage()!

        let pasteboard = NSPasteboard(name: .init("AeroshotTests.\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }
        let changeCountBefore = pasteboard.changeCount
        #expect(PasteboardWriter.copy(image: image, pasteboard: pasteboard))
        #expect(pasteboard.changeCount > changeCountBefore)
        #expect(pasteboard.data(forType: .png) != nil)

        let suppliedPNG = Data([1, 2, 3])
        #expect(PasteboardWriter.copy(image: image, pngData: suppliedPNG, pasteboard: pasteboard))
        #expect(pasteboard.data(forType: .png) == suppliedPNG)
    }

    @Test func sensitiveLineIndicesUsesPatternMatchingOnlyWithoutSmartScan() async throws {
        let lines = ["Build succeeded", "Contact sarah.chen@acmecorp.com"]
        let flagged = try await ShareSafeService.sensitiveLineIndices(from: lines, useSmartScan: false)
        #expect(flagged == [1])
    }

    @Test func emptyCaptureSkipsSmartScan() async throws {
        let flagged = try await ShareSafeService.sensitiveLineIndices(from: [], useSmartScan: true)
        #expect(flagged.isEmpty)
    }

    @Test func smartScanFilterSkipsNameOnlyLines() {
        let lines = ["Jordan Alvarez", "jordan@company.com", "Email"]
        let findings = [
            SmartScanFinding(lineIndex: 0, category: .name),
            SmartScanFinding(lineIndex: 1, category: .email),
            SmartScanFinding(lineIndex: 2, category: .email),
        ]
        let filtered = ShareSafeLinePolicy.filterSmartScanFindings(findings, lineTexts: lines, patternMatched: [1])
        #expect(filtered.contains(1))
        #expect(!filtered.contains(0))
        #expect(!filtered.contains(2))
    }

    @Test func smartScanStrongCategoryAcceptedWhenPlausible() {
        let lines = ["my door code is 4482", "Open Settings"]
        let findings = [
            SmartScanFinding(lineIndex: 0, category: .credential),
            SmartScanFinding(lineIndex: 1, category: .email),
        ]
        let filtered = ShareSafeLinePolicy.filterSmartScanFindings(findings, lineTexts: lines, patternMatched: [])
        #expect(filtered.contains(0))
        #expect(!filtered.contains(1))
    }

    @Test func privacyFilterFindingsRequirePatternCorroboration() {
        let lines = [
            "Admin https://admin.staging.acme-demo.internal/users",
            "export STRIPE_KEY=sk_live_4eC39HqLyjWDarjtT1zdp7dc",
            "$ deploy --env staging",
        ]
        let findings = [
            SmartScanFinding(lineIndex: 0, category: .secret),
            SmartScanFinding(lineIndex: 1, category: .secret),
            SmartScanFinding(lineIndex: 2, category: .secret),
        ]
        let filtered = ShareSafeLinePolicy.filterPrivacyFilterFindings(
            findings,
            lineTexts: lines,
            patternMatched: []
        )
        #expect(!filtered.contains(0))
        #expect(filtered.contains(1))
        #expect(!filtered.contains(2))
    }

    @Test func privacyFilterSkipsStatusOkFalsePositive() {
        let line = "Request ID 10234 · Status OK 20000 requests · v2.14.3 build 20250601"
        #expect(!ShareSafeLinePolicy.shouldIncludeSmartScanLine(line))
        let filtered = ShareSafeLinePolicy.filterPrivacyFilterFindings(
            [SmartScanFinding(lineIndex: 0, category: .address)],
            lineTexts: [line],
            patternMatched: []
        )
        #expect(filtered.isEmpty)
    }

    @Test func smartScanSkipsBenignCaptureText() {
        let lines = [
            "Working for 19s",
            "I was connected to Chrome, while your authenticated Google Ads tabs are in Helium.",
            "Investigating Helium browser availability",
        ]
        #expect(!ShareSafeLinePolicy.needsSmartScanReview(lineTexts: lines, patternMatched: []))
        #expect(ShareSafeLinePolicy.needsSmartScanReview(lineTexts: ["Password: hunter2"], patternMatched: []))
        #expect(ShareSafeLinePolicy.needsSmartScanReview(lineTexts: ["my door code is 4482"], patternMatched: []))
    }

    @Test func privacyFilterDoesNotExpandBeyondPatternOnlyScan() async throws {
        let demoDeployLog = [
            "$ deploy --env staging",
            "✓ Connected to k8s.staging.acme-demo.internal",
            "→ Pushing image tagged registry.acme-demo.local/app:sha-9f3a2b1",
            "→ Auth header: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.demo.token.here",
            "→ Notifying oncall@pager.acme-demo.com via webhook",
            "→ DB migrate with postgres://readonly:R3ad0nlyP@ss!@db.internal.acme-demo.local/analytics",
            "✓ Deploy complete — ping (650) 555-2389 if issues",
        ]
        let patternOnly = try await ShareSafeService.sensitiveLineIndices(
            from: demoDeployLog,
            useSmartScan: false,
            usePrivacyFilter: false
        )
        guard PrivacyFilterModel.isDownloaded else { return }
        let withPrivacyFilter = try await ShareSafeService.sensitiveLineIndices(
            from: demoDeployLog,
            useSmartScan: false,
            usePrivacyFilter: true
        )
        #expect(withPrivacyFilter == patternOnly)
    }

    @Test func aiNameNextToFlaggedContactIsCorroborated() {
        let lines = ["Jordan Alvarez", "jordan@company.com"]
        let added = ShareSafeLinePolicy.corroboratedMediumLines(
            lineTexts: lines,
            flagged: [1],
            aiFindings: [SmartScanFinding(lineIndex: 0, category: .name)]
        )
        #expect(added.contains(0))
    }

    @Test func bareStateZipNeedsAdjacentFlaggedLine() {
        let lines = ["CA 94107", "Build succeeded"]
        let isolated = ShareSafeLinePolicy.corroboratedMediumLines(lineTexts: lines, flagged: [], aiFindings: [])
        #expect(isolated.isEmpty)

        let nextToAddress = ShareSafeLinePolicy.corroboratedMediumLines(
            lineTexts: ["742 Evergreen Terrace", "CA 94107"],
            flagged: [0],
            aiFindings: []
        )
        #expect(nextToAddress.contains(1))
    }

    // Exercises the real ONNX model when it's installed (Settings → download);
    // passes trivially otherwise so CI without the 809MB model stays green.
    @Test func privacyFilterScannerFindsSecretsWhenModelInstalled() async throws {
        guard PrivacyFilterModel.isDownloaded else { return }
        let findings = try await PrivacyFilterScanner.shared.findings(lineTexts: [
            "Build succeeded",
            "export STRIPE_KEY=sk_live_4eC39HqLyjWDarjtT1zdp7dc",
            "Call me at (415) 555-0192",
        ])
        #expect(findings.contains { $0.lineIndex == 1 && $0.category == .secret })
        #expect(findings.contains { $0.lineIndex == 2 && $0.category == .phone })
        #expect(!findings.contains { $0.lineIndex == 0 })
    }

    @Test func requestedPrivacyFilterFailsClosedWhenModelIsMissing() async {
        guard !PrivacyFilterModel.isDownloaded else { return }
        await #expect(throws: PrivacyFilterScanError.modelUnavailable) {
            try await PrivacyFilterScanner.shared.findings(lineTexts: ["Password: hunter2"])
        }
    }

    @Test func requestedSmartScanFailsClosedWhenModelIsUnavailable() async {
        guard !ShareSafeSmartScanSupport.isModelAvailable else { return }
        await #expect(throws: ShareSafeSmartScanError.unavailable) {
            try await ShareSafeSmartScanSupport.findings(lineTexts: ["Password: hunter2"])
        }
    }

    @Test func privacyFilterLabelMapping() {
        #expect(SmartScanCategory(privacyFilterLabel: "B-secret") == .secret)
        #expect(SmartScanCategory(privacyFilterLabel: "S-private_email") == .email)
        #expect(SmartScanCategory(privacyFilterLabel: "I-private_address") == .address)
        #expect(SmartScanCategory(privacyFilterLabel: "E-private_person") == .name)
        // Weak on purpose: the model tags invoice/record numbers as account_number.
        #expect(SmartScanCategory(privacyFilterLabel: "B-account_number") == .id)
        #expect(!SmartScanCategory(privacyFilterLabel: "B-account_number").isStrong)
        #expect(SmartScanCategory(privacyFilterLabel: "B-private_url") == .id)
    }

    @Test func detectsJWT() {
        let text = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"
        #expect(!PIIDetector.sensitiveRanges(in: text).isEmpty)
    }

    @Test func detectsConnectionStringCredentials() {
        #expect(PIIDetector.lineShouldBeRedacted("postgres://admin:hunter2@db.internal:5432/prod"))
        #expect(!PIIDetector.lineShouldBeRedacted("https://example.com:8080/path"))
    }

    @Test func detectsHighEntropyToken() {
        #expect(PIIDetector.lineShouldBeRedacted("API_KEY=Zq8xN2vLp0Rt5Wy7Jb4Km9Qs3Fd6Hg1T"))
    }

    @Test func ignoresGitShaAndUUID() {
        #expect(!PIIDetector.isLikelyHighEntropySecret("3f2a9b1c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a"))
        #expect(!PIIDetector.isLikelyHighEntropySecret("550e8400-e29b-41d4-a716-446655440000"))
    }

    @Test func rejectsPlaceholderCardNumber() {
        #expect(PIIDetector.sensitiveRanges(in: "0000 0000 0000 0000").isEmpty)
    }

    @Test func ignoresSettingsCopyWithFieldLabelWords() {
        #expect(!PIIDetector.lineShouldBeRedacted("Email notifications enabled"))
        #expect(!PIIDetector.lineShouldBeRedacted("Phone: see settings"))
    }

    @Test func ignoresIdAndStatusCodes() {
        #expect(PIIDetector.sensitiveRanges(in: "Request ID 10234").isEmpty)
        #expect(PIIDetector.sensitiveRanges(in: "Status OK 20000 requests").isEmpty)
        #expect(!PIIDetector.lineShouldBeRedacted(
            "Request ID 10234 · Status OK 20000 requests · v2.14.3 build 20250601"
        ))
    }

    @Test func continuationExpansionCatchesSplitAddressTail() {
        let lines = [
            "742 Evergreen Terrace, Springfiel",
            "d, CA 94107",
        ]
        let expanded = ShareSafeLinePolicy.expandForContinuations([0], lineTexts: lines)
        #expect(expanded.contains(1))
    }

    @Test func rectsRedactsFlaggedLines() {
        let groups = [
            [
                OCRTextObservation(text: "safe", boundingBox: CGRect(x: 10, y: 10, width: 40, height: 16)),
            ],
            [
                OCRTextObservation(text: "secret@company.com", boundingBox: CGRect(x: 10, y: 40, width: 140, height: 16)),
            ],
        ]
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
        let rects = ShareSafeService.rects(for: groups, flaggedIndices: [1], bounds: bounds)
        #expect(rects.count == 1)
        #expect(rects[0].minY > 20)
    }

    @Test func shareSafeEvalCorpusHasNoFalsePositivesOrNegatives() async throws {
        // Labeled fixture corpus: (screen lines, expected flagged indices).
        // Deterministic pattern path only (useSmartScan: false), so exact match is required.
        let corpus: [(name: String, lines: [String], expected: Set<Int>)] = [
            ("terminal secret", ["$ export STRIPE_KEY=sk_live_4eC39HqLyjWDarjtT1zdp7dc", "Build succeeded"], [0]),
            ("jwt header", ["Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"], [0]),
            ("connection string", ["postgres://admin:hunter2@db.internal:5432/prod", "Connected in 42ms"], [0]),
            ("contact form", ["Name", "Jordan Alvarez", "Email", "jordan@acme.com", "Save"], [1, 3]),
            ("settings copy", ["Email notifications enabled", "Phone: see settings", "General", "Privacy & Security"], []),
            ("dev table", ["Request ID 10234", "Status OK 20000 requests", "v2.14.3"], []),
            ("negative control status line", [
                "Request ID 10234 · Status OK 20000 requests · v2.14.3 build 20250601",
            ], []),
            ("shipping address", ["Ship to:", "742 Evergreen Terrace", "Springfield, CA 94107"], [1, 2]),
            ("payment form", ["Cardholder Jane Doe", "4242 4242 4242 4242", "Exp 12/28"], [0, 1]),
            ("git log", ["commit 3f2a9b1c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a", "Merge pull request #42"], []),
            ("uuid session", ["Session 550e8400-e29b-41d4-a716-446655440000"], []),
            ("generic api key", ["API_KEY=Zq8xN2vLp0Rt5Wy7Jb4Km9Qs3Fd6Hg1T", "Retry with backoff"], [0]),
            ("phone in chat", ["Call me at (415) 555-0192 tomorrow", "Sounds good!"], [0]),
            // Fixtures mirroring design/share-safe-secrets-demo.html sections.
            ("demo contact record", [
                "Contact record #8842",
                "Name Jordan Alvarez",
                "Email jordan.alvarez@acmecorp-demo.com",
                "Backup email jalvarez.personal@gmail-demo.net",
                "Phone (415) 555-0192",
                "Mobile +1 628-555-0147",
                "Address 742 Evergreen Terrace, Springfield, CA 94107",
            ], [1, 2, 3, 4, 5, 6]),
            ("demo billing card", [
                "Cardholder Jordan Alvarez",
                "Visa 4111 1111 1111 1111",
                "Amex 3782 822463 10005",
                "Expiry 09/28",
                "Invoice INV-2026-004821",
            ], [0, 1, 2]),
            ("demo env file", [
                "DATABASE_URL=postgres://admin:SuperSecret123!@db.internal.acme-demo.local:5432/production",
                "STRIPE_SECRET_KEY=sk_live_4eC39HqLyjWDarjtT1zdp7dc",
                "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE",
                "GITHUB_TOKEN=ghp_1234567890abcdefghijklmnopqrstuvwx",
                "SLACK_BOT_TOKEN=xoxb-1234567890-1234567890123-AbCdEfGhIjKlMnOpQrStUvWx",
                "JWT_SECRET=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U",
                "OPENAI_API_KEY=sk-proj-demo-abcdefghijklmnopqrstuvwxyz1234567890",
            ], [0, 1, 2, 3, 4, 5, 6]),
            ("demo api keys", [
                "API keys by service",
                "Stripe test",
                "sk_test_51HqDemoKeyForShareSafeTestingOnly00001",
                "Webhook signing",
                "whsec_demo_9f8e7d6c5b4a3210fedcba9876543210",
                "Support alias",
                "escalations@support.acme-demo.internal",
            ], [2, 4, 6]),
            ("demo internal links", [
                "Session sess_a1b2c3d4e5f6789012345678",
                "SSN (fake) 078-05-1120",
            ], [0, 1]),
            ("demo deploy log", [
                "$ deploy --env staging",
                "✓ Connected to k8s.staging.acme-demo.internal",
                "→ Pushing image tagged registry.acme-demo.local/app:sha-9f3a2b1",
                "→ Auth header: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.demo.token.here",
                "→ Notifying oncall@pager.acme-demo.com via webhook",
                "→ DB migrate with postgres://readonly:R3ad0nlyP@ss!@db.internal.acme-demo.local/analytics",
                "✓ Deploy complete — ping (650) 555-2389 if issues",
            ], [3, 4, 5, 6]),
        ]

        var falsePositives: [String] = []
        var falseNegatives: [String] = []

        for fixture in corpus {
            let flagged = try await ShareSafeService.sensitiveLineIndices(from: fixture.lines, useSmartScan: false)
            for index in flagged.subtracting(fixture.expected) {
                falsePositives.append("\(fixture.name): [\(index)] \(fixture.lines[index])")
            }
            for index in fixture.expected.subtracting(flagged) {
                falseNegatives.append("\(fixture.name): [\(index)] \(fixture.lines[index])")
            }
        }

        if !falsePositives.isEmpty || !falseNegatives.isEmpty {
            let report = "FP: \(falsePositives)\nFN: \(falseNegatives)\n"
            try? report.write(toFile: "/tmp/share-safe-eval-failures.txt", atomically: true, encoding: .utf8)
        }
        #expect(falsePositives.isEmpty, "False positives:\n\(falsePositives.joined(separator: "\n"))")
        #expect(falseNegatives.isEmpty, "False negatives:\n\(falseNegatives.joined(separator: "\n"))")
    }

    @Test func twoColumnMergedLineRedactsInterleavedBackupEmail() {
        // Contact + billing columns share one OCR line when Y positions align.
        let group = [
            OCRTextObservation(text: "Backup email", boundingBox: CGRect(x: 42, y: 366, width: 78, height: 12)),
            OCRTextObservation(text: "jalvarez.personal@gmail-demo.net", boundingBox: CGRect(x: 198, y: 366, width: 256, height: 16)),
            OCRTextObservation(text: "Amex", boundingBox: CGRect(x: 508, y: 366, width: 36, height: 12)),
            OCRTextObservation(text: "3782 822463 10005", boundingBox: CGRect(x: 784, y: 366, width: 134, height: 12)),
        ]
        let redactable = ShareSafeLinePolicy.redactableObservations(in: group)
        let redactedText = Set(redactable.map(\.text))
        #expect(redactedText.contains("jalvarez.personal@gmail-demo.net"))
        #expect(redactedText.contains("3782 822463 10005"))
        #expect(!redactedText.contains("Backup email"))
        #expect(!redactedText.contains("Amex"))

        let bounds = CGRect(x: 0, y: 0, width: 960, height: 1200)
        let rects = ShareSafeService.rects(for: [group], flaggedIndices: [0], bounds: bounds)
        let emailCenter = CGPoint(x: 198 + 128, y: 366 + 8)
        #expect(rects.contains { $0.contains(emailCenter) })
    }

    @Test func smartScanPhoneCategoryRequiresRealPhoneMatch() {
        // Digit-dense status copy must not satisfy a hallucinated "phone" finding.
        let line = "Request ID 10234 · Status OK 20000 requests · v2.14.3 build 20250601"
        #expect(!ShareSafeLinePolicy.categoryPlausible(.phone, in: line))
        #expect(!ShareSafeLinePolicy.categoryPlausible(.payment, in: line))
        let filtered = ShareSafeLinePolicy.filterSmartScanFindings(
            [SmartScanFinding(lineIndex: 0, category: .phone)],
            lineTexts: [line],
            patternMatched: []
        )
        #expect(filtered.isEmpty)
        #expect(ShareSafeLinePolicy.categoryPlausible(.phone, in: "Call me at (415) 555-0192"))
    }

    @Test func wrappedSecretKeyFragmentIsRedactedAsContinuation() async throws {
        let lines = [
            "sk_test_51HqDemoKeyForShareSafeTestingOnly00",
            "001",
            "Webhook signing",
        ]
        let flagged = try await ShareSafeService.sensitiveLineIndices(from: lines, useSmartScan: false)
        #expect(flagged.contains(0))
        #expect(flagged.contains(1))
        #expect(!flagged.contains(2))
    }

    @Test func continuationDoesNotSwallowTitleCaseUICopy() {
        let lines = [
            "STRIPE_KEY=sk_live_4eC39HqLyjWDarjtT1zdp7dc",
            "Privacy",
        ]
        let expanded = ShareSafeLinePolicy.expandForContinuations([0], lineTexts: lines)
        #expect(!expanded.contains(1))
    }

    @Test func partialRedactionCoversOnlySensitiveRangeOfLine() {
        // "Deploy complete — ping (650) 555-2389 if issues" as one OCR observation:
        // only the phone number should be covered, not the surrounding words.
        let text = "Deploy complete — ping (650) 555-2389 if issues"
        let observation = OCRTextObservation(
            text: text,
            boundingBox: CGRect(x: 0, y: 100, width: CGFloat(text.count) * 10, height: 16)
        )
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 400)
        let rects = ShareSafeService.rects(for: [[observation]], flaggedIndices: [0], bounds: bounds)
        #expect(rects.count == 1)
        let phoneStart = CGFloat(text.distance(from: text.startIndex, to: text.range(of: "(650)")!.lowerBound)) * 10
        let phoneEnd = phoneStart + CGFloat("(650) 555-2389".count) * 10
        // Covers the number (with padding) but leaves the head and tail readable.
        #expect(rects[0].minX < phoneStart + 20 && rects[0].maxX > phoneEnd - 20)
        #expect(rects[0].minX > 100)
        #expect(rects[0].maxX < CGFloat(text.count) * 10 - 60)
    }

    @Test func partialRedactionAbsorbsSplitEmailTldFragment() {
        let group = [
            OCRTextObservation(text: "support@company", boundingBox: CGRect(x: 10, y: 20, width: 120, height: 18)),
            OCRTextObservation(text: ".internal", boundingBox: CGRect(x: 132, y: 20, width: 60, height: 18)),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 100)
        let rects = ShareSafeService.rects(for: [group], flaggedIndices: [0], bounds: bounds)
        #expect(rects.contains { $0.minX <= 10 && $0.maxX >= 192 })
    }

    @Test func envVarPartialRedactionKeepsVariableNameVisible() {
        let text = "DATABASE_URL=postgres://admin:SuperSecret123!@db.internal:5432/prod"
        let observation = OCRTextObservation(
            text: text,
            boundingBox: CGRect(x: 0, y: 50, width: CGFloat(text.count) * 10, height: 16)
        )
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 200)
        let rects = ShareSafeService.rects(for: [[observation]], flaggedIndices: [0], bounds: bounds)
        #expect(!rects.isEmpty)
        // "DATABASE_URL=" (13 chars ≈ 130pt) stays readable; the URL itself is covered.
        #expect(rects.allSatisfy { $0.minX > 60 })
        #expect(rects.contains { $0.maxX >= CGFloat(text.count) * 10 - 20 })
    }

    @Test func envVarPartialRedactionKeepsNameVisibleForShortSecrets() {
        let text = "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"
        let observation = OCRTextObservation(
            text: text,
            boundingBox: CGRect(x: 0, y: 80, width: CGFloat(text.count) * 10, height: 16)
        )
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 200)
        let ranges = PIIDetector.redactionRanges(in: text)
        #expect(ranges.count == 1)
        #expect(String(text[ranges[0]]) == "AKIAIOSFODNN7EXAMPLE")
        let rects = ShareSafeService.rects(for: [[observation]], flaggedIndices: [0], bounds: bounds)
        #expect(!rects.isEmpty)
        #expect(rects.allSatisfy { $0.minX >= 180 })
    }

    @Test func splitStripeSecretRedactsPrefixAndSuffix() {
        // Vision sometimes splits long sk_live keys mid-token.
        let group = [
            OCRTextObservation(
                text: "STRIPE_SECRET_KEY=sk_live_4e",
                boundingBox: CGRect(x: 0, y: 120, width: 280, height: 16)
            ),
            OCRTextObservation(
                text: "C39HqLyjWDarjtT1zdp7dc",
                boundingBox: CGRect(x: 290, y: 120, width: 200, height: 16)
            ),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 200)
        let rects = ShareSafeService.rects(for: [group], flaggedIndices: [0], bounds: bounds)
        #expect(rects.contains { $0.maxX >= 480 })
        #expect(rects.allSatisfy { $0.minX > 150 })
    }

    @Test func rectsSkipsFieldLabelObservations() {
        let groups = [
            [
                OCRTextObservation(text: "Name", boundingBox: CGRect(x: 10, y: 40, width: 40, height: 16)),
                OCRTextObservation(text: "Jordan Alvarez", boundingBox: CGRect(x: 120, y: 40, width: 100, height: 16)),
            ],
        ]
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 100)
        let rects = ShareSafeService.rects(for: groups, flaggedIndices: [0], bounds: bounds)
        #expect(rects.count == 1)
        #expect(rects[0].minX >= 100)
        #expect(rects[0].maxX <= 240)
    }
}

// MARK: - Capture profiles

@MainActor
struct CaptureProfileTests {
    @Test func manualChangesStopReportingTheLastAppliedProfileAsCurrent() {
        let settings = SettingsStore()
        let originalProfile = settings.exportProfile()
        defer {
            if let originalProfile {
                try? settings.importProfile(from: originalProfile)
            }
        }

        CaptureProfile.standard.apply(to: settings)
        #expect(CaptureProfile.standard.matches(settings))

        settings.saveToDiskAfterCapture = false
        #expect(!CaptureProfile.standard.matches(settings))
    }
}
