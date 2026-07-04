import SwiftUI

struct RecordingSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var gifAdvancedExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SettingsPaneLayout {
            VStack(alignment: .leading, spacing: SettingsTheme.spacingL) {
                SettingsHeroHeader(
                    "Recording",
                    subtitle: "Configure screen recordings and animated GIF exports.",
                    chips: [
                        settings.recordingFormat.displayName,
                        settings.recordSystemAudio ? "System audio" : "Video only"
                    ]
                )

                SettingsPanel("Format") {
                    HStack(spacing: SettingsTheme.spacingM) {
                        ForEach(RecordingFormat.allCases) { format in
                            RecordingFormatCard(
                                format: format,
                                isSelected: settings.recordingFormat == format
                            ) {
                                withAnimation(SettingsTheme.spring(reducedMotion: reduceMotion)) {
                                    settings.recordingFormat = format
                                }
                                SettingsTheme.performHaptic()
                            }
                        }
                    }
                }

                SettingsPanel("Options") {
                    SettingsToggle(
                        title: "Record system audio",
                        subtitle: "Capture audio playback (MP4 only)",
                        isOn: $settings.recordSystemAudio,
                        symbol: "speaker.wave.3"
                    )

                    SettingsToggle(
                        title: "Highlight clicks",
                        subtitle: "Show a visual ripple on mouse clicks",
                        isOn: $settings.highlightClicksDuringRecording,
                        symbol: "cursorarrow.rays"
                    )

                    SettingsToggle(
                        title: "Add recordings to history",
                        subtitle: "Keep MP4 and GIF files in the history browser",
                        isOn: $settings.addRecordingsToHistory,
                        symbol: "clock.arrow.circlepath"
                    )
                }

                if settings.recordingFormat == .gif {
                    SettingsExpandablePanel(
                        "Advanced GIF options",
                        subtitle: "Frame rate and length limits",
                        isExpanded: $gifAdvancedExpanded
                    ) {
                        SettingsValueSlider(
                            title: "Frame rate",
                            value: Binding(
                                get: { Double(settings.gifFPS) },
                                set: { settings.gifFPS = Int($0) }
                            ),
                            in: 5...20,
                            step: 1,
                            valueLabel: { "\(Int($0)) fps" }
                        )

                        SettingsValueSlider(
                            title: "Maximum frames",
                            value: Binding(
                                get: { Double(settings.gifMaxFrames) },
                                set: { settings.gifMaxFrames = Int($0) }
                            ),
                            in: 60...600,
                            step: 30,
                            valueLabel: { "\(Int($0))" }
                        )
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }

                SettingsPanel("Related") {
                    SettingsQuickLink(
                        title: "Scrolling capture",
                        subtitle: "Long-page stitch settings",
                        pane: .scrolling
                    )
                }
            }
            .animation(SettingsTheme.spring(reducedMotion: reduceMotion), value: settings.recordingFormat)
        }
    }
}

private struct RecordingFormatCard: View {
    let format: RecordingFormat
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
                Image(systemName: format == .mp4 ? "film" : "photo.stack")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)

                Text(format.displayName)
                    .font(.headline)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)

                Text(format == .mp4 ? "High quality video with optional audio" : "Lightweight animated image")
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(SettingsTheme.spacingL)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.primary.opacity(isHovered ? 0.06 : 0.04)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .scaleEffect(isHovered && !isSelected && !reduceMotion ? 1.01 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovered = $0 }
    }
}
