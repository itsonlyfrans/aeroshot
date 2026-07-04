import CoreGraphics
@preconcurrency import Vision

enum OCRService {
    /// Recognizes text in the image using Vision's accurate path.
    nonisolated static func recognizeText(in image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try performRecognition(on: image)
        }.value
    }

    private nonisolated static func performRecognition(on image: CGImage) throws -> String {
        var recognizedLines: [String] = []
        var recognitionError: Error?

        let request = VNRecognizeTextRequest { request, error in
            if let error {
                recognitionError = error
                return
            }
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            recognizedLines = observations.compactMap { $0.topCandidates(1).first?.string }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        if let recognitionError {
            throw recognitionError
        }
        return recognizedLines.joined(separator: "\n")
    }
}
