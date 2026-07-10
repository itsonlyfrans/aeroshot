import Foundation

/// Local diagnostics are deliberately opt-in. Merely constructing this store
/// never creates or changes a preference.
@MainActor
final class DiagnosticConsentStore {
    private static let consentKey = "diagnostics.explicitConsent"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        defaults.object(forKey: Self.consentKey) as? Bool ?? false
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.consentKey)
    }

    func resetConsent() {
        defaults.removeObject(forKey: Self.consentKey)
    }
}
