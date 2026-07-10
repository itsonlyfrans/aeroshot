import Foundation

nonisolated enum ExportDestinationKind: String, Codable, Equatable, Sendable {
    case file
    case revealInFinder
    case clipboard
    case drag
    case shareSheet
    case userOwnedEndpoint
}

nonisolated enum ExportDestinationAvailability: Equatable, Sendable {
    case available
    case requiresUserInteraction
}

nonisolated enum EndpointMethod: String, Codable, Equatable, Sendable {
    case post = "POST"
    case put = "PUT"
}

nonisolated struct UserOwnedEndpoint: Codable, Equatable, Sendable {
    let url: URL
    let method: EndpointMethod
    let headers: [String: String]

    init(url: URL, method: EndpointMethod, headers: [String: String] = [:]) throws {
        guard url.scheme?.lowercased() == "https", url.host != nil else {
            throw ExportDestinationError.endpointMustUseHTTPS
        }
        guard url.user == nil, url.password == nil else {
            throw ExportDestinationError.endpointCannotContainCredentials
        }
        guard headers.allSatisfy({ key, value in
            !key.isEmpty && !key.contains(":" ) && !key.contains("\r") && !key.contains("\n")
                && !value.contains("\r") && !value.contains("\n")
        }) else { throw ExportDestinationError.invalidEndpointHeader }
        self.url = url
        self.method = method
        self.headers = headers
    }

    private enum CodingKeys: String, CodingKey { case url, method, headers }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            url: values.decode(URL.self, forKey: .url),
            method: values.decode(EndpointMethod.self, forKey: .method),
            headers: values.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        )
    }
}

nonisolated struct FileDestinationRequest: Equatable, Sendable { let itemURL: URL }
nonisolated struct FinderDestinationRequest: Equatable, Sendable { let itemURL: URL }
nonisolated struct ClipboardDestinationRequest: Equatable, Sendable { let itemURL: URL }
nonisolated struct DragDestinationRequest: Equatable, Sendable { let itemURL: URL }
nonisolated struct ShareSheetDestinationRequest: Equatable, Sendable { let itemURL: URL }
nonisolated struct EndpointDestinationRequest: Equatable, Sendable {
    let url: URL
    let method: EndpointMethod
    let headers: [String: String]
    let localFileURL: URL
}

nonisolated enum ExportDestinationRequest: Equatable, Sendable {
    case file(FileDestinationRequest)
    case revealInFinder(FinderDestinationRequest)
    case clipboard(ClipboardDestinationRequest)
    case drag(DragDestinationRequest)
    case shareSheet(ShareSheetDestinationRequest)
    case endpoint(EndpointDestinationRequest)
}

nonisolated enum ExportDestination: Equatable, Sendable {
    case file(URL)
    case revealInFinder(URL)
    case clipboard
    case drag
    case shareSheet
    case userOwnedEndpoint(UserOwnedEndpoint)

    var kind: ExportDestinationKind {
        switch self {
        case .file: .file
        case .revealInFinder: .revealInFinder
        case .clipboard: .clipboard
        case .drag: .drag
        case .shareSheet: .shareSheet
        case .userOwnedEndpoint: .userOwnedEndpoint
        }
    }

    var availability: ExportDestinationAvailability {
        switch self {
        case .drag, .shareSheet: .requiresUserInteraction
        default: .available
        }
    }

    /// Produces metadata for an app-owned adapter. It performs no I/O or network access.
    func request(for exportedFileURL: URL) throws -> ExportDestinationRequest {
        guard exportedFileURL.isFileURL else { throw ExportDestinationError.outputMustBeLocalFile }
        switch self {
        case .file(let destination): return .file(.init(itemURL: destination))
        case .revealInFinder(let destination): return .revealInFinder(.init(itemURL: destination))
        case .clipboard: return .clipboard(.init(itemURL: exportedFileURL))
        case .drag: return .drag(.init(itemURL: exportedFileURL))
        case .shareSheet: return .shareSheet(.init(itemURL: exportedFileURL))
        case .userOwnedEndpoint(let endpoint):
            return .endpoint(.init(
                url: endpoint.url, method: endpoint.method, headers: endpoint.headers,
                localFileURL: exportedFileURL
            ))
        }
    }
}

nonisolated enum ExportDestinationError: Error, Equatable, Sendable {
    case endpointMustUseHTTPS
    case endpointCannotContainCredentials
    case invalidEndpointHeader
    case outputMustBeLocalFile
}
