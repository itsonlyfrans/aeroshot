import AppKit

@objc(AeroshotAutomationCommand)
final class AeroshotAutomationCommand: NSScriptCommand, @unchecked Sendable {
    nonisolated override init(commandDescription: NSScriptCommandDescription) {
        super.init(commandDescription: commandDescription)
    }

    nonisolated override func performDefaultImplementation() -> Any? {
        let actionName = directParameter as? String ?? ""
        let outcome: ScriptOutcome = MainActor.assumeIsolated { Self.performOnMainActor(actionName) }
        if let error = outcome.error {
            scriptErrorNumber = -1708
            scriptErrorString = error
        }
        return outcome.message
    }

    private nonisolated struct ScriptOutcome: Sendable { let message: String; let error: String? }

    private static func performOnMainActor(_ actionName: String) -> ScriptOutcome {
        guard let delegate = NSApp.delegate as? AppDelegate else { return .init(message: "Aeroshot is not ready.", error: "Aeroshot is not ready.") }
        do {
            let action = try AutomationActionParser.parse(arguments: ["aeroshot", "--aeroshot-action"] + actionName.split(separator: " ").map(String.init))
            guard let action else { throw AutomationParseError.missingValue("action") }
            let result = delegate.automationRouter.route(action)
            return .init(message: result.message, error: result.succeeded ? nil : result.message)
        } catch {
            return .init(message: error.localizedDescription, error: error.localizedDescription)
        }
    }
}
