import AppKit
import SwiftUI

enum AnnotationInspectorNumericProperty: CaseIterable, Hashable {
    case strokeWidth, opacity, fillOpacity, dashLength, dashGap, dashPhase
    case arrowLength, arrowWidth, arrowInset, arrowCurve, cornerRadius
    case shadowOpacity, shadowRadius, shadowOffsetX, shadowOffsetY
    case fontSize, textBackgroundOpacity, textPadding, textLineHeight

    var label: String {
        switch self {
        case .strokeWidth: "Stroke width"
        case .opacity: "Stroke opacity"
        case .fillOpacity: "Fill opacity"
        case .dashLength: "Dash length"
        case .dashGap: "Dash gap"
        case .dashPhase: "Dash phase"
        case .arrowLength: "Arrowhead length"
        case .arrowWidth: "Arrowhead width"
        case .arrowInset: "Arrowhead inset"
        case .arrowCurve: "Arrow curve"
        case .cornerRadius: "Corner radius"
        case .shadowOpacity: "Shadow opacity"
        case .shadowRadius: "Shadow radius"
        case .shadowOffsetX: "Shadow horizontal offset"
        case .shadowOffsetY: "Shadow vertical offset"
        case .fontSize: "Font size"
        case .textBackgroundOpacity: "Text background opacity"
        case .textPadding: "Text padding"
        case .textLineHeight: "Line height"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .opacity, .fillOpacity, .shadowOpacity, .textBackgroundOpacity: 0...1
        case .strokeWidth: 0.5...64
        case .dashLength, .dashGap, .dashPhase: 0...100
        case .arrowLength, .arrowWidth: 1...200
        case .arrowInset, .cornerRadius, .shadowRadius, .textPadding: 0...200
        case .arrowCurve, .shadowOffsetX, .shadowOffsetY: -200...200
        case .fontSize: 6...288
        case .textLineHeight: 0.5...4
        }
    }

    var step: Double {
        switch self {
        case .opacity, .fillOpacity, .shadowOpacity, .textBackgroundOpacity, .textLineHeight: 0.05
        default: 0.5
        }
    }

    var unit: String {
        switch self {
        case .opacity, .fillOpacity, .shadowOpacity, .textBackgroundOpacity: "%"
        case .fontSize: "pt"
        case .textLineHeight: "×"
        default: "px"
        }
    }
}

/// Which inspector sections a selected annotation exposes. Pure so tests can
/// assert the matrix: a section may appear ONLY when the renderer honors it.
enum AnnotationInspectorSection: CaseIterable, Equatable {
    case color, stroke, strokeOpacity, fillAndShape, arrowheads, shadow, text, redaction

    static func sections(for kind: AnnotationKind) -> [AnnotationInspectorSection] {
        switch kind {
        // Redactions honor exactly one property (fill opacity); showing
        // color/stroke/shadow controls for them would be inert UI.
        case .redactBlur, .redactPixelate, .redactSolid:
            return [.redaction]
        // Text and step glyphs honor color, stroke *opacity*, and shadow, but
        // not stroke width/dash/cap — so no full stroke section.
        case .text, .step:
            return [.color, .strokeOpacity, .shadow, .text]
        case .arrow:
            return [.color, .stroke, .arrowheads, .shadow]
        case .rectangle, .ellipse:
            return [.color, .stroke, .fillAndShape, .shadow]
        case .line, .freehand, .highlighter:
            return [.color, .stroke, .shadow]
        }
    }
}

/// Testable command adapter used by every selected-object inspector control.
/// Tool-default bindings deliberately remain outside this type, so a no-selection
/// edit cannot silently mutate an annotation.
@MainActor
final class AnnotationInspectorController {
    private let document: EditorDocument

    init(document: EditorDocument) { self.document = document }

    var selectedAnnotation: Annotation? {
        guard let id = document.selectedAnnotationID else { return nil }
        return document.annotation(withID: id)
    }

    static func validated(
        _ value: Double,
        for property: AnnotationInspectorNumericProperty,
        step shouldStep: Bool = false
    ) -> Double? {
        guard value.isFinite else { return nil }
        let clamped = min(max(value, property.range.lowerBound), property.range.upperBound)
        guard shouldStep else { return clamped }
        return (clamped / property.step).rounded() * property.step
    }

