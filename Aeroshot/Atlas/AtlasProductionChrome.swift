import AppKit
import SwiftUI

/// Shared window chrome for the production editors. The content below it stays
/// the real editor/model view, so the Atlas presentation does not fork behavior.
struct AtlasProductionWindow<Content: View>: View {
    let title: String
    let detail: String
    let status: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            AtlasProductionTitleBar(title: title, detail: detail, status: status)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(red: 0.043, green: 0.047, blue: 0.059))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("atlas.production.window")
    }
}

private struct AtlasProductionTitleBar: View {
    let title: String
    let detail: String
    let status: String

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 11, height: 11)
                Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 11, height: 11)
                Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 11, height: 11)
            }

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(SettingsTheme.accent)
                .frame(width: 17, height: 17)
                .overlay {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AeroTokens.ColorRole.onAccent)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(SettingsTheme.typeMicro(design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(status)
                .font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced))
                .tracking(0.45)
                .foregroundStyle(SettingsTheme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(SettingsTheme.accent.opacity(0.11), in: Capsule())
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(Color(red: 0.055, green: 0.063, blue: 0.078))
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
    }
}

struct AtlasEditorProductionView: View {
    @ObservedObject var document: EditorDocument
    let appState: AppState
    let projectTitle: String

    var body: some View {
        AtlasProductionWindow(
            title: projectTitle,
            detail: "MOVE STACK · NON-DESTRUCTIVE",
            status: document.isPrivacyScanPending ? "SHARESAFE REVIEW" : "AUTOSAVED"
        ) {
            HStack(spacing: 0) {
                AtlasEditorStackPanel(document: document)
                    .frame(width: 250)
                EditorView(document: document, appState: appState)
                    .frame(minWidth: 960, minHeight: 520)
                    .background(Color(red: 0.055, green: 0.063, blue: 0.078))
            }
        }
    }
}

private struct AtlasEditorStackPanel: View {
    @ObservedObject var document: EditorDocument

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Move stack")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Text("\(document.annotations.count)")
                    .font(SettingsTheme.typeMicro(design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 13)
            .padding(.top, 13)
            .padding(.bottom, 9)

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(Array(document.annotations.enumerated()), id: \.element.id) { index, annotation in
                        Button {
                            document.selectOnly(annotation.id)
                        } label: {
                            HStack(spacing: 8) {
                                Text(annotationGlyph(annotation.kind))
                                    .font(SettingsTheme.typeMicro(weight: .bold, design: .monospaced))
                                    .foregroundStyle(annotation.kind.isRedaction ? AeroTokens.ColorRole.warning : SettingsTheme.accent)
                                    .frame(width: 20, height: 20)
                                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(annotationLabel(annotation, index: index))
                                        .font(.system(size: 11, weight: .semibold))
                                        .lineLimit(1)
                                    Text(annotationMeta(annotation))
                                        .font(SettingsTheme.typeMicro(design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .background(
                                document.selection.contains(annotation.id)
                                    ? SettingsTheme.fillSelected
                                    : .clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if document.annotations.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            Image(systemName: "square.stack.3d.up")
                                .foregroundStyle(SettingsTheme.accent)
                            Text("Your base capture is untouched.")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Choose a tool above to add the first reversible mark.")
                                .font(SettingsTheme.typeMicro())
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }

            VStack(alignment: .leading, spacing: 8) {
                Divider()
                HStack(spacing: 7) {
                    Circle()
                        .fill(SettingsTheme.success)
                        .frame(width: 7, height: 7)
                    Text("Base capture · \(Int(document.pixelSize.width)) × \(Int(document.pixelSize.height))")
                        .font(SettingsTheme.typeMicro())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 7) {
                    Circle()
                        .fill(document.isPrivacyScanPending ? SettingsTheme.warning : SettingsTheme.success)
                        .frame(width: 7, height: 7)
                    Text(document.isPrivacyScanPending ? "ShareSafe review pending" : "Autosaved to project package")
                        .font(SettingsTheme.typeMicro())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Button("Select all") { document.selectAll() }
                    Button("Delete selected", role: .destructive) { _ = document.deleteSelected() }
                        .disabled(document.selection.isEmpty)
                }
                .buttonStyle(.borderless)
                .font(SettingsTheme.typeMicro(weight: .semibold))
            }
            .padding(12)
        }
        .background(Color(red: 0.055, green: 0.063, blue: 0.078))
        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.08)).frame(width: 1) }
        .accessibilityIdentifier("atlas.editor.stack")
    }

    private func annotationLabel(_ annotation: Annotation, index: Int) -> String {
        let text = annotation.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return text
        }
        return "\(annotation.kind.rawValue.capitalized) \(index + 1)"
    }

    private func annotationMeta(_ annotation: Annotation) -> String {
        let bounds = annotation.boundingRect
        return "\(Int(bounds.width)) × \(Int(bounds.height)) · \(annotation.kind.rawValue.uppercased())"
    }

    private func annotationGlyph(_ kind: AnnotationKind) -> String {
        switch kind {
        case .arrow: "↗"
        case .rectangle: "□"
        case .ellipse: "○"
        case .line: "╱"
        case .freehand: "⌁"
        case .highlighter: "▰"
        case .text: "T"
        case .redactBlur, .redactPixelate, .redactSolid: "◍"
        case .step: "#"
        }
    }
}

struct AtlasGIFStudioProductionView: View {
    @ObservedObject var model: GIFStudioDocument

    var body: some View {
        AtlasProductionWindow(
            title: model.packageURL?.deletingPathExtension().lastPathComponent ?? "GIF Studio",
            detail: "DURATION IS WIDTH · \(model.document.frames.count) FRAMES",
            status: model.exportProgress == nil ? "READY TO EXPORT" : "EXPORTING"
        ) {
            GIFStudioView(model: model)
        }
    }
}

struct AtlasMediaStudioProductionView: View {
    @ObservedObject var document: VideoStudioDocument

    var body: some View {
        AtlasProductionWindow(
            title: document.packageURL.deletingPathExtension().lastPathComponent,
            detail: "THE RECORDING KNOWS WHAT HAPPENED",
            status: document.exportProgress == nil ? "EVENT TRACKS LIVE" : "EXPORTING"
        ) {
            VideoStudioView(document: document)
        }
    }
}

struct AtlasOnboardingProductionView: View {
    @EnvironmentObject private var settings: SettingsStore
    let startStep: OnboardingStep
    let onComplete: () -> Void

    var body: some View {
        AtlasProductionWindow(
            title: "Aeroshot setup",
            detail: "PROVE IT · DO NOT PROMISE IT",
            status: "SETUP · STEP \(startStep.rawValue + 1) OF \(OnboardingStep.allCases.count)"
        ) {
            OnboardingView(startStep: startStep, onComplete: onComplete)
                .environmentObject(settings)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
