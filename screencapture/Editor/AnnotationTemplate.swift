import AppKit
import Foundation

struct AnnotationTemplateSnapshot: Codable {
    var kind: AnnotationKind
    var normalizedPoints: [CGPoint]
    var colorHex: String
    var lineWidth: CGFloat
    var text: String
    var fontSize: CGFloat
    var stepNumber: Int
    var filled: Bool
}

struct AnnotationTemplate: Identifiable, Codable {
    let id: String
    let name: String
    let symbol: String
    let snapshots: [AnnotationTemplateSnapshot]

    func makeAnnotations(for imageSize: CGSize) -> [Annotation] {
        snapshots.map { snapshot in
            let points = snapshot.normalizedPoints.map {
                CGPoint(x: $0.x * imageSize.width, y: $0.y * imageSize.height)
            }
            return Annotation(
                kind: snapshot.kind,
                points: points,
                color: NSColor(hex: snapshot.colorHex) ?? .systemRed,
                lineWidth: snapshot.lineWidth,
                text: snapshot.text,
                fontSize: snapshot.fontSize,
                stepNumber: snapshot.stepNumber,
                filled: snapshot.filled
            )
        }
    }

    static let bugReport = AnnotationTemplate(
        id: "bug-report",
        name: "Bug report",
        symbol: "ladybug.fill",
        snapshots: [
            AnnotationTemplateSnapshot(
                kind: .rectangle,
                normalizedPoints: [CGPoint(x: 0.08, y: 0.12), CGPoint(x: 0.62, y: 0.58)],
                colorHex: "#FF3B30",
                lineWidth: 4,
                text: "",
                fontSize: 24,
                stepNumber: 1,
                filled: false
            ),
            AnnotationTemplateSnapshot(
                kind: .arrow,
                normalizedPoints: [CGPoint(x: 0.64, y: 0.18), CGPoint(x: 0.48, y: 0.28)],
                colorHex: "#FF3B30",
                lineWidth: 4,
                text: "",
                fontSize: 24,
                stepNumber: 1,
                filled: false
            ),
            AnnotationTemplateSnapshot(
                kind: .step,
                normalizedPoints: [CGPoint(x: 0.5, y: 0.34)],
                colorHex: "#FF3B30",
                lineWidth: 4,
                text: "",
                fontSize: 28,
                stepNumber: 1,
                filled: true
            )
        ]
    )

    static let callout = AnnotationTemplate(
        id: "callout",
        name: "Callout",
        symbol: "text.bubble",
        snapshots: [
            AnnotationTemplateSnapshot(
                kind: .rectangle,
                normalizedPoints: [CGPoint(x: 0.55, y: 0.15), CGPoint(x: 0.92, y: 0.32)],
                colorHex: "#007AFF",
                lineWidth: 3,
                text: "",
                fontSize: 24,
                stepNumber: 1,
                filled: true
            ),
            AnnotationTemplateSnapshot(
                kind: .text,
                normalizedPoints: [CGPoint(x: 0.57, y: 0.18)],
                colorHex: "#FFFFFF",
                lineWidth: 3,
                text: "Note this",
                fontSize: 20,
                stepNumber: 1,
                filled: false
            )
        ]
    )

    static let steps = AnnotationTemplate(
        id: "steps",
        name: "Step markers",
        symbol: "list.number",
        snapshots: [
            AnnotationTemplateSnapshot(
                kind: .step,
                normalizedPoints: [CGPoint(x: 0.2, y: 0.25)],
                colorHex: "#5856D6",
                lineWidth: 4,
                text: "",
                fontSize: 26,
                stepNumber: 1,
                filled: true
            ),
            AnnotationTemplateSnapshot(
                kind: .step,
                normalizedPoints: [CGPoint(x: 0.2, y: 0.55)],
                colorHex: "#5856D6",
                lineWidth: 4,
                text: "",
                fontSize: 26,
                stepNumber: 2,
                filled: true
            )
        ]
    )

    static let builtIn: [AnnotationTemplate] = [.bugReport, .callout, .steps]
}

private extension NSColor {
    convenience init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt64(string, radix: 16) else { return nil }
        let r = CGFloat((value & 0xFF0000) >> 16) / 255
        let g = CGFloat((value & 0x00FF00) >> 8) / 255
        let b = CGFloat(value & 0x0000FF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#FF3B30" }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
