import Foundation

/// Local policy for deciding what may leave the process. This package deliberately
/// contains no transport: a future sender must consume `sanitizedEvent(_:)` and
/// separately honor the user's current consent.
struct TelemetryPolicy: Sendable {
    enum Consent: String, Codable, Sendable {
        case disabled
        case enabled
    }

    struct Event: Equatable, Sendable {
        let name: String
        let properties: [String: String]
    }

    static let allowedEventNames: Set<String> = [
        "app_launch", "capture_completed", "export_completed", "operation_failed"
    ]

    static let allowedPropertyNames: Set<String> = [
        "app_version", "build", "operation", "result", "format", "duration_bucket"
    ]

    private static let sensitiveFragments = [
        "content", "path", "file", "url", "title", "text", "ocr", "clipboard",
        "email", "name", "token", "secret", "key", "host", "device", "user"
    ]

    let analyticsConsent: Consent
    let crashConsent: Consent

    init(analyticsConsent: Consent = .disabled, crashConsent: Consent = .disabled) {
        self.analyticsConsent = analyticsConsent
        self.crashConsent = crashConsent
    }

    var permitsAnalytics: Bool { analyticsConsent == .enabled }
    var permitsCrashReports: Bool { crashConsent == .enabled }

    func sanitizedEvent(_ event: Event) -> Event? {
        guard permitsAnalytics, Self.allowedEventNames.contains(event.name) else { return nil }

        let properties = event.properties.reduce(into: [String: String]()) { result, pair in
            let key = pair.key.lowercased()
            guard Self.allowedPropertyNames.contains(key),
                  !Self.sensitiveFragments.contains(where: key.contains),
                  pair.value.utf8.count <= 64,
                  !pair.value.contains("/"),
                  !pair.value.contains("@"),
                  URL(string: pair.value)?.scheme == nil
            else { return }
            result[key] = pair.value
        }
        return Event(name: event.name, properties: properties)
    }
}
