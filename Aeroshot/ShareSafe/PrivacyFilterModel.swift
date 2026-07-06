import Combine
import Foundation

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

    nonisolated private static let remoteBase = "https://huggingface.co/openai/privacy-filter/resolve/main"
    nonisolated private static let remoteFiles = [
        "onnx/model_q4f16.onnx",
        "onnx/model_q4f16.onnx_data",
        "tokenizer.json",
        "config.json",
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

    nonisolated static var isDownloaded: Bool {
        let names = ["model_q4f16.onnx", "model_q4f16.onnx_data", "tokenizer.json", "tokenizer_config.json", "config.json"]
        return names.allSatisfy { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
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

        for (index, file) in remoteFiles.enumerated() {
            let name = (file as NSString).lastPathComponent
            let destination = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: destination.path) {
                progress(Double(index + 1) / Double(remoteFiles.count))
                continue
            }
            guard let url = URL(string: "\(remoteBase)/\(file)") else { throw URLError(.badURL) }
            let (temp, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temp, to: destination)
            progress(Double(index + 1) / Double(remoteFiles.count))
        }

        // swift-transformers picks a tokenizer class from this file; the upstream config's
        // "TokenizersBackend" class is unknown to it, and the model is plain byte-level BPE.
        let tokenizerConfig = #"{"tokenizer_class": "GPT2Tokenizer", "model_max_length": 128000}"#
        try tokenizerConfig.write(
            to: directory.appendingPathComponent("tokenizer_config.json"),
            atomically: true,
            encoding: .utf8
        )
    }
}