    func value(for property: AnnotationInspectorNumericProperty) -> Double? {
        guard let annotation = selectedAnnotation else { return nil }
        return switch property {
        case .strokeWidth: Double(annotation.lineWidth)
        case .opacity: Double(annotation.appearance.stroke.opacity)
        case .fillOpacity: Double(annotation.appearance.fill.opacity)
        case .dashLength: Double(annotation.appearance.stroke.dash.first ?? 0)
        case .dashGap: Double(annotation.appearance.stroke.dash.dropFirst().first ?? 0)
        case .dashPhase: Double(annotation.appearance.stroke.dashPhase)
        case .arrowLength: Double(annotation.appearance.arrow.headLength ?? max(annotation.lineWidth * 4, 14))
        case .arrowWidth: Double(annotation.appearance.arrow.headWidth ?? max(annotation.lineWidth * 2, 7))
        case .arrowInset: Double(annotation.appearance.arrow.inset ?? max(annotation.lineWidth * 4, 14) * 0.6)
        case .arrowCurve: Double(annotation.appearance.arrow.curve)
        case .cornerRadius: Double(annotation.appearance.cornerRadius)
        case .shadowOpacity: Double(annotation.appearance.stroke.shadow.opacity)
        case .shadowRadius: Double(annotation.appearance.stroke.shadow.radius)
        case .shadowOffsetX: Double(annotation.appearance.stroke.shadow.offset.width)
        case .shadowOffsetY: Double(annotation.appearance.stroke.shadow.offset.height)
        case .fontSize: Double(annotation.fontSize)
        case .textBackgroundOpacity: Double(annotation.appearance.typography.backgroundOpacity)
        case .textPadding: Double(annotation.appearance.typography.padding.top)
        case .textLineHeight: Double(annotation.appearance.typography.lineHeight)
        }
    }

    @discardableResult
    func update(_ property: AnnotationInspectorNumericProperty, value: Double) -> Bool {
        guard let value = Self.validated(value, for: property), var annotation = selectedAnnotation else { return false }
        let number = CGFloat(value)
        switch property {
        case .strokeWidth: annotation.lineWidth = number
        case .opacity: annotation.appearance.stroke.opacity = number
        case .fillOpacity: annotation.appearance.fill.opacity = number
        case .dashLength:
            annotation.appearance.stroke.dash = dash(length: number, gap: annotation.appearance.stroke.dash.dropFirst().first ?? 0)
        case .dashGap:
            annotation.appearance.stroke.dash = dash(length: annotation.appearance.stroke.dash.first ?? 0, gap: number)
        case .dashPhase: annotation.appearance.stroke.dashPhase = number
        case .arrowLength: annotation.appearance.arrow.headLength = number
        case .arrowWidth: annotation.appearance.arrow.headWidth = number
        case .arrowInset: annotation.appearance.arrow.inset = number
        case .arrowCurve: annotation.appearance.arrow.curve = number
        case .cornerRadius: annotation.appearance.cornerRadius = number
        case .shadowOpacity: annotation.appearance.stroke.shadow.opacity = number
        case .shadowRadius: annotation.appearance.stroke.shadow.radius = number
        case .shadowOffsetX: annotation.appearance.stroke.shadow.offset.width = number
        case .shadowOffsetY: annotation.appearance.stroke.shadow.offset.height = number
        case .fontSize: annotation.fontSize = number
        case .textBackgroundOpacity: annotation.appearance.typography.backgroundOpacity = number
        case .textPadding:
            annotation.appearance.typography.padding = AnnotationInsets(top: number, leading: number, bottom: number, trailing: number)
        case .textLineHeight: annotation.appearance.typography.lineHeight = number
        }
        return document.transformAnnotation(id: annotation.id, to: annotation)
    }

