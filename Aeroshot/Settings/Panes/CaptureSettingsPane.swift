import SwiftUI

struct CaptureSettingsPane: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var summaryChips: [String] {
        var chips: [String] = []
        if settings.copyToClipboardAfterCapture { chips.append("Clipboard") }
        if settings.saveToDiskAfterCapture { chips.append("Save to disk") }
        if settings.showThumbnailAfterCapture { chips.append("Thumbnail") }
        if settings.playCaptureSound { chips.append("Sound") }
        return chips.isEmpty ? ["No actions enabled"] : chips
    }

    var body: some View {
        SettingsPaneLayout {
            VStack(alignment: .leading, spacing: SettingsTheme.spacingL) {
                SettingsHeroHeader(
                    "Capture workflow",
                    subtitle: "Choose what happens immediately after you take a screenshot.",
                    chips: summaryChips + [settings.activeCaptureProfile.name]
                )

                SettingsPanel("Capture profile") {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: SettingsTheme.spacingM
                    ) {
                        ForEach(CaptureProfile.builtIn) { profile in
                            CaptureProfileCard(
                                profile: profile,
                                isSelected: settings.activeCaptureProfileID == profile.id
                            ) {
                                settings.applyCaptureProfile(profile)
                                SettingsTheme.performHaptic()
                            }
                        }
                    }
                }

                SettingsPanel("After capture") {
                    SettingsToggle(
                        title: "Copy to clipboard",
                        subtitle: "Paste captured images right away",
                        isOn: $settings.copyToClipboardAfterCapture,
                        symbol: "doc.on.clipboard"
                    )

                    SettingsToggle(
                        title: "Save to disk",
                        subtitle: "Write files to your output folder automatically",
                        isOn: $settings.saveToDiskAfterCapture,
                        symbol: "externaldrive"
                    )

                    SettingsToggle(
                        title: "Quick-access thumbnail",
                        subtitle: "Show a floating preview in the corner",
                        isOn: $settings.showThumbnailAfterCapture,
                        symbol: "photo.on.rectangle.angled"
                    )

                    SettingsToggle(
                        title: "Play capture sound",
                        subtitle: "Audible feedback when a capture completes",
                        isOn: $settings.playCaptureSound,
                        symbol: "speaker.wave.2"
                    )

                    if settings.playCaptureSound {
                        HStack {
                            HStack(spacing: 8) {
                                Image(systemName: "music.note")
                                    .foregroundStyle(.secondary)
                                Text("Sound effect")
                                    .font(.body)
                            }
                            Spacer()
                            Picker("", selection: $settings.selectedCaptureSound) {
                                ForEach(settings.availableSounds) { sound in
                                    Text(sound.displayName).tag(sound.filename)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 220)
                            .labelsHidden()
                            .onChange(of: settings.selectedCaptureSound) {
                                settings.playSelectedSound()
                            }
                        }
                        .padding(.leading, 38)
                        .transition(.opacity)
                    }

                }

                SettingsPanel("Timing & recall") {
                    VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Capture delay")
                                .font(.headline)
                            Text("Countdown before the selection overlay or instant capture starts")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        SettingsSegmentedControl(
                            options: [0, 3, 5, 10],
                            selection: Binding(
                                get: { settings.captureDelaySeconds },
                                set: { settings.captureDelaySeconds = $0 }
                            ),
                            label: { value in
                                value == 0 ? "Off" : "\(value)s"
                            }
                        )
                    }

                    SettingsToggle(
                        title: "Recall last region",
                        subtitle: "Enable Capture Last Region to repeat your previous area crop",
                        isOn: $settings.recallLastRegionEnabled,
                        symbol: "arrow.counterclockwise"
                    )

                    VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Selection aspect lock")
                                .font(.headline)
                            Text("Constrain area selection to a fixed ratio")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        SettingsSegmentedControl(
                            options: SelectionAspectLock.allCases,
                            selection: Binding(
                                get: { settings.selectionAspectLock },
                                set: { settings.selectionAspectLock = $0 }
                            ),
                            label: { $0.displayName }
                        )
                    }
                }

                if settings.showThumbnailAfterCapture {
                    SettingsPanel("Quick preview") {
                        SettingsToggle(
                            title: "Always show thumbnail actions",
                            subtitle: "Keep Copy, Edit, and Pin visible without hovering",
                            isOn: $settings.showThumbnailActionsAlways,
                            symbol: "hand.tap"
                        )

                        SettingsValueSlider(
                            title: "Thumbnail duration",
                            subtitle: "How long the preview stays visible",
                            value: $settings.thumbnailDuration,
                            in: 2...15,
                            step: 1,
                            valueLabel: { "\(Int($0))s" }
                        )

                        ThumbnailPreviewMock(duration: settings.thumbnailDuration)
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }

                SettingsPanel("Share Safe") {
                    HStack(alignment: .top, spacing: SettingsTheme.spacingS) {
                        Image(systemName: "shield.checkered")
                            .foregroundStyle(.green)
                        Text("Share Safe scans captures for emails, phone numbers, API keys, and similar data. With redaction enabled, every capture is processed automatically — not only when you tap the green shield.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    SettingsToggle(
                        title: "Redact sensitive data",
                        subtitle: "Automatically redact after every capture and when using the Share Safe button. Turn off to scan only when sharing.",
                        isOn: $settings.shareSafeRedactBeforeSharing,
                        symbol: "shield.checkered"
                    )

                    SettingsToggle(
                        title: "Smart scan (Apple Intelligence)",
                        subtitle: ShareSafeSmartScanSupport.settingsSubtitle,
                        isOn: $settings.shareSafeSmartScan,
                        symbol: "sparkles"
                    )
                    .disabled(!settings.shareSafeRedactBeforeSharing)

                    PrivacyFilterSettingsRow(isOn: $settings.shareSafePrivacyFilter)
                        .disabled(!settings.shareSafeRedactBeforeSharing)

                    VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Redaction style")
                                .font(.headline)
                            Text("How sensitive regions are hidden in Share Safe exports. Redact replaces pixels with solid black and cannot be reversed.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        SettingsSegmentedControl(
                            options: ShareSafeRedactionStyle.allCases,
                            selection: Binding(
                                get: { settings.shareSafeRedactionStyle },
                                set: { settings.shareSafeRedactionStyle = $0 }
                            ),
                            label: { $0.displayName }
                        )
                    }
                }

                SettingsPanel("Power tips") {
                    HStack(alignment: .top, spacing: SettingsTheme.spacingS) {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(.secondary)
                        Text("Pinned screenshots: scroll to resize, Option+scroll for opacity, double-click or Esc to close.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SettingsPanel("Related") {
                    SettingsQuickLink(
                        title: "Output folder & format",
                        subtitle: "Change where screenshots are saved",
                        pane: .output
                    )
                    Divider().opacity(0.5)
                    SettingsQuickLink(
                        title: "Keyboard shortcuts",
                        subtitle: "Launch captures from anywhere",
                        pane: .shortcuts
                    )
                }
            }
            .animation(SettingsTheme.spring(reducedMotion: reduceMotion), value: settings.showThumbnailAfterCapture)
        }
    }
}

private struct CaptureProfileCard: View {
    let profile: CaptureProfile
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
                HStack {
                    Image(systemName: profile.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                Text(profile.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(profile.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(SettingsTheme.spacingM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
            )
            .overlay {
                RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1 : 0.5
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct ThumbnailPreviewMock: View {
    let duration: Double
    @State private var visible = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: SettingsTheme.spacingM) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.3), Color.blue.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 72, height: 48)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.white.opacity(0.8))
                }
                .opacity(visible ? 1 : 0.35)
                .scaleEffect(visible ? 1 : 0.95)

            VStack(alignment: .leading, spacing: 2) {
                Text("Preview mockup")
                    .font(.subheadline.weight(.medium))
                Text("Fades after \(Int(duration)) seconds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.top, SettingsTheme.spacingXS)
        .onAppear { schedulePulse() }
        .onChange(of: duration) { _, _ in schedulePulse() }
        .accessibilityHidden(true)
    }

    private func schedulePulse() {
        visible = true
        guard !reduceMotion else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.15) {
            withAnimation(.easeInOut(duration: 0.4)) {
                visible = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    visible = true
                }
            }
        }
    }
}
