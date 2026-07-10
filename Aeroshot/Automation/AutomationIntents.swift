import AppIntents
import AppKit

@available(macOS 14.0, *)
struct AutomationCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Aeroshot Capture"
    static let description = IntentDescription("Starts a bounded local capture action in Aeroshot.")
    static let openAppWhenRun = true
    @Parameter(title: "Mode") var mode: String
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let value = AutomationCaptureMode(rawValue: mode.lowercased()), let delegate = NSApp.delegate as? AppDelegate else {
            return .result(dialog: "Unsupported capture mode.")
        }
        return .result(dialog: IntentDialog(stringLiteral: delegate.automationRouter.route(.capture(value)).message))
    }
}

@available(macOS 14.0, *)
struct AutomationPrivacyReviewIntent: AppIntent {
    static let title: LocalizedStringResource = "Review Aeroshot Privacy"
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let delegate = NSApp.delegate as? AppDelegate else { return .result(dialog: "Aeroshot is not ready.") }
        return .result(dialog: IntentDialog(stringLiteral: delegate.automationRouter.route(.privacyReview).message))
    }
}
