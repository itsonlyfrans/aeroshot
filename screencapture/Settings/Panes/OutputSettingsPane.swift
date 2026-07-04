import AppKit
import SwiftUI

struct OutputSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsPaneLayout {
            VStack(alignment: .leading, spacing: SettingsTheme.spacingL) {
                SettingsHeroHeader(
                    "Output",
                    subtitle: truncatedPath,
                    chips: [settings.imageFormat.displayName, settings.downscaleRetina ? "1× export" : "Native resolution"]
                )

                SettingsPanel("Save location") {
                    SettingsPathField(
                        path: settings.saveDirectoryPath,
                        chooseAction: chooseFolder,
                        openAction: openInFinder
                    )
                }

                SettingsPanel("Image format") {
                    SettingsSegmentedControl(
                        options: ImageFormat.allCases,
                        selection: Binding(
                            get: { settings.imageFormat },
                            set: { settings.imageFormat = $0 }
                        ),
                        label: { $0.displayName }
                    )

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

                SettingsPanel("Filename templates") {
                    VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
                        Text("Screenshots")
                            .font(.subheadline.weight(.medium))
                        TextField("Screenshot {date} at {time}", text: $settings.filenameTemplate)
                            .textFieldStyle(.roundedBorder)

                        Text("Recordings")
                            .font(.subheadline.weight(.medium))
                            .padding(.top, SettingsTheme.spacingXS)
                        TextField("Screen Recording {date} at {time}", text: $settings.recordingFilenameTemplate)
                            .textFieldStyle(.roundedBorder)

                        Text("Tokens: {date} · {time} · {type} · {app}")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsPanel("Related") {
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
