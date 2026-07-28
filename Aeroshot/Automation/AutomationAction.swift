import Foundation

nonisolated enum AutomationCaptureMode: String, CaseIterable, Codable, Sendable {
    case area, window, screen, lastRegion = "last-region", scrolling, text
    case recordArea = "record-area", recordScreen = "record-screen"

    var displayName: String {
        switch self {
        case .area: "an area capture"
        case .window: "a window capture"
        case .screen: "a full-screen capture"
        case .lastRegion: "the last capture region"
        case .scrolling: "a scrolling capture"
        case .text: "a text capture"
        case .recordArea: "an area recording"
        case .recordScreen: "a screen recording"
        }
    }
}

nonisolated enum AutomationExportPreset: String, CaseIterable, Codable, Sendable {
    case png, jpeg, gif, h264
}

nonisolated enum AutomationAction: Equatable, Sendable {
    case capture(AutomationCaptureMode)
    case openProject(URL)
    case exportPreset(AutomationExportPreset, project: URL, destination: URL)
    case reveal(URL)
    case privacyReview

    func allowsExternalURL(using confirm: (AutomationCaptureMode) -> Bool) -> Bool {
        guard case .capture(let mode) = self else { return true }
        return confirm(mode)
    }
}

nonisolated enum AutomationParseError: Error, Equatable, LocalizedError {
    case invalidScheme
    case unsupportedAction(String)
    case missingValue(String)
    case duplicateValue(String)
    case invalidValue(String)
    case unsafeFileURL

    var errorDescription: String? {
        switch self {
        case .invalidScheme: "The URL scheme must be aeroshot."
        case .unsupportedAction(let value): "Unsupported automation action: \(value)."
        case .missingValue(let value): "Missing required value: \(value)."
        case .duplicateValue(let value): "Value was supplied more than once: \(value)."
        case .invalidValue(let value): "Invalid automation value: \(value)."
        case .unsafeFileURL: "Only absolute local file paths are allowed."
        }
    }
}

nonisolated enum AutomationActionParser {
    static func parse(url: URL) throws -> AutomationAction {
        guard url.scheme?.lowercased() == "aeroshot" else { throw AutomationParseError.invalidScheme }
        guard url.user == nil, url.password == nil, url.port == nil else { throw AutomationParseError.invalidValue("authority") }
        let route = (url.host ?? "").lowercased()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let values = try queryValues(components?.queryItems ?? [])
        switch route {
        case "capture":
            try requireOnly(values, allowed: ["mode"])
            guard let raw = values["mode"] else { throw AutomationParseError.missingValue("mode") }
            guard let mode = AutomationCaptureMode(rawValue: raw.lowercased()) else { throw AutomationParseError.invalidValue("mode") }
            return .capture(mode)
        case "open-project":
            try requireOnly(values, allowed: ["path"])
            return .openProject(try localURL(values["path"], name: "path"))
        case "export":
            try requireOnly(values, allowed: ["preset", "project", "destination"])
            guard let raw = values["preset"], let preset = AutomationExportPreset(rawValue: raw.lowercased()) else {
                throw AutomationParseError.invalidValue("preset")
            }
            return .exportPreset(preset, project: try localURL(values["project"], name: "project"), destination: try localURL(values["destination"], name: "destination"))
        case "reveal":
            try requireOnly(values, allowed: ["path"])
            return .reveal(try localURL(values["path"], name: "path"))
        case "privacy-review":
            try requireOnly(values, allowed: [])
            return .privacyReview
        default: throw AutomationParseError.unsupportedAction(route)
        }
    }

    static func parse(arguments: [String]) throws -> AutomationAction? {
        guard let index = arguments.firstIndex(of: "--aeroshot-action") else { return nil }
        guard arguments.indices.contains(index + 1) else { throw AutomationParseError.missingValue("action") }
        let action = arguments[index + 1]
        let tail = Array(arguments.dropFirst(index + 2))
        guard tail.count.isMultiple(of: 2) else { throw AutomationParseError.missingValue("argument value") }
        var values: [String: String] = [:]
        for pair in stride(from: 0, to: tail.count, by: 2) {
            let key = tail[pair]
            guard key.hasPrefix("--") else { throw AutomationParseError.invalidValue(key) }
            let normalized = String(key.dropFirst(2))
            guard values.updateValue(tail[pair + 1], forKey: normalized) == nil else { throw AutomationParseError.duplicateValue(normalized) }
        }
        func require(_ key: String) throws -> String {
            guard let value = values[key] else { throw AutomationParseError.missingValue(key) }
            return value
        }
        switch action {
        case "capture":
            try requireOnly(values, allowed: ["mode"])
            guard let mode = AutomationCaptureMode(rawValue: try require("mode")) else { throw AutomationParseError.invalidValue("mode") }
            return .capture(mode)
        case "open-project":
            try requireOnly(values, allowed: ["path"])
            return .openProject(try localURL(try require("path"), name: "path"))
        case "export":
            try requireOnly(values, allowed: ["preset", "project", "destination"])
            guard let preset = AutomationExportPreset(rawValue: try require("preset")) else { throw AutomationParseError.invalidValue("preset") }
            return .exportPreset(preset, project: try localURL(try require("project"), name: "project"), destination: try localURL(try require("destination"), name: "destination"))
        case "reveal":
            try requireOnly(values, allowed: ["path"])
            return .reveal(try localURL(try require("path"), name: "path"))
        case "privacy-review":
            try requireOnly(values, allowed: [])
            return .privacyReview
        default: throw AutomationParseError.unsupportedAction(action)
        }
    }

    private static func queryValues(_ items: [URLQueryItem]) throws -> [String: String] {
        var result: [String: String] = [:]
        for item in items {
            guard let value = item.value, !value.isEmpty else { throw AutomationParseError.missingValue(item.name) }
            guard result.updateValue(value, forKey: item.name) == nil else { throw AutomationParseError.duplicateValue(item.name) }
        }
        return result
    }

    private static func requireOnly(_ values: [String: String], allowed: Set<String>) throws {
        if let key = values.keys.first(where: { !allowed.contains($0) }) { throw AutomationParseError.invalidValue(key) }
    }

    static func localURL(_ value: String?, name: String) throws -> URL {
        guard let value, !value.isEmpty else { throw AutomationParseError.missingValue(name) }
        guard !value.contains("\0") else { throw AutomationParseError.unsafeFileURL }
        let url: URL
        if let parsed = URL(string: value), parsed.scheme != nil {
            guard parsed.isFileURL, parsed.host == nil || parsed.host == "localhost" else { throw AutomationParseError.unsafeFileURL }
            url = parsed
        } else {
            guard value.hasPrefix("/") else { throw AutomationParseError.unsafeFileURL }
            url = URL(fileURLWithPath: value)
        }
        let standardized = url.standardizedFileURL
        guard standardized.path.hasPrefix("/"), !standardized.path.isEmpty else { throw AutomationParseError.unsafeFileURL }
        return standardized
    }
}
