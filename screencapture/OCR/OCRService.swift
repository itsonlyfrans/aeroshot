import CoreGraphics
@preconcurrency import Vision

struct OCRTextObservation: Sendable {
    let text: String
    /// Full line bounding box in image pixels (top-left origin).
    let boundingBox: CGRect
}

enum OCRService {
    /// Recognizes text in the image using Vision's accurate path.
    nonisolated static func recognizeText(in image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try performRecognition(on: image)
        }.value
    }

    /// OCR with bounding boxes for Share Safe line redaction.
    nonisolated static func recognizeObservations(in image: CGImage) async throws -> [OCRTextObservation] {
        try await Task.detached(priority: .userInitiated) {
            try performObservationRecognition(on: image)
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
        request.recognitionLevel = VNRequestTextRecognitionLevel.accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        if let recognitionError {
            throw recognitionError
        }
        return recognizedLines.joined(separator: "\n")
    }

    private nonisolated static func performObservationRecognition(on image: CGImage) throws -> [OCRTextObservation] {
        var results: [OCRTextObservation] = []
        var recognitionError: Error?
        let width = image.width
        let height = image.height
        let imageSize = CGSize(width: width, height: height)

        let request = VNRecognizeTextRequest { request, error in
            if let error {
                recognitionError = error
                return
            }
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let text = candidate.string
                let fullBox = pixelRect(from: observation.boundingBox, imageWidth: width, imageHeight: height)
                    .intersection(CGRect(origin: .zero, size: imageSize))
                guard !fullBox.isEmpty else { continue }
                results.append(OCRTextObservation(text: text, boundingBox: fullBox))
            }
        }
        request.recognitionLevel = VNRequestTextRecognitionLevel.accurate
        // Keep tokens verbatim for emails, API keys, and code-like strings.
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        if let recognitionError {
            throw recognitionError
        }
        return results
    }

    /// Vision normalized box (bottom-left origin) → image pixels (top-left origin).
    private nonisolated static func pixelRect(from normalized: CGRect, imageWidth: Int, imageHeight: Int) -> CGRect {
        let w = CGFloat(imageWidth)
        let h = CGFloat(imageHeight)
        return CGRect(
            x: normalized.origin.x * w,
            y: (1 - normalized.origin.y - normalized.height) * h,
            width: normalized.width * w,
            height: normalized.height * h
        )
    }
}
