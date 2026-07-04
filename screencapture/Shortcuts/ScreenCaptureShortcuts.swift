import AppIntents

struct ScreenCaptureShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenAllInOneIntent(),
            phrases: [
                "Open All-in-One with \(.applicationName)",
                "Show capture HUD with \(.applicationName)",
            ],
            shortTitle: "All-in-One",
            systemImageName: "camera.viewfinder"
        )
        AppShortcut(
            intent: CaptureAreaIntent(),
            phrases: [
                "Capture area with \(.applicationName)",
                "Take area screenshot with \(.applicationName)",
            ],
            shortTitle: "Capture Area",
            systemImageName: "rectangle.dashed"
        )
        AppShortcut(
            intent: CaptureLastRegionIntent(),
            phrases: [
                "Capture last region with \(.applicationName)",
            ],
            shortTitle: "Last Region",
            systemImageName: "arrow.counterclockwise"
        )
        AppShortcut(
            intent: CaptureWindowIntent(),
            phrases: [
                "Capture window with \(.applicationName)",
            ],
            shortTitle: "Capture Window",
            systemImageName: "macwindow"
        )
        AppShortcut(
            intent: CaptureScreenIntent(),
            phrases: [
                "Capture screen with \(.applicationName)",
                "Take full screen screenshot with \(.applicationName)",
            ],
            shortTitle: "Capture Screen",
            systemImageName: "display"
        )
        AppShortcut(
            intent: CaptureScrollingIntent(),
            phrases: [
                "Scrolling capture with \(.applicationName)",
            ],
            shortTitle: "Scrolling Capture",
            systemImageName: "arrow.up.and.down.text.horizontal"
        )
        AppShortcut(
            intent: CaptureTextIntent(),
            phrases: [
                "Capture text with \(.applicationName)",
                "OCR with \(.applicationName)",
            ],
            shortTitle: "Capture Text",
            systemImageName: "text.viewfinder"
        )
        AppShortcut(
            intent: RecordAreaIntent(),
            phrases: [
                "Record area with \(.applicationName)",
            ],
            shortTitle: "Record Area",
            systemImageName: "record.circle"
        )
        AppShortcut(
            intent: RecordScreenIntent(),
            phrases: [
                "Record screen with \(.applicationName)",
            ],
            shortTitle: "Record Screen",
            systemImageName: "record.circle.fill"
        )
        AppShortcut(
            intent: OpenHistoryIntent(),
            phrases: [
                "Open capture history with \(.applicationName)",
            ],
            shortTitle: "History",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}
