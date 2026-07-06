import AppIntents

struct OpenAllInOneIntent: AppIntent {
    static let title: LocalizedStringResource = "Open All-in-One"
    static let description = IntentDescription("Show the All-in-One capture HUD.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStateAccessor.shared?.allInOneController.begin()
        return .result()
    }
}

struct CaptureAreaIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Area"
    static let description = IntentDescription("Capture a selected region of the screen.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStateAccessor.shared?.captureController.beginAreaCapture()
        return .result()
    }
}

struct CaptureWindowIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Window"
    static let description = IntentDescription("Capture the frontmost window under the cursor.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStateAccessor.shared?.captureController.beginWindowCapture()
        return .result()
    }
}

struct CaptureScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Screen"
    static let description = IntentDescription("Capture the full screen.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStateAccessor.shared?.captureController.captureFullScreen()
        return .result()
    }
}

struct CaptureScrollingIntent: AppIntent {
    static let title: LocalizedStringResource = "Scrolling Capture"
    static let description = IntentDescription("Capture a long scrollable region.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStateAccessor.shared?.scrollingCaptureController.begin()
        return .result()
    }
}

struct CaptureTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Text"
    static let description = IntentDescription("Capture text with OCR from a screen region.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStateAccessor.shared?.ocrCaptureController.begin()
        return .result()
    }
}

struct RecordAreaIntent: AppIntent {
    static let title: LocalizedStringResource = "Record Area"
    static let description = IntentDescription("Record video of a selected screen region.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStateAccessor.shared?.recordingController.beginAreaRecording()
        return .result()
    }
}

struct RecordScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Record Screen"
    static let description = IntentDescription("Record video of the full screen.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStateAccessor.shared?.recordingController.beginScreenRecording()
        return .result()
    }
}

struct OpenHistoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Open History"
    static let description = IntentDescription("Open the capture history window.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStateAccessor.shared?.showHistoryWindow()
        return .result()
    }
}

struct CaptureLastRegionIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Last Region"
    static let description = IntentDescription("Capture the same screen region as your previous area capture.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStateAccessor.shared?.captureController.captureLastRegion()
        return .result()
    }
}

struct OpenSettingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Settings"
    static let description = IntentDescription("Open Aeroshot settings.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppStateAccessor.shared?.showSettingsWindow()
        return .result()
    }
}
