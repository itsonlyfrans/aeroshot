import Foundation

nonisolated enum UploadService {
    struct UploadResponse: Decodable {
        let url: String?
        let link: String?

        var resolvedURL: URL? {
            if let url, let parsed = URL(string: url) { return parsed }
            if let link, let parsed = URL(string: link) { return parsed }
            return nil
        }
    }

    enum UploadError: LocalizedError, Equatable {
        case invalidWebhook
        case badResponse
        case missingURL

        var errorDescription: String? {
            switch self {
            case .invalidWebhook: return "Upload webhook URL is invalid."
            case .badResponse: return "Upload server returned an error."
            case .missingURL: return "Upload response did not include a link."
            }
        }
    }

    static func upload(fileURL: URL, webhookURL: String) async throws -> URL {
        guard let endpoint = URL(string: webhookURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              endpoint.scheme?.lowercased() == "https",
              endpoint.host != nil else {
            throw UploadError.invalidWebhook
        }

        let boundary = "Aeroshot-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Aeroshot-\(UUID().uuidString).upload")
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        try writeMultipartBody(fileURL: fileURL, to: bodyURL, boundary: boundary)

        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: bodyURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UploadError.badResponse
        }

        if let decoded = try? JSONDecoder().decode(UploadResponse.self, from: data),
           let url = decoded.resolvedURL {
            return url
        }

        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: text), url.scheme != nil {
            return url
        }

        throw UploadError.missingURL
    }

    static func writeMultipartBody(fileURL: URL, to destination: URL, boundary: String) throws {
        let filename = fileURL.lastPathComponent
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
        let header = "--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
            + "Content-Type: application/octet-stream\r\n\r\n"
        let footer = "\r\n--\(boundary)--\r\n"
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let input = try FileHandle(forReadingFrom: fileURL)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? input.close()
            try? output.close()
        }
        try output.write(contentsOf: Data(header.utf8))
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
        try output.write(contentsOf: Data(footer.utf8))
    }
}