    @discardableResult func updateColor(_ color: NSColor) -> Bool { mutate { $0.color = color } }
    @discardableResult func updateShadowColor(_ color: NSColor) -> Bool { mutate { $0.appearance.stroke.shadow.color = color } }
    @discardableResult func updateTextBackgroundColor(_ color: NSColor?) -> Bool { mutate { $0.appearance.typography.backgroundColor = color } }
    @discardableResult func updateFilled(_ filled: Bool) -> Bool { mutate { $0.filled = filled } }
    @discardableResult func updateText(_ text: String) -> Bool { mutate { $0.text = text } }
    @discardableResult func updateFontName(_ name: String) -> Bool { mutate { $0.appearance.typography.fontName = name.isEmpty ? nil : name } }
    @discardableResult func updateLineCap(_ cap: AnnotationLineCap) -> Bool { mutate { $0.appearance.stroke.lineCap = cap } }
    @discardableResult func updateTextAlignment(_ alignment: AnnotationTextAlignment) -> Bool { mutate { $0.appearance.typography.alignment = alignment } }
    @discardableResult func updateFontWeight(_ weight: NSFont.Weight) -> Bool { mutate { $0.appearance.typography.weight = weight } }
    @discardableResult func updateArrowheads(start: AnnotationArrowheadStyle, end: AnnotationArrowheadStyle) -> Bool {
        mutate { $0.appearance.arrow.startStyle = start; $0.appearance.arrow.endStyle = end }
    }

    @discardableResult
    private func mutate(_ body: (inout Annotation) -> Void) -> Bool {
        guard var annotation = selectedAnnotation else { return false }
        body(&annotation)
        return document.transformAnnotation(id: annotation.id, to: annotation)
    }

    private func dash(length: CGFloat, gap: CGFloat) -> [CGFloat] {
        length == 0 && gap == 0 ? [] : [length, gap]
    }
}

struct AnnotationInspector: View {
    @ObservedObject var document: EditorDocument
    let toolKind: ToolKind
    @Binding var defaultColor: Color
    @Binding var defaultLineWidth: CGFloat
    @Binding var defaultFontSize: CGFloat
    @Binding var defaultFilled: Bool

