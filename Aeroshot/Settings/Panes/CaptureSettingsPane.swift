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
        SettingsPaneLayout(pane: .capture) {
            VStack(alignment: .leading, spacing: SettingsTheme.spacingL) {
                SettingsHeroHeader(
                    "Capture workflow",
                    symbol: "camera.viewfinder",
                    subtitle: "Choose what happens immediately after you take a screenshot.",
                    chips: summaryChips + [settings.activeCaptureProfile.name]
                )

                SettingsPanel("Capture profile", symbol: "rectangle.stack") {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: SettingsTheme.spacingM), GridItem(.flexible(), spacing: SettingsTheme.spacingM)],
                        spacing: SettingsTheme.spacingM
                    ) {
                        ForEach(CaptureProfile.builtIn) { profile in
                            SettingsSelectionCard(
                                title: profile.name,
                                subtitle: profile.summary,
                                symbol: profile.symbol,
                                isSelected: settings.activeCaptureProfileID == profile.id
                            ) {
                                settings.applyCaptureProfile(profile)
                                SettingsTheme.performHaptic()
                            }
                        }
                    }
                }

                SettingsPanel("After capture", symbol: "bolt") {
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
                        HStack(spacing: SettingsTheme.spacingM) {
                            Image(systemName: "music.note")
                                .font(.system(size: SettingsTheme.iconSizeMedium, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: SettingsTheme.iconColumnWidth)

                            Text("Sound effect")
                                .font(.body.weight(.medium))

                            Spacer()

                            SettingsMenuPicker(
                                options: settings.availableSounds.map(\.filename),
                                selection: $settings.selectedCaptureSound,
                                label: { filename in
                                    settings.availableSounds.first { $0.filename == filename }?.displayName ?? filename
                                }
                            )
                            .onChange(of: settings.selectedCaptureSound) {
                                settings.playSelectedSound()
                            }
                            .accessibilityLabel("Sound effect")
                        }
                        .padding(.leading, SettingsTheme.spacingXS)
                        .transition(.opacity)
                    }
                }

                SettingsPanel("Timing & recall", symbol: "timer") {
                    VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
                        SettingsSubsectionHeader(
                            title: "Capture delay",
                            subtitle: "Countdown before the selection overlay or instant capture starts"
                        )

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
                        SettingsSubsectionHeader(
                            title: "Selection aspect lock",
                            subtitle: "Constrain area selection to a fixed ratio"
                        )

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
                    SettingsPanel("Quick preview", symbol: "eye") {
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

                        VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
                            SettingsSubsectionHeader(
                                title: "Visible actions",
                                subtitle: "Choose up to three actions; the rest stay in More."
                            )

                            ForEach(ThumbnailAction.allCases) { action in
                                SettingsToggle(
                                    title: action.title,
                                    subtitle: nil,
                                    isOn: Binding(
                                        get: { settings.thumbnailVisibleActions.contains(action) },
                                        set: { settings.setThumbnailAction(action, visible: $0) }
                                    ),
                                    symbol: action.symbol
                                )
                                .disabled(!settings.thumbnailVisibleActions.contains(action) && settings.thumbnailVisibleActions.count >= 3)
                            }
                        }

                        ThumbnailPreviewMock(duration: settings.thumbnailDuration)
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }

                SettingsPanel("Share Safe", symbol: "shield.lefthalf.filled") {
                    HStack(alignment: .top, spacing: SettingsTheme.spacingS) {
                        Image(systemName: "shield.checkered")
                            .foregroundStyle(SettingsTheme.success)
                            .frame(width: SettingsTheme.iconColumnWidth)
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
                        symbol: "text.magnifyingglass"
                    )
                    .disabled(!settings.shareSafeRedactBeforeSharing)

                    PrivacyFilterSettingsRow(isOn: $settings.shareSafePrivacyFilter)
                        .disabled(!settings.shareSafeRedactBeforeSharing)

                    VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
                        SettingsSubsectionHeader(
                            title: "Redaction style",
                            subtitle: "How sensitive regions are hidden in Share Safe exports. Redact replaces pixels with solid black and cannot be reversed."
                        )

                        RedactionStylePicker(
                            selection: Binding(
                                get: { settings.shareSafeRedactionStyle },
                                set: { settings.shareSafeRedactionStyle = $0 }
                            )
                        )
                    }
                }

                SettingsFootnoteSection("Power tips") {
                    SettingsTipRow(
                        symbol: "pin",
                        text: "Pinned screenshots: scroll to resize, Option+scroll for opacity, double-click or Esc to close."
                    )
                }

                SettingsFootnoteSection("Related") {
                    SettingsQuickLink(
                        title: "Output folder & format",
                        subtitle: "Change where screenshots are saved",
                        pane: .output
                    )
                    SettingsSeparator()
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

private struct ThumbnailPreviewMock: View {
    let duration: Double
    @State private var visible = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: SettingsTheme.spacingM) {
            RoundedRectangle(cornerRadius: AeroTokens.Radius.small, style: .continuous)
                .fill(.quaternary)
                .frame(width: 72, height: 48)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
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
        // Deliberate pulse choreography — slower than Motion tokens by design.
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
