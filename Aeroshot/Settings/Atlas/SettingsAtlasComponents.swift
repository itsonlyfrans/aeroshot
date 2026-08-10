import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsAtlasTopBar: View {
    @EnvironmentObject private var settings: SettingsStore
    @Binding var route: SettingsAtlasRoute
    let openPalette: () -> Void

    var body: some View {
        HStack {
            Button("Atlas") { route = .atlas }
                .buttonStyle(.plain)
            Spacer()
            Button(settings.activeCaptureProfile.name) { cycleProfile() }
                .buttonStyle(.bordered)
            Button("Search every setting") { openPalette() }
                .buttonStyle(.bordered)
                .keyboardShortcut("k", modifiers: .command)
        }
        .padding()
        .background(.bar)
    }

    private func cycleProfile() {
        let profiles = CaptureProfile.builtIn
        guard let index = profiles.firstIndex(where: { $0.id == settings.activeCaptureProfileID }) else {
            settings.applyCaptureProfile(profiles[0])
            return
        }
        settings.applyCaptureProfile(profiles[(index + 1) % profiles.count])
    }
}

struct SettingsAtlasMetricCard: View {
    let value: String
    let label: String
    let symbol: String
    var tint: Color = .accentColor

    var body: some View {
        Label(value, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(tint)
            .accessibilityLabel("\(label): \(value)")
    }
}

struct SettingsAtlasCategoryCard: View {
    let category: SettingsAtlasCategory
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Label(category.name, systemImage: category.symbol)
                    .font(.headline)
                Text(category.blurb)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .padding()
        }
        .buttonStyle(.bordered)
    }
}

struct SettingsAtlasBandHeader: View {
    let band: SettingsAtlasBand

    var body: some View {
        VStack(alignment: .leading) {
            Text(band.title).font(.caption.weight(.bold))
            Text(band.blurb).font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 112, alignment: .leading)
    }
}

