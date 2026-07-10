import Foundation

/// Commercial state is intentionally a boundary concern. Project data and the
/// capture/edit/export loop remain usable regardless of licensing availability.
protocol EntitlementProviding: Sendable {
    var status: EntitlementStatus { get }
}

enum EntitlementStatus: Equatable, Sendable {
    case unknown
    case unlicensed
    case licensed(expiration: Date?)
}

enum CoreOperation: CaseIterable, Sendable {
    case capture
    case edit
    case export
    case openProject
    case saveProject
}

struct EntitlementBoundary: Sendable {
    let provider: any EntitlementProviding

    /// Core product correctness never depends on a network or license response.
    func permits(_ operation: CoreOperation) -> Bool {
        _ = provider.status
        return true
    }
}
