import Combine
import Foundation

nonisolated enum PrivacyFilterModelError: Error, Equatable, LocalizedError {
    case integrityCheckFailed(String)

    var errorDescription: String? {
        switch self {
        case .integrityCheckFailed(let name):
            "The downloaded privacy model failed its integrity check (\(name)). Remove it and try again."
        }
    }
}

/// Locates and downloads the on-device OpenAI privacy-filter model
/// (Apache 2.0 token classifier, ONNX q4f16 build, ~809 MB).
/// Files live in Application Support so the app bundle stays small.
final class PrivacyFilterModel: ObservableObject {
    static let shared = PrivacyFilterModel()

    enum State: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case ready
        case failed(String)
    }

    @Published private(set) var state: State

    static let downloadSizeLabel = "809 MB"

    nonisolated static let artifactRevision = "7ffa9a043d54d1be65afb281eddf0ffbe629385b"
    nonisolated private static let remoteBase =
        "https://huggingface.co/openai/privacy-filter/resolve/\(artifactRevision)"
    nonisolated private static let remoteArtifacts: [(path: String, sha256: String)] = [
        ("onnx/model_q4f16.onnx", "eaae4e83cf1345a60abe333ed882b55fe5775d1dfbf34b9b269e5e5416f45e5b"),
        ("onnx/model_q4f16.onnx_data", "6d4dde787e03ace283c45d4e32a94eec32b6cfcc242e7219bea96f5b4c13569d"),
        ("tokenizer.json", "0614fe83cadab421296e664e1f48f4261fa8fef6e03e63bb75c20f38e37d07d3"),
        ("config.json", "b2b26a4a4a000639ad30b0c264adbefe365bdb567fbd7bb27303b8c438375bd1"),
    ]

    nonisolated static var directory: URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacy = base.appendingPathComponent("screencapture/PrivacyFilter", isDirectory: true)
        let modern = base.appendingPathComponent("Aeroshot/PrivacyFilter", isDirectory: true)
        if fileManager.fileExists(atPath: legacy.path), !fileManager.fileExists(atPath: modern.path) {
            try? fileManager.createDirectory(at: modern.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fileManager.moveItem(at: legacy, to: modern)
        }
        return modern
    }

    nonisolated static var modelURL: URL {
        directory.appendingPathComponent("model_q4f16.onnx")
    }

    nonisolated private static var integrityMarkerURL: URL {
        directory.appendingPathComponent("integrity-revision.txt")
    }

    nonisolated static var isDownloaded: Bool {
        let names = ["model_q4f16.onnx", "model_q4f16.onnx_data", "tokenizer.json", "tokenizer_config.json", "config.json"]
        guard names.allSatisfy({
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }) else { return false }
        if (try? String(contentsOf: integrityMarkerURL, encoding: .utf8)) == artifactRevision {
            return true
        }
        guard (try? verifyInstalledArtifacts()) != nil else { return false }
        try? artifactRevision.write(to: integrityMarkerURL, atomically: true, encoding: .utf8)
        return true
    }

    private init() {
        state = Self.isDownloaded ? .ready : .notDownloaded
    }

    func download() {
        if case .downloading = state { return }
        state = .downloading(progress: 0)
        Task {
            do {
                try await Self.fetchAll { progress in
                    Task { @MainActor in
                        let model = PrivacyFilterModel.shared
                        if case .downloading = model.state {
                            model.state = .downloading(progress: progress)
                        }
                    }
                }
                state = .ready
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: Self.directory)
        state = .notDownloaded
    }

    nonisolated private static func fetchAll(progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: integrityMarkerURL)

        for (index, artifact) in remoteArtifacts.enumerated() {
            let name = (artifact.path as NSString).lastPathComponent
            let destination = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: destination.path),
               (try? verifyArtifact(at: destination, expectedSHA256: artifact.sha256)) != nil {
                progress(Double(index + 1) / Double(remoteArtifacts.count))
                continue
            }
            try? FileManager.default.removeItem(at: destination)
            guard let url = URL(string: "\(remoteBase)/\(artifact.path)") else { throw URLError(.badURL) }
            let (temp, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            do {
                try verifyArtifact(at: temp, expectedSHA256: artifact.sha256)
            } catch {
                try? FileManager.default.removeItem(at: temp)
                throw error
            }
            try FileManager.default.moveItem(at: temp, to: destination)
            progress(Double(index + 1) / Double(remoteArtifacts.count))
        }

        // swift-transformers picks a tokenizer class from this file; the upstream config's
        // "TokenizersBackend" class is unknown to it, and the model is plain byte-level BPE.
        let tokenizerConfig = #"{"tokenizer_class": "GPT2Tokenizer", "model_max_length": 128000}"#
        try tokenizerConfig.write(
            to: directory.appendingPathComponent("tokenizer_config.json"),
            atomically: true,
            encoding: .utf8
        )
        try verifyInstalledArtifacts()
        try artifactRevision.write(to: integrityMarkerURL, atomically: true, encoding: .utf8)
    }

    nonisolated static func verifyInstalledArtifacts() throws {
        for artifact in remoteArtifacts {
            let name = (artifact.path as NSString).lastPathComponent
            do {
                try verifyArtifact(
                    at: directory.appendingPathComponent(name),
                    expectedSHA256: artifact.sha256
                )
            } catch {
                try? FileManager.default.removeItem(at: integrityMarkerURL)
                throw error
            }
        }
    }

    nonisolated static func verifyArtifact(at url: URL, expectedSHA256: String) throws {
        let name = url.lastPathComponent
        guard FileManager.default.fileExists(atPath: url.path),
              (try? AeroProjectPackageStore.sha256(ofFileAt: url)) == expectedSHA256
        else { throw PrivacyFilterModelError.integrityCheckFailed(name) }
    }
}
