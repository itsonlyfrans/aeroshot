import AppKit

@objc(AeroshotAutomationCommand)
final class AeroshotAutomationCommand: NSScriptCommand, @unchecked Sendable {
    private nonisolated static let forwardedArgumentsPrefix = "aeroshot-arguments:"

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
        guard let delegate = AppDelegate.current else { return .init(message: "Aeroshot is not ready.", error: "Aeroshot is not ready.") }
        do {
            let action = try AutomationActionParser.parse(arguments: launchArguments(from: actionName))
            guard let action else { throw AutomationParseError.missingValue("action") }
            let result = delegate.automationRouter.route(action)
            return .init(message: result.message, error: result.succeeded ? nil : result.message)
        } catch {
            return .init(message: error.localizedDescription, error: error.localizedDescription)
        }
    }

    @MainActor
    static func forwardLaunchArguments(_ arguments: [String]) throws -> String? {
        guard try AutomationActionParser.parse(arguments: arguments) != nil else { return nil }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            throw AutomationForwardingError.runningInstanceUnavailable
        }
        var runningApp: NSRunningApplication?
        for _ in 0..<100 {
            runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .first(where: { $0.processIdentifier != currentPID && !$0.isTerminated && $0.isFinishedLaunching })
            if runningApp != nil { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard let runningApp else { throw AutomationForwardingError.runningInstanceUnavailable }

        let event = NSAppleEventDescriptor(
            eventClass: 0x41654175, // AeAu
            eventID: 0x52756E41, // RunA
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: runningApp.processIdentifier),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(
            NSAppleEventDescriptor(string: try forwardedDirectParameter(for: arguments)),
            forKeyword: AEKeyword(keyDirectObject)
        )
        let reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: 10)
        if let errorNumber = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber)), errorNumber.int32Value != 0 {
            let message = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorString))?.stringValue
                ?? "The running Aeroshot instance rejected the action."
            throw AutomationForwardingError.remote(message)
        }
        guard let message = reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue else {
            throw AutomationForwardingError.invalidReply
        }
        return message
    }

    nonisolated static func forwardedDirectParameter(for arguments: [String]) throws -> String {
        forwardedArgumentsPrefix + (try JSONEncoder().encode(arguments)).base64EncodedString()
    }

    nonisolated static func launchArguments(from directParameter: String) throws -> [String] {
        guard directParameter.hasPrefix(forwardedArgumentsPrefix) else {
            return ["aeroshot", "--aeroshot-action"] + directParameter.split(separator: " ").map(String.init)
        }
        let encoded = directParameter.dropFirst(forwardedArgumentsPrefix.count)
        guard let data = Data(base64Encoded: String(encoded)) else { throw AutomationForwardingError.invalidPayload }
        return try JSONDecoder().decode([String].self, from: data)
    }
}

nonisolated enum AutomationForwardingError: Error, Equatable, LocalizedError {
    case runningInstanceUnavailable
    case invalidPayload
    case invalidReply
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .runningInstanceUnavailable: "The running Aeroshot instance could not receive the action."
        case .invalidPayload: "The forwarded Aeroshot action was invalid."
        case .invalidReply: "The running Aeroshot instance did not return a result."
        case .remote(let message): message
        }
    }
}