struct SettingsAtlasPalette: View {
    @Binding var query: String
    let results: [SettingsAtlasPaletteItem]
    @Binding var selectedIndex: Int
    let onSelect: (SettingsAtlasPaletteItem) -> Void
    let onToggle: (SettingsAtlasPaletteItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search settings", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("settings.atlas.search")
            if results.isEmpty {
                Text("No matching settings")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    Button {
                        selectedIndex = index
                        onSelect(result)
                    } label: {
                        HStack {
                            Label(result.title, systemImage: result.symbol)
                            Spacer()
                            if let value = result.value { Text(value).foregroundStyle(.secondary) }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if result.isToggleable { Button("Toggle") { onToggle(result) } }
                    }
                }
            }
        }
        .padding()
        .frame(width: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SettingsAtlasTerritoryView: View {
    let category: SettingsAtlasCategoryID
    @Binding var highlightedRowID: String?

    @EnvironmentObject private var settings: SettingsStore
    @State private var hotkeys: [HotkeyAction: Hotkey] = [:]
    @State private var hotkeyErrors: [HotkeyAction: String] = [:]
    @State private var showResetConfirmation = false

    static func sectionTitles(for category: SettingsAtlasCategoryID) -> [String] {
        switch category {
        case .capture: ["Capture", "After capture"]
        case .screenRecording: ["Recording"]
        case .gifRecording: ["GIF"]
        case .screenshotEditor: ["Editor"]
        case .export: ["Export"]
        case .sharingUploads: ["Uploads"]
        case .general: ["General"]
        case .hotkeys: ["Hotkeys", "Permission"]
        case .privacy: ["Redaction", "Permissions"]
        case .advanced: ["Automation", "Configuration"]
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content }
                .padding(28)
        }
        .onAppear { hotkeys = settings.hotkeys() }
        .confirmationDialog("Reset all settings?", isPresented: $showResetConfirmation) {
            Button("Reset all settings", role: .destructive) { settings.resetAllToDefaults() }
        }
        .accessibilityIdentifier("settings.atlas.territory.\(category.rawValue)")
    }

    @ViewBuilder
    private var content: some View {
        switch category {
        case .capture: captureContent
        case .screenRecording: recordingContent
        case .gifRecording: gifContent
        case .screenshotEditor: editorContent
        case .export: exportContent
        case .sharingUploads: uploadContent
        case .general: generalContent
        case .hotkeys: hotkeysContent
        case .privacy: privacyContent
        case .advanced: advancedContent
        }
    }

    private var captureContent: some View {
        Group {
            section("Capture") {
                row("Recall last region", "Use the previous capture region.", id: "capture.last-region") { toggle($settings.recallLastRegionEnabled) }
                row("Selection aspect lock", "Set the area capture aspect ratio.", id: "capture.aspect") { aspectLockChoice }
                row("Capture delay", "Wait before capture starts.", id: "capture.delay") { captureDelayChoice }
                row("Freeze screen", "Keep the captured frame visible.", id: "capture.freeze") { toggle($settings.freezeScreenDuringCapture) }
                row("Play capture sound", "Play a sound after capture.", id: "capture.sound") { toggle($settings.playCaptureSound) }
                row("Capture sound", "Choose the capture sound.", id: "capture.sound-effect") { soundChoice }
                row("Downscale Retina captures", "Write 1× image files.", id: "capture.retina") { toggle($settings.downscaleRetina) }
                row("Scrolling capture", "Scroll automatically during scrolling capture.", id: "capture.scroll") { toggle($settings.scrollingAutoScroll) }
            }
            section("After capture") {
                row("Open editor", "Open the editor after capture.", id: "capture.editor") { toggle($settings.openEditorAfterCapture) }
                row("Copy to clipboard", "Copy the capture after capture.", id: "capture.clipboard") { toggle($settings.copyToClipboardAfterCapture) }
                row("Save to disk", "Write the capture to the output folder.", id: "capture.save") { toggle($settings.saveToDiskAfterCapture) }
                row("Show thumbnail", "Show the capture thumbnail.", id: "capture.thumbnail") { toggle($settings.showThumbnailAfterCapture) }
                row("Thumbnail actions", "Choose the thumbnail actions.", id: "capture.thumbnail-actions") {
                    Menu {
                        ForEach(ThumbnailAction.allCases) { action in
                            let selected = settings.thumbnailVisibleActions.contains(action)
                            Button {
                                settings.setThumbnailAction(action, visible: !selected)
                            } label: {
                                Label(action.title, systemImage: selected ? "checkmark" : action.symbol)
                            }
                            .disabled(!selected && settings.thumbnailVisibleActions.count >= 4)
                        }
                    } label: {
                        Text(settings.thumbnailVisibleActions.isEmpty ? "None" : settings.thumbnailVisibleActions.map(\.title).joined(separator: ", "))
                    }
                }
                row("Always show actions", "Keep thumbnail actions visible.", id: "capture.thumbnail-actions-always") { toggle($settings.showThumbnailActionsAlways) }
                row("Thumbnail duration", "Set how long the thumbnail stays visible.", id: "capture.thumbnail-duration") { Slider(value: $settings.thumbnailDuration, in: 1...15, step: 1).frame(width: 160) }
                row("Thumbnail swipe fingers", "Set the thumbnail swipe gesture.", id: "capture.thumbnail-swipe-fingers") { swipeFingerChoice }
                ForEach(ThumbnailSwipeDirection.allCases) { direction in
                    row("\(settings.thumbnailSwipeFingerCount.title) \(direction.title) swipe", "Set the action for this gesture.", id: "capture.thumbnail-swipe.\(settings.thumbnailSwipeFingerCount.rawValue).\(direction.rawValue)") {
                        Picker("Thumbnail swipe action", selection: Binding(
                            get: { settings.thumbnailSwipeBindings.action(for: settings.thumbnailSwipeFingerCount, direction: direction) },
                            set: { settings.setThumbnailSwipeAction($0, fingers: settings.thumbnailSwipeFingerCount, direction: direction) }
                        )) {
                            ForEach(ThumbnailGestureAction.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                    }
                }
                row("Add OCR captures to history", "Save text captures in history.", id: "capture.ocr-history") { toggle($settings.addOCRCapturesToHistory) }
            }
        }
    }

    private var recordingContent: some View {
        section("Recording") {
            row("Container", "Set the recording output format.", id: "rec.container") { recordingFormatChoice }
            if settings.recordingFormat == .mp4 {
                row("Capture system audio", "Record system audio.", id: "rec.system-audio") { toggle($settings.recordSystemAudio) }
                row("Record microphone", "Record microphone audio.", id: "rec.microphone") { toggle($settings.recordMicrophone) }
            }
            row("Webcam overlay", "Show the webcam overlay.", id: "rec.webcam") { toggle($settings.showWebcamOverlay) }
            row("Highlight clicks", "Show click highlights in recordings.", id: "rec.click-highlight") { toggle($settings.highlightClicksDuringRecording) }
            row("Add recordings to history", "Add finished recordings to history.", id: "rec.history") { toggle($settings.addRecordingsToHistory) }
        }
    }

    private var gifContent: some View {
        section("GIF") {
            row("Frame rate", "Set the GIF frame rate.", id: "gif.fps") { Slider(value: Binding(get: { Double(settings.gifFPS) }, set: { settings.gifFPS = Int($0.rounded()) }), in: 6...30, step: 1).frame(width: 160) }
            row("Maximum frames", "Set the GIF frame limit.", id: "gif.frames") { Slider(value: Binding(get: { Double(settings.gifMaxFrames) }, set: { settings.gifMaxFrames = Int($0.rounded()) }), in: 30...900, step: 30).frame(width: 160) }
        }
    }

    private var editorContent: some View {
        section("Editor") {
            row("Beautify by default", "Apply presentation framing to new editor documents.", id: "editor.beautify") { toggle($settings.beautifyEnabledDefault) }
            row("Canvas padding", "Set the canvas padding.", id: "editor.padding") { Slider(value: $settings.beautifyPadding, in: 0...160, step: 4).frame(width: 160) }
            row("Corner radius", "Set the image corner radius.", id: "editor.radius") { Slider(value: $settings.beautifyCornerRadius, in: 0...40, step: 2).frame(width: 160) }
            row("Shadow radius", "Set the image shadow radius.", id: "editor.shadow") { Slider(value: $settings.beautifyShadowRadius, in: 0...80, step: 2).frame(width: 160) }
            row("Background", "Set the presentation background.", id: "editor.gradient") { gradientChoice }
            row("Canvas aspect", "Set the default canvas aspect.", id: "editor.aspect") { aspectChoice }
        }
    }

    private var exportContent: some View {
        section("Export") {
            row("Image format", "Set the image output format.", id: "export.image-format") { imageFormatChoice }
            row("Image quality", "Set quality for lossy image formats.", id: "export.quality") { Slider(value: $settings.jpegQuality, in: 0.4...1, step: 0.01).frame(width: 160) }
            row("Filename template", "Set the screenshot filename template.", id: "export.template") { TextField("Screenshot {date} at {time}", text: $settings.filenameTemplate).frame(width: 260) }
            row("Recording filename template", "Set the recording filename template.", id: "export.recording-template") { TextField("Screen Recording {date} at {time}", text: $settings.recordingFilenameTemplate).frame(width: 260) }
            row("Output folder", "Choose the output folder.", id: "export.destination") { Button("Choose…", action: chooseSaveDirectory) }
        }
    }

    private var uploadContent: some View {
        section("Uploads") {
            row("Webhook URL", "Set the HTTPS upload endpoint.", id: "share.endpoint") { TextField("https://example.com/upload", text: $settings.uploadWebhookURL).frame(width: 260) }
            row("Upload after capture", "Upload captured files automatically.", id: "share.upload") { toggle($settings.uploadAfterCapture) }
            row("Copy returned link", "Copy the webhook response link.", id: "share.copy") { toggle($settings.copyLinkAfterUpload) }
            row("Redact before upload", "Require redaction review before upload.", id: "share.warn") { toggle($settings.shareSafeRedactBeforeSharing) }
        }
    }

    private var generalContent: some View {
        section("General") {
            row("Show in menu bar", "Show the capture menu in the menu bar.", id: "general.menu-bar") { toggle($settings.showInMenuBar) }
            row("Show in Dock", "Show the app icon in the Dock.", id: "general.dock") { toggle($settings.showInDock) }
            row("Capture profile", "Apply a built-in capture profile.", id: "general.profile") { profileChoice }
        }
    }

    private var hotkeysContent: some View {
        Group {
            section("Hotkeys") {
                ForEach(HotkeyAction.allCases) { action in
                    row(action.displayName, "Set the shortcut for \(action.displayName).", id: "hotkey.\(action.rawValue)") {
                        SettingsAtlasHotkeyControl(action: action, hotkey: Binding(get: { hotkeys[action] ?? action.defaultHotkey }, set: { hotkeys[action] = $0 }), errorMessage: hotkeyErrors[action]) { hotkey in
                            settings.setHotkey(hotkey, for: action)
                            hotkeys = settings.hotkeys()
                            hotkeyErrors[action] = nil
                            (NSApp.delegate as? AppDelegate)?.rebindHotkeys()
                        } onValidationError: { message in
                            hotkeyErrors[action] = message
                        }
                    }
                }
            }
            section("Permission") {
                permissionRow("Accessibility", SettingsPermissions.accessibilityGranted) { SettingsPermissions.requestAccessibility() }
            }
        }
    }

    private var privacyContent: some View {
        Group {
            section("Redaction") {
                row("Sensitive-information detection", "Find sensitive information in captures.", id: "privacy.detection") { toggle($settings.shareSafeSmartScan) }
                row("Default redaction", "Set the redaction style.", id: "privacy.redaction") { redactionChoice }
                row("Redact before sharing", "Require review before sharing flagged captures.", id: "privacy.before-share") { toggle($settings.shareSafeRedactBeforeSharing) }
            }
            section("Permissions") {
                permissionRow("Screen Recording", SettingsPermissions.screenRecordingGranted) { SettingsPermissions.requestScreenRecording() }
                permissionRow("Accessibility", SettingsPermissions.accessibilityGranted) { SettingsPermissions.requestAccessibility() }
                permissionRow("Microphone", SettingsPermissions.microphoneGranted) { Task { _ = await SettingsPermissions.requestMicrophone() } }
                permissionRow("Camera", SettingsPermissions.cameraGranted) { Task { _ = await SettingsPermissions.requestCamera() } }
            }
        }
    }

    private var advancedContent: some View {
        Group {
            section("Automation") {
                row("Automation", "Use URL, command-line, Shortcuts, and AppleScript actions.", id: "advanced.automation") { Text("Available").foregroundStyle(.secondary) }
            }
            section("Configuration") {
                row("Export settings profile", "Save the current settings profile.", id: "advanced.export") { Button("Export…", action: exportProfile) }
                row("Reset all settings", "Restore Aeroshot preferences and shortcuts.", id: "advanced.reset") { Button("Reset", role: .destructive) { showResetConfirmation = true } }
            }
        }
    }

    private var captureDelayChoice: some View {
        Picker("Capture delay", selection: $settings.captureDelaySeconds) {
            Text("Off").tag(0); Text("3 seconds").tag(3); Text("5 seconds").tag(5); Text("10 seconds").tag(10)
        }.labelsHidden()
    }

    private var aspectLockChoice: some View {
        Picker("Selection aspect lock", selection: $settings.selectionAspectLock) {
            ForEach(SelectionAspectLock.allCases) { Text($0.displayName).tag($0) }
        }.labelsHidden()
    }

    private var soundChoice: some View {
        Picker("Capture sound", selection: $settings.selectedCaptureSound) {
            ForEach(settings.availableSounds) { Text($0.displayName).tag($0.filename) }
        }.labelsHidden()
    }

    private var swipeFingerChoice: some View {
        Picker("Thumbnail swipe fingers", selection: $settings.thumbnailSwipeFingerCount) {
            ForEach(ThumbnailSwipeFingerCount.allCases) { Text($0.title).tag($0) }
        }.labelsHidden()
    }

    private var recordingFormatChoice: some View {
        Picker("Recording container", selection: $settings.recordingFormat) {
            ForEach(RecordingFormat.allCases) { Text($0.displayName).tag($0) }
        }.labelsHidden()
    }

    private var imageFormatChoice: some View {
        Picker("Image format", selection: $settings.imageFormat) {
            ForEach(ImageFormat.allCases) { Text($0.displayName).tag($0) }
        }.labelsHidden()
    }

    private var profileChoice: some View {
        Picker("Capture profile", selection: Binding(get: { settings.activeCaptureProfileID }, set: { id in
            guard let profile = CaptureProfile.builtIn.first(where: { $0.id == id }) else { return }
            settings.applyCaptureProfile(profile)
        })) {
            ForEach(CaptureProfile.builtIn, id: \.id) { Text($0.name).tag($0.id) }
        }.labelsHidden()
    }

    private var gradientChoice: some View {
        Picker("Background", selection: $settings.beautifyGradientPreset) {
            ForEach(BeautifySettings.GradientPreset.allCases) { Text($0.displayName).tag($0) }
        }.labelsHidden()
    }

    private var aspectChoice: some View {
        Picker("Canvas aspect", selection: $settings.beautifyAspectPreset) {
            ForEach(BeautifySettings.AspectPreset.allCases) { Text($0.displayName).tag($0) }
        }.labelsHidden()
    }

    private var redactionChoice: some View {
        Picker("Default redaction", selection: $settings.shareSafeRedactionStyle) {
            ForEach(ShareSafeRedactionStyle.allCases) { Text($0.displayName).tag($0) }
        }.labelsHidden()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.headline).padding(.bottom, 6)
            content()
        }
        .id(title)
    }

    private func row<Control: View>(_ title: String, _ detail: String, id: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            control()
        }
        .padding(.vertical, 9)
        .id(id)
        .background(highlightedRowID == id ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private func toggle(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: binding).labelsHidden()
    }

    private func permissionRow(_ title: String, _ granted: Bool, action: @escaping () -> Void) -> some View {
        row(title, granted ? "Permission granted." : "Grant this macOS permission.", id: "permission.\(title)") {
            Button(granted ? "Granted" : "Grant…", action: action).disabled(granted)
        }
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.saveDirectory
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            settings.saveDirectoryPath = url.path
        }
    }

    private func exportProfile() {
        guard let data = settings.exportProfile() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Aeroshot Profile.json"
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}

private struct SettingsAtlasHotkeyControl: View {
    let action: HotkeyAction
    @Binding var hotkey: Hotkey
    let errorMessage: String?
    let onChange: (Hotkey) -> Void
    let onValidationError: (String?) -> Void

    var body: some View {
        HotkeyRecorderView(action: action, hotkey: $hotkey, validationMessage: { _ in nil }, onChange: onChange, onValidationError: onValidationError)
            .frame(width: 120, height: 24)
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(errorMessage == nil ? Color.secondary : Color.orange) }
    }
}
