import SwiftUI

@main
struct ScreenCaptureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Placeholder scene required by SwiftUI App lifecycle.
        // Settings UI is opened via SettingsWindowController (AppKit).
        Settings { EmptyView() }
    }
}
