import Foundation

enum UploadService {
    struct UploadResponse: Decodable {
        let url: String?
        let link: String?

        var resolvedURL: URL? {
            if let url, let parsed = URL(string: url) { return parsed }
            if let link, let parsed = URL(string: link) { return parsed }
            return nil
        }
    }

    enum UploadError: LocalizedError {
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
              endpoint.scheme == "https" || endpoint.scheme == "http" else {
            throw UploadError.invalidWebhook
        }

        let boundary = "Aeroshot-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
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
}
