import AppKit
import SwiftUI

struct OutputSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsPaneLayout(pane: .output) {
            VStack(alignment: .leading, spacing: SettingsTheme.spacingL) {
                SettingsHeroHeader(
                    "Output",
                    symbol: "folder",
                    subtitle: truncatedPath,
                    chips: [settings.imageFormat.displayName, settings.downscaleRetina ? "1× export" : "Native resolution"]
                )

                SettingsPanel("Save location", symbol: "folder") {
                    SettingsPathField(
                        path: settings.saveDirectoryPath,
                        chooseAction: chooseFolder,
                        openAction: openInFinder
                    )
                }

                SettingsPanel("Image format", symbol: "photo") {
                    SettingsSegmentedControl(
                        options: ImageFormat.allCases,
                        selection: Binding(
                            get: { settings.imageFormat },
                            set: { settings.imageFormat = $0 }
                        ),
                        label: { $0.displayName }
                    )

                    Text(formatHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if settings.imageFormat == .jpeg {
                        SettingsValueSlider(
                            title: "JPEG compression quality",
                            subtitle: "Higher quality means larger files",
                            value: $settings.jpegQuality,
                            in: 0.3...1.0,
                            step: 0.05,
                            valueLabel: { String(format: "%.0f%%", $0 * 100) }
                        )
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    }

                    SettingsToggle(
                        title: "Downscale Retina captures",
                        subtitle: "Export at 1× resolution instead of 2×",
                        isOn: $settings.downscaleRetina,
                        symbol: "arrow.down.right.and.arrow.up.left"
                    )
                }

                SettingsPanel("Filename templates", symbol: "textformat") {
                    VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
                        SettingsSubsectionHeader(title: "Screenshots", compact: true)
                        TextField("Screenshot {date} at {time}", text: $settings.filenameTemplate)
                            .textFieldStyle(.roundedBorder)
                        filenamePreview(
                            settings.formattedFilename(
                                template: settings.filenameTemplate,
                                typeLabel: "Screenshot",
                                fileExtension: settings.imageFormat.fileExtension
                            )
                        )

                        SettingsSubsectionHeader(title: "Recordings", compact: true)
                            .padding(.top, SettingsTheme.spacingS)
                        TextField("Screen Recording {date} at {time}", text: $settings.recordingFilenameTemplate)
                            .textFieldStyle(.roundedBorder)
                        filenamePreview(
                            settings.formattedFilename(
                                template: settings.recordingFilenameTemplate,
                                typeLabel: "Screen Recording",
                                fileExtension: settings.recordingFormat.fileExtension
                            )
                        )

                        Text("Tokens: {date} · {time} · {type} · {app}")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, SettingsTheme.spacingXS)
                    }
                }

                SettingsPanel("Cloud upload", symbol: "icloud.and.arrow.up") {
                    SettingsToggle(
                        title: "Upload after capture",
                        subtitle: "POST saved files to your webhook when a capture completes",
                        isOn: $settings.uploadAfterCapture,
                        symbol: "icloud.and.arrow.up"
                    )

                    Group {
                        VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
                            SettingsSubsectionHeader(title: "Webhook URL", compact: true)
                            TextField("https://your-server.com/upload", text: $settings.uploadWebhookURL)
                                .textFieldStyle(.roundedBorder)
                            Text("Expects multipart file upload; responds with JSON {\"url\"} or plain link text.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        SettingsToggle(
                            title: "Copy link after upload",
                            subtitle: "Put the returned URL on the clipboard",
                            isOn: $settings.copyLinkAfterUpload,
                            symbol: "link"
                        )
                    }
                    .disabled(!settings.uploadAfterCapture)
                    .opacity(settings.uploadAfterCapture ? 1 : 0.45)
                }

                SettingsFootnoteSection("Related") {
                    SettingsQuickLink(
                        title: "Capture workflow",
                        subtitle: "Clipboard, thumbnail, and sound options",
                        pane: .capture
                    )
                }
            }
            .animation(SettingsTheme.spring(reducedMotion: reduceMotion), value: settings.imageFormat)
        }
    }

    private var formatHint: String {
        switch settings.imageFormat {
        case .png: return "Lossless with transparency — best for UI screenshots and crisp text."
        case .jpeg: return "Small files with adjustable quality — good for photos and sharing."
        case .heic: return "Half the size of JPEG at the same quality — Apple platforms only."
        }
    }

    private func filenamePreview(_ name: String) -> some View {
        HStack(spacing: SettingsTheme.spacingXS + 2) {
            Image(systemName: "doc")
                .font(SettingsTheme.typeMicro(weight: .medium))
            Text(name)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, SettingsTheme.spacingS)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var truncatedPath: String {
        let path = settings.saveDirectoryPath
        if path.count <= 48 { return path }
        return "…" + path.suffix(45)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = settings.saveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectoryPath = url.path
        }
    }

    private func openInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: settings.saveDirectoryPath)
    }
}
