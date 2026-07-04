import AppKit

@MainActor
enum AppStateAccessor {
    static var shared: AppState? {
        (NSApp.delegate as? AppDelegate)?.appState
    }
}
