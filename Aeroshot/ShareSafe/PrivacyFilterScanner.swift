import Foundation
import OnnxRuntimeBindings
import Tokenizers

enum PrivacyFilterScanError: Error, Equatable {
    case modelUnavailable
    case invalidModelOutput
}

/// Runs the on-device OpenAI privacy-filter token classifier over OCR lines and maps
/// its BIOES labels into `SmartScanFinding`s. Findings go through the same
/// `ShareSafeLinePolicy` filtering as Apple Intelligence results, so weak categories
/// (names, record numbers, URLs) can only redact with corroboration.
actor PrivacyFilterScanner {
    static let shared = PrivacyFilterScanner()

    private var session: ORTSession?
    private var env: ORTEnv?
    private var tokenizer: Tokenizer?
    private var id2label: [Int: String] = [:]

    /// OCR of a single screen is far below this; guards against pathological input.
    private static let maxTokens = 8192

    func findings(lineTexts: [String]) async throws -> [SmartScanFinding] {
        guard !lineTexts.isEmpty else { return [] }
        guard PrivacyFilterModel.isDownloaded else { throw PrivacyFilterScanError.modelUnavailable }
        try await loadIfNeeded()
        return try scan(lineTexts: lineTexts)
    }

    private func loadIfNeeded() async throws {
        if session != nil, tokenizer != nil { return }
        try PrivacyFilterModel.verifyInstalledArtifacts()
        let directory = PrivacyFilterModel.directory

        struct ModelConfig: Decodable { let id2label: [String: String] }
        let configData = try Data(contentsOf: directory.appendingPathComponent("config.json"))
        let config = try JSONDecoder().decode(ModelConfig.self, from: configData)
        id2label = Dictionary(uniqueKeysWithValues: config.id2label.compactMap { key, value in
            Int(key).map { ($0, value) }
        })

        tokenizer = try await AutoTokenizer.from(modelFolder: directory)

        let env = try ORTEnv(loggingLevel: .warning)
        self.env = env
        session = try ORTSession(env: env, modelPath: PrivacyFilterModel.modelURL.path, sessionOptions: nil)
    }

    private func scan(lineTexts: [String]) throws -> [SmartScanFinding] {
        guard let session, let tokenizer, !id2label.isEmpty else {
            throw PrivacyFilterScanError.invalidModelOutput
        }

        // The model is contextual, so feed the whole screen as one newline-joined
        // sequence. Lines are tokenized individually so each token's owning line is
        // known by construction — no offset mapping needed.
        let newline = tokenizer.encode(text: "\n")
        var ids: [Int64] = []
        var lineForToken: [Int] = []

        for (index, line) in lineTexts.enumerated() {
            if index > 0 {
                ids.append(contentsOf: newline.map(Int64.init))
                lineForToken.append(contentsOf: Array(repeating: -1, count: newline.count))
            }
            let lineIds = tokenizer.encode(text: line)
            ids.append(contentsOf: lineIds.map(Int64.init))
            lineForToken.append(contentsOf: Array(repeating: index, count: lineIds.count))
            if ids.count >= Self.maxTokens { break }
        }
        if ids.count > Self.maxTokens {
            ids = Array(ids.prefix(Self.maxTokens))
            lineForToken = Array(lineForToken.prefix(Self.maxTokens))
        }
        guard !ids.isEmpty else { return [] }

        let count = ids.count
        var mask = [Int64](repeating: 1, count: count)
        let idsData = ids.withUnsafeMutableBufferPointer {
            NSMutableData(bytes: $0.baseAddress!, length: count * MemoryLayout<Int64>.size)
        }
        let maskData = mask.withUnsafeMutableBufferPointer {
            NSMutableData(bytes: $0.baseAddress!, length: count * MemoryLayout<Int64>.size)
        }
        let shape: [NSNumber] = [1, NSNumber(value: count)]
        let inputIds = try ORTValue(tensorData: idsData, elementType: .int64, shape: shape)
        let attention = try ORTValue(tensorData: maskData, elementType: .int64, shape: shape)

        let outputs = try session.run(
            withInputs: ["input_ids": inputIds, "attention_mask": attention],
            outputNames: ["logits"],
            runOptions: nil
        )
        guard let logitsValue = outputs["logits"] else {
            throw PrivacyFilterScanError.invalidModelOutput
        }
        let logitsData = try logitsValue.tensorData() as Data

        let numLabels = id2label.count
        let floats: [Float] = logitsData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        guard floats.count >= count * numLabels else {
            throw PrivacyFilterScanError.invalidModelOutput
        }

        var results = Set<SmartScanFinding>()
        for token in 0..<count {
            let line = lineForToken[token]
            guard line >= 0 else { continue }
            let base = token * numLabels
            var best = 0
            var bestScore = -Float.infinity
            for label in 0..<numLabels where floats[base + label] > bestScore {
                bestScore = floats[base + label]
                best = label
            }
            guard let label = id2label[best], label != "O" else { continue }
            results.insert(SmartScanFinding(lineIndex: line, category: SmartScanCategory(privacyFilterLabel: label)))
        }
        return Array(results)
    }
}
