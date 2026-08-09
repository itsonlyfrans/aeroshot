import Combine
import ScreenCaptureKit

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var hasPermission: Bool = false

    private let preflightAccess: () -> Bool

    init(preflightAccess: @escaping () -> Bool = CGPreflightScreenCaptureAccess) {
        self.preflightAccess = preflightAccess
    }

    func preflight() -> Bool {
        let ok = preflightAccess()
        hasPermission = ok
        return ok
    }

    /// Checks capture access without prompting. Permission requests belong to
    /// explicit onboarding and Settings actions.
    @discardableResult
    func ensurePermission() async -> Bool {
        guard preflight() else {
            ToastController.shared.show(
                "Screen Recording permission is required.",
                symbol: "exclamationmark.triangle"
            )
            return false
        }
        // Preflight is authoritative for whether we should show the TCC sheet.
        // ScreenCaptureKit can fail transiently even when access is granted.
        _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        hasPermission = true
        return true
    }
}
