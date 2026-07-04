import AppIntents

struct OpenAllInOneIntent: AppIntent {
    static var title: LocalizedStringResource = "Open All-in-One"
    static var description = IntentDescription("Show the All-in-One capture HUD.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStateAccessor.shared?.allInOneController.begin()
        return .result()
    }
}

struct CaptureAreaIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Area"
    static var description = IntentDescription("Capture a selected region of the screen.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStateAccessor.shared?.captureController.beginAreaCapture()
        return .result()
    }
}

struct CaptureWindowIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Window"
    static var description = IntentDescription("Capture the frontmost window under the cursor.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStateAccessor.shared?.captureController.beginWindowCapture()
        return .result()
    }
}

struct CaptureScreenIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Screen"
    static var description = IntentDescription("Capture the full screen.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStateAccessor.shared?.captureController.captureFullScreen()
        return .result()
    }
}

struct CaptureScrollingIntent: AppIntent {
    static var title: LocalizedStringResource = "Scrolling Capture"
    static var description = IntentDescription("Capture a long scrollable region.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStateAccessor.shared?.scrollingCaptureController.begin()
        return .result()
    }
}

struct CaptureTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Text"
    static var description = IntentDescription("Capture text with OCR from a screen region.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStateAccessor.shared?.ocrCaptureController.begin()
        return .result()
    }
}

struct RecordAreaIntent: AppIntent {
    static var title: LocalizedStringResource = "Record Area"
    static var description = IntentDescription("Record video of a selected screen region.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStateAccessor.shared?.recordingController.beginAreaRecording()
        return .result()
    }
}

struct RecordScreenIntent: AppIntent {
    static var title: LocalizedStringResource = "Record Screen"
    static var description = IntentDescription("Record video of the full screen.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStateAccessor.shared?.recordingController.beginScreenRecording()
        return .result()
    }
}

struct OpenHistoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Open History"
    static var description = IntentDescription("Open the capture history window.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStateAccessor.shared?.showHistoryWindow()
        return .result()
    }
}

struct OpenSettingsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Settings"
    static var description = IntentDescription("Open ScreenCapture settings.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStateAccessor.shared?.showSettingsWindow()
        return .result()
    }
}
