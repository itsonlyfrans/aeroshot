import Foundation

nonisolated struct DiagnosticSupportBundle: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let createdAt: Date
    let events: [DiagnosticEvent]
}

nonisolated enum DiagnosticSupportBundleError: Error, Equatable {
    case consentRequired
    case destinationIsDirectory
}

/// An in-memory, local-only collector. It intentionally has no networking API.
@MainActor
final class LocalDiagnostics {
    private let consent: DiagnosticConsentStore
    private let maximumEventCount: Int
    private(set) var events: [DiagnosticEvent] = []

    init(consent: DiagnosticConsentStore, maximumEventCount: Int = 200) {
        self.consent = consent
        self.maximumEventCount = max(1, maximumEventCount)
    }

    func record(_ event: DiagnosticEvent) {
        guard consent.isEnabled else { return }
        events.append(event)
        if events.count > maximumEventCount {
            events.removeFirst(events.count - maximumEventCount)
        }
    }

    func removeAll() {
        events.removeAll(keepingCapacity: false)
    }

    /// Writes one explicit local JSON bundle. No upload or sender exists.
    @discardableResult
    func exportSupportBundle(to destination: URL, now: Date = Date()) throws -> URL {
        guard consent.isEnabled else { throw DiagnosticSupportBundleError.consentRequired }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            throw DiagnosticSupportBundleError.destinationIsDirectory
        }
        let bundle = DiagnosticSupportBundle(schemaVersion: 1, createdAt: now, events: events)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // macOS support bundles must remain readable immediately after the atomic rename. File
        // protection can transiently deny the exporting process itself when tests or exports run
        // concurrently, and provides no useful desktop guarantee beyond the user's volume policy.
        try encoder.encode(bundle).write(to: destination, options: .atomic)
        return destination
    }
}