    private var controller: AnnotationInspectorController { AnnotationInspectorController(document: document) }
    private var selected: Annotation? { controller.selectedAnnotation }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AeroPanel(
            selected == nil ? "Tool Defaults" : "Selection",
            symbol: selected == nil ? "slider.horizontal.3" : "selection.pin.in.out",
            materialIntent: .floating
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: AeroTokens.Spacing.medium) {
                    if let selected { selectedControls(selected) } else { defaultControls }
                }
            }
            .frame(width: 300, height: panelHeight)
        }
        .animation(
            AeroTokens.Motion.resolved(AeroTokens.Motion.spring, reduceMotion: reduceMotion),
            value: selected == nil
        )
        .accessibilityLabel(selected == nil ? "No annotation selected. Tool defaults" : "Selected annotation inspector")
    }

    private var panelHeight: CGFloat {
        guard let selected else { return 210 }
        return selected.kind.isRedaction ? 220 : 540
    }

    private var defaultControls: some View {
        VStack(alignment: .leading, spacing: AeroTokens.Spacing.medium) {
            Text("No annotation selected")
                .font(AeroTokens.Typography.small(weight: .semibold))
                .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
            Text("Changes apply only to the next \(toolKind.displayName.lowercased()) annotation.")
                .font(AeroTokens.Typography.small())
                .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
            AeroInspectorRow("Color") { ColorPicker("Default color", selection: $defaultColor).labelsHidden() }
            if supportsStroke(toolKind) { defaultSlider("Stroke width", value: $defaultLineWidth, range: 0.5...64, unit: "px") }
            if toolKind == .text || toolKind == .step { defaultSlider("Font size", value: $defaultFontSize, range: 6...288, unit: "pt") }
            if toolKind == .rectangle || toolKind == .ellipse {
                AeroInspectorRow("Fill") { AeroCompactToggle(title: "", isOn: $defaultFilled) }
            }
        }
    }

    @ViewBuilder
    private func selectedControls(_ annotation: Annotation) -> some View {
        let sections = AnnotationInspectorSection.sections(for: annotation.kind)
        Text(annotation.kind.rawValue.capitalized)
            .font(AeroTokens.Typography.small(weight: .semibold))
            .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
        if sections.contains(.redaction) {
            section("Redaction")
            numeric(.fillOpacity)
            Text("Redactions cover with black, blur, or pixelation. Opacity is the only adjustable property and applies identically in preview and export.")
                .font(AeroTokens.Typography.small())
                .foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
        }
        if sections.contains(.color) {
            AeroInspectorRow("Color") {
                ColorPicker("Annotation color", selection: colorBinding).labelsHidden()
            }
        }
        if sections.contains(.strokeOpacity) {
            numeric(.opacity)
        }
        if sections.contains(.stroke) {
            section("Stroke")
            numeric(.strokeWidth)
            numeric(.opacity)
            HStack { numeric(.dashLength); numeric(.dashGap) }
            numeric(.dashPhase)
            AeroInspectorRow("Line cap") {
                AeroMenuPicker(
                    options: [AnnotationLineCap.butt, .round, .square],
                    selection: lineCapBinding,
                    label: lineCapLabel
                )
                .accessibilityLabel("Stroke line cap")
            }
        }

        if sections.contains(.fillAndShape) {
            section("Fill and shape")
            AeroInspectorRow("Fill") { AeroCompactToggle(title: "", isOn: filledBinding) }
            numeric(.fillOpacity)
            if annotation.kind == .rectangle { numeric(.cornerRadius) }
        }
        if sections.contains(.arrowheads) {
            section("Arrowheads")
            arrowheadPicker("Start", selection: arrowStartBinding)
            arrowheadPicker("End", selection: arrowEndBinding)
            numeric(.arrowLength); numeric(.arrowWidth); numeric(.arrowInset); numeric(.arrowCurve)
        }
        if sections.contains(.shadow) {
            section("Shadow")
            AeroInspectorRow("Shadow color") {
                ColorPicker("Shadow color", selection: shadowColorBinding).labelsHidden()
            }
            numeric(.shadowOpacity); numeric(.shadowRadius)
            HStack { numeric(.shadowOffsetX); numeric(.shadowOffsetY) }
        }

        if sections.contains(.text) {
            section("Text")
            if annotation.kind == .text {
                TextField("Text", text: textBinding)
                    .aeroFieldChrome()
                    .accessibilityLabel("Annotation text")
            }
            TextField("Font family", text: fontNameBinding)
                .aeroFieldChrome()
                .accessibilityLabel("Font family")
            numeric(.fontSize)
            AeroInspectorRow("Weight") {
                AeroMenuPicker(
                    options: [NSFont.Weight.regular, .medium, .semibold, .bold],
                    selection: fontWeightBinding,
                    label: fontWeightLabel
                )
                .accessibilityLabel("Font weight")
            }
            AeroInspectorRow("Alignment") {
                AeroMenuPicker(
                    options: [AnnotationTextAlignment.leading, .center, .trailing],
                    selection: textAlignmentBinding,
                    label: textAlignmentLabel
                )
                .accessibilityLabel("Text alignment")
            }
            AeroInspectorRow("Background color") {
                ColorPicker("Text background color", selection: textBackgroundColorBinding).labelsHidden()
            }
            numeric(.textBackgroundOpacity); numeric(.textPadding); numeric(.textLineHeight)
        }
    }

    private func section(_ title: String) -> some View {
        Text(title).font(AeroTokens.Typography.body(weight: .semibold)).padding(.top, AeroTokens.Spacing.xs)
    }

    private func numeric(_ property: AnnotationInspectorNumericProperty) -> some View {
        InspectorNumericControl(property: property, value: numericBinding(property))
    }

    private func numericBinding(_ property: AnnotationInspectorNumericProperty) -> Binding<Double> {
        Binding(get: { controller.value(for: property) ?? property.range.lowerBound }, set: { _ = controller.update(property, value: $0) })
    }

    private var colorBinding: Binding<Color> { Binding(get: { Color(nsColor: selected?.color ?? .systemRed) }, set: { _ = controller.updateColor(NSColor($0)) }) }
    private var shadowColorBinding: Binding<Color> { Binding(get: { Color(nsColor: selected?.appearance.stroke.shadow.color ?? .black) }, set: { _ = controller.updateShadowColor(NSColor($0)) }) }
    private var textBackgroundColorBinding: Binding<Color> { Binding(get: { Color(nsColor: selected?.appearance.typography.backgroundColor ?? .clear) }, set: { _ = controller.updateTextBackgroundColor(NSColor($0)) }) }
    private var filledBinding: Binding<Bool> { Binding(get: { selected?.filled ?? false }, set: { _ = controller.updateFilled($0) }) }
    private var textBinding: Binding<String> { Binding(get: { selected?.text ?? "" }, set: { _ = controller.updateText($0) }) }
    private var fontNameBinding: Binding<String> { Binding(get: { selected?.appearance.typography.fontName ?? "" }, set: { _ = controller.updateFontName($0) }) }
    private var lineCapBinding: Binding<AnnotationLineCap> { Binding(get: { selected?.appearance.stroke.lineCap ?? .round }, set: { _ = controller.updateLineCap($0) }) }
    private var textAlignmentBinding: Binding<AnnotationTextAlignment> { Binding(get: { selected?.appearance.typography.alignment ?? .leading }, set: { _ = controller.updateTextAlignment($0) }) }
    private var fontWeightBinding: Binding<NSFont.Weight> { Binding(get: { selected?.appearance.typography.weight ?? .semibold }, set: { _ = controller.updateFontWeight($0) }) }
    private var arrowStartBinding: Binding<AnnotationArrowheadStyle> { arrowBinding(start: true) }
    private var arrowEndBinding: Binding<AnnotationArrowheadStyle> { arrowBinding(start: false) }

    private func arrowBinding(start: Bool) -> Binding<AnnotationArrowheadStyle> {
        Binding(get: { start ? selected?.appearance.arrow.startStyle ?? .none : selected?.appearance.arrow.endStyle ?? .filled }, set: { value in
            let arrow = selected?.appearance.arrow ?? AnnotationArrowAppearance()
            _ = controller.updateArrowheads(start: start ? value : arrow.startStyle, end: start ? arrow.endStyle : value)
        })
    }

    private func arrowheadPicker(_ label: String, selection: Binding<AnnotationArrowheadStyle>) -> some View {
        AeroInspectorRow(label) {
            AeroMenuPicker(
                options: [AnnotationArrowheadStyle.none, .open, .filled],
                selection: selection,
                label: arrowheadLabel
            )
            .accessibilityLabel("\(label) arrowhead style")
        }
    }

    private func lineCapLabel(_ cap: AnnotationLineCap) -> String {
        switch cap {
        case .butt: "Butt"
        case .round: "Round"
        case .square: "Square"
        }
    }

    private func fontWeightLabel(_ weight: NSFont.Weight) -> String {
        switch weight {
        case .regular: "Regular"
        case .medium: "Medium"
        case .semibold: "Semibold"
        case .bold: "Bold"
        default: "Custom"
        }
    }

    private func textAlignmentLabel(_ alignment: AnnotationTextAlignment) -> String {
        switch alignment {
        case .leading: "Leading"
        case .center: "Center"
        case .trailing: "Trailing"
        }
    }

    private func arrowheadLabel(_ style: AnnotationArrowheadStyle) -> String {
        switch style {
        case .none: "None"
        case .open: "Open"
        case .filled: "Filled"
        }
    }

    private func defaultSlider(_ label: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>, unit: String) -> some View {
        AeroInspectorRow(label, detail: unit) { Slider(value: value, in: range).frame(width: 130).accessibilityLabel(label) }
    }

    private func supportsStroke(_ kind: ToolKind) -> Bool {
        [.arrow, .line, .rectangle, .ellipse, .freehand, .highlighter].contains(kind)
    }
}

private struct InspectorNumericControl: View {
    let property: AnnotationInspectorNumericProperty
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: AeroTokens.Spacing.xs) {
            HStack {
                Text(property.label).font(AeroTokens.Typography.small())
                Spacer()
                TextField(property.unit, value: $value, format: .number.precision(.fractionLength(0...2)))
                    .aeroFieldChrome()
                    .frame(width: 72)
                    .multilineTextAlignment(.trailing)
                Text(property.unit).font(AeroTokens.Typography.micro()).foregroundStyle(AeroTokens.ColorRole.foregroundSecondary)
            }
            Slider(value: $value, in: property.range, step: property.step)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(property.label)
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + property.step, property.range.upperBound)
            case .decrement: value = max(value - property.step, property.range.lowerBound)
            @unknown default: break
            }
        }
    }

    private var accessibilityValue: String {
        let displayed = property.unit == "%" ? value * 100 : value
        return "\(displayed.formatted(.number.precision(.fractionLength(0...2)))) \(property.unit)"
    }
}
