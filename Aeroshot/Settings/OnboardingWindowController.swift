import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {
    private unowned let appState: AppState
    private let onComplete: () -> Void

    init(
        appState: AppState,
        startStep: OnboardingStep = .welcome,
        onComplete: @escaping () -> Void,
        onTestCaptureFinished: @escaping () -> Void = {}
    ) {
        self.appState = appState
        self.onComplete = onComplete

        let resumeKey = "onboardingResumeStep"
        let resumedStep = UserDefaults.standard.object(forKey: resumeKey)
            .flatMap { $0 as? Int }
            .flatMap(OnboardingStep.init(rawValue:))
        UserDefaults.standard.removeObject(forKey: resumeKey)

        let hosting = NSHostingController(
            rootView: OnboardingView(
                startStep: resumedStep ?? startStep,
                runTestCapture: { kind, completion in
                    switch kind {
                    case .area: appState.captureController.beginAreaCapture(onComplete: completion)
                    case .window: appState.captureController.beginWindowCapture(onComplete: completion)
                    case .last: appState.captureController.captureLastRegion(onComplete: completion)
                    }
                },
                onComplete: onComplete,
                onTestCaptureFinished: onTestCaptureFinished
            )
            .environmentObject(appState.settings)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Aeroshot setup"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.setContentSize(NSSize(width: 560, height: 520))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome, screenRecording, accessibility, ready

    var id: Int { rawValue }
    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .screenRecording: "Screen Recording"
        case .accessibility: "Accessibility"
        case .ready: "All set"
        }
    }
}

enum OnboardingCaptureKind: String, CaseIterable, Identifiable {
    case area, window, last

    var id: String { rawValue }
    var action: HotkeyAction {
        switch self {
        case .area: .captureArea
        case .window: .captureWindow
        case .last: .captureLastRegion
        }
    }
}

private enum OnboardingDestination: String, CaseIterable, Identifiable {
    case desktop, clipboard, library

    var id: String { rawValue }
    var title: String {
        switch self {
        case .desktop: "Desktop"
        case .clipboard: "Clipboard"
        case .library: "Library only"
        }
    }
}

private enum OnboardingPalette {
    static let background = Color(red: 17 / 255, green: 20 / 255, blue: 26 / 255)
    static let surface = Color(red: 25 / 255, green: 28 / 255, blue: 34 / 255)
    static let border = Color.white.opacity(0.075)
    static let borderStrong = Color.white.opacity(0.15)
    static let text = Color(red: 237 / 255, green: 238 / 255, blue: 241 / 255)
    static let textSecondary = Color(red: 156 / 255, green: 161 / 255, blue: 171 / 255)
    static let textTertiary = Color(red: 102 / 255, green: 107 / 255, blue: 117 / 255)
    static let accent = Color(red: 1, green: 138 / 255, blue: 107 / 255)
    static let warning = Color(red: 1, green: 180 / 255, blue: 84 / 255)
    static let danger = Color(red: 229 / 255, green: 72 / 255, blue: 77 / 255)
    static let success = Color(red: 95 / 255, green: 211 / 255, blue: 160 / 255)
    static let blue = Color(red: 76 / 255, green: 141 / 255, blue: 1)
}

private struct OnboardingView: View {
    typealias TestCaptureRunner = (OnboardingCaptureKind, @escaping CaptureController.Completion) -> Void

    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let runTestCapture: TestCaptureRunner
    let onComplete: () -> Void
    let onTestCaptureFinished: () -> Void

    @State private var step: OnboardingStep
    @State private var goingForward = true
    @State private var permissionRefresh = UUID()
    @State private var requestedScreenRecording = false
    @State private var requestedAccessibility = false
    @State private var captureKind: OnboardingCaptureKind = .area
    @State private var destination: OnboardingDestination = .desktop
    @State private var tested = false
    @State private var isTestingCapture = false
    @State private var capturedSize: CGSize?
    @FocusState private var focusedControl: FocusTarget?

    private enum FocusTarget: Hashable {
        case back, primary, testCapture
    }

    init(
        startStep: OnboardingStep,
        runTestCapture: @escaping TestCaptureRunner = { _, _ in },
        onComplete: @escaping () -> Void,
        onTestCaptureFinished: @escaping () -> Void = {}
    ) {
        self.runTestCapture = runTestCapture
        self.onComplete = onComplete
        self.onTestCaptureFinished = onTestCaptureFinished
        _step = State(initialValue: startStep)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                switch step {
                case .welcome: welcome
                case .screenRecording: permission(.screenRecording)
                case .accessibility: permission(.accessibility)
                case .ready: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .id(step)
            .transition(stepTransition)

            permissionChips
            footer
        }
        .frame(width: 560, height: 520)
        .background(OnboardingPalette.background)
        .foregroundStyle(OnboardingPalette.text)
        .animation(SettingsTheme.spring(reducedMotion: reduceMotion), value: step)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { permissionRefresh = UUID() }
        }
        .onAppear { focusPrimaryControl() }
        .onChange(of: step) { _, _ in focusPrimaryControl() }
    }

    private func focusPrimaryControl() {
        let target: FocusTarget = step == .ready && SettingsPermissions.screenRecordingGranted && !tested
            ? .testCapture
            : .primary
        DispatchQueue.main.async { focusedControl = target }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Spacer()
            Text("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(OnboardingPalette.textTertiary)
            HStack(spacing: 5) {
                ForEach(OnboardingStep.allCases) { item in
                    Button {
                        navigate(to: item)
                    } label: {
                        Capsule()
                            .fill(item == step ? OnboardingPalette.accent : Color.white.opacity(item.rawValue < step.rawValue ? 0.28 : 0.12))
                            .frame(width: item == step ? 20 : 7, height: 7)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canNavigate(to: item))
                    .opacity(canNavigate(to: item) ? 1 : 0.45)
                    .accessibilityLabel(item.title)
                    .accessibilityValue(item == step ? "Current step" : canNavigate(to: item) ? "Available" : "Complete Screen Recording first")
                    .accessibilityAddTraits(item == step ? .isSelected : [])
                }
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 13)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(OnboardingPalette.accent)
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Aeroshot needs two grants")
                        .font(.system(size: 21, weight: .semibold))
                    Text("About 30 seconds. Both can be revoked any time in System Settings.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(OnboardingPalette.textSecondary)
                }
            }
            .padding(.top, 8)

            VStack(spacing: 9) {
                welcomeRow(
                    symbol: "rectangle.inset.filled.and.person.filled",
                    tint: OnboardingPalette.accent,
                    title: "Screen Recording · required",
                    body: "Reading pixels through ScreenCaptureKit. Without it there is no capture at all."
                )
                welcomeRow(
                    symbol: "arrow.up.and.down",
                    tint: OnboardingPalette.blue,
                    title: "Accessibility · optional",
                    body: "Only for driving scrolling capture and recording click positions."
                )
                welcomeRow(
                    symbol: "house.fill",
                    tint: OnboardingPalette.success,
                    title: "Nothing leaves this Mac",
                    body: "OCR, ShareSafe and the library are on-device. No account, no upload unless you ask."
                )
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 6)
    }

    private func welcomeRow(symbol: String, tint: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(body)
                    .font(.system(size: 11.5))
                    .foregroundStyle(OnboardingPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 13)
        .background(OnboardingPalette.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(OnboardingPalette.border, lineWidth: 1)
        }
    }

    private enum PermissionKind: Equatable {
        case screenRecording, accessibility

        var title: String { self == .screenRecording ? "Screen Recording" : "Accessibility · optional" }
        var symbol: String { self == .screenRecording ? "rectangle.inset.filled.and.person.filled" : "arrow.up.and.down" }
        var tint: Color { self == .screenRecording ? OnboardingPalette.accent : OnboardingPalette.blue }
        var body: String {
            self == .screenRecording
                ? "ScreenCaptureKit cannot hand Aeroshot a single pixel without this. It is the one grant the app genuinely cannot work around."
                : "Only used to post scroll events and read click positions while recording. Everything else works without it."
        }
        var call: String { self == .screenRecording ? "CGPreflightScreenCaptureAccess()" : "AXIsProcessTrustedWithOptions()" }
        var pane: String { self == .screenRecording ? "Screen & System Audio Recording" : "Accessibility" }
        var readyMessage: String {
            self == .screenRecording ? "Nice — screen capture is ready to go." : "Shortcuts will now work everywhere."
        }
        var losses: [String] {
            self == .screenRecording
                ? ["No screenshots, no recordings, no window picker", "Scrolling capture and OCR have nothing to read", "The hotkeys stay registered but do nothing"]
                : ["Scrolling capture cannot drive the page for you", "Click highlights in recordings go unrecorded", "Auto-zoom to clicks in Media Studio is unavailable"]
        }
    }

    private func permission(_ kind: PermissionKind) -> some View {
        let granted = kind == .screenRecording
            ? SettingsPermissions.screenRecordingGranted
            : SettingsPermissions.accessibilityGranted
        let requested = kind == .screenRecording ? requestedScreenRecording : requestedAccessibility
        let stateColor = granted ? OnboardingPalette.success : requested ? OnboardingPalette.warning : OnboardingPalette.textTertiary

        return VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(kind.tint)
                    .frame(width: 40, height: 40)
                    .background(kind.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(kind.title).font(.system(size: 18, weight: .semibold))
                    Text(kind.body)
                        .font(.system(size: 12))
                        .foregroundStyle(OnboardingPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 6)

            HStack(spacing: 10) {
                Circle().fill(stateColor).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 3) {
                    Text(granted ? "Granted" : requested ? "Granted in Settings, not yet in this process" : "Not determined")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(stateColor)
                    Text("\(kind.call) → \(granted ? "true" : "false")")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(OnboardingPalette.textTertiary)
                }
                Spacer()
                Button("Re-check") { permissionRefresh = UUID() }
                    .buttonStyle(OnboardingOutlineButtonStyle(compact: true))
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 13)
            .background(stateColor.opacity(granted || requested ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(granted || requested ? stateColor.opacity(0.35) : OnboardingPalette.border, lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 7) {
                sectionLabel("WITHOUT IT")
                ForEach(kind.losses, id: \.self) { loss in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(kind == .screenRecording ? OnboardingPalette.danger : OnboardingPalette.warning)
                            .frame(width: 5, height: 5)
                        Text(loss)
                            .font(.system(size: 11.5))
                            .foregroundStyle(OnboardingPalette.textSecondary)
                    }
                }
            }

            permissionSettingsCard(kind: kind, granted: granted)

            if kind == .screenRecording, requested, !granted {
                HStack(spacing: 10) {
                    Text("macOS only hands the new grant to a fresh process. Aeroshot will relaunch itself and come back to this step.")
                        .font(.system(size: 11))
                        .foregroundStyle(OnboardingPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Relaunch", action: relaunch)
                        .buttonStyle(OnboardingOutlineButtonStyle(tint: OnboardingPalette.warning, compact: true))
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(OnboardingPalette.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(OnboardingPalette.warning.opacity(0.35), lineWidth: 1)
                }
            }
        }
        .id(permissionRefresh)
        .padding(.horizontal, 30)
        .padding(.top, 6)
    }

    private func permissionSettingsCard(kind: PermissionKind, granted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(kind.tint)
                    .frame(width: 34, height: 34)
                    .background(kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("System Settings → Privacy & Security")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("\(kind.pane) → Aeroshot")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(OnboardingPalette.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
                if granted {
                    Button("Granted ✓", action: {})
                        .buttonStyle(OnboardingOutlineButtonStyle(tint: OnboardingPalette.success, compact: true))
                        .disabled(true)
                } else {
                    Button("Open System Settings…") {
                        if kind == .screenRecording {
                            openScreenRecordingSettings()
                        } else {
                            openAccessibilitySettings()
                        }
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle(monospaced: true))
                }
            }

            Label(
                granted ? kind.readyMessage : "Enable Aeroshot, then return here. The status refreshes automatically.",
                systemImage: granted ? "checkmark.circle.fill" : "arrow.uturn.backward.circle"
            )
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(granted ? OnboardingPalette.success : OnboardingPalette.textTertiary)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .background(OnboardingPalette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(granted ? OnboardingPalette.success.opacity(0.35) : OnboardingPalette.border, lineWidth: 1)
        }
    }

    private var ready: some View {
        let screenGranted = SettingsPermissions.screenRecordingGranted
        let accessibilityGranted = SettingsPermissions.accessibilityGranted

        return VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 13) {
                Image(systemName: screenGranted ? "checkmark" : "exclamationmark.triangle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(screenGranted ? OnboardingPalette.success : OnboardingPalette.warning)
                    .frame(width: 44, height: 44)
                    .background((screenGranted ? OnboardingPalette.success : OnboardingPalette.warning).opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(screenGranted ? "Ready to capture" : "Screen Recording required")
                        .font(.system(size: 18, weight: .semibold))
                    Text(readySubtitle(screenGranted: screenGranted, accessibilityGranted: accessibilityGranted))
                        .font(.system(size: 12))
                        .foregroundStyle(OnboardingPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 6)

            choiceGroup(title: "CAPTURE HOTKEY") {
                ForEach(OnboardingCaptureKind.allCases) { kind in
                    choiceButton(hotkeyLabel(for: kind), selected: captureKind == kind) { captureKind = kind }
                }
            }

            choiceGroup(title: "CAPTURES GO TO") {
                ForEach(OnboardingDestination.allCases) { item in
                    choiceButton(item.title, selected: destination == item) { setDestination(item) }
                }
            }

            VStack(spacing: 1) {
                summaryRow("Hotkey", hotkeyLabel(for: captureKind))
                summaryRow("Destination", destination.title)
                summaryRow("Screen Recording", screenGranted ? "granted" : "required", warning: !screenGranted)
                summaryRow("Accessibility", accessibilityGranted ? "granted" : "optional", warning: false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(OnboardingPalette.border, lineWidth: 1)
            }

            HStack(spacing: 11) {
                if tested {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OnboardingPalette.success)
                        .frame(width: 26, height: 26)
                        .background(OnboardingPalette.success.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                    Text("First capture taken").font(.system(size: 12, weight: .semibold))
                        Text(captureResultSummary)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(OnboardingPalette.textTertiary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Try it before you close this").font(.system(size: 12, weight: .semibold))
                        Text("Press the hotkey now — the grant is only proven by a real capture.")
                            .font(.system(size: 11))
                            .foregroundStyle(OnboardingPalette.textTertiary)
                    }
                    Spacer()
                    Button(isTestingCapture ? "Capturing…" : hotkeyLabel(for: captureKind), action: testCapture)
                        .buttonStyle(OnboardingPrimaryButtonStyle(monospaced: true))
                        .disabled(!screenGranted || isTestingCapture)
                        .focused($focusedControl, equals: .testCapture)
                        .accessibilityHint(screenGranted ? "Starts a real capture, then returns to setup" : "Grant Screen Recording before testing a capture")
                }
            }
            .padding(13)
            .background(tested ? OnboardingPalette.success.opacity(0.08) : OnboardingPalette.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(tested ? OnboardingPalette.success.opacity(0.35) : OnboardingPalette.borderStrong, style: StrokeStyle(lineWidth: 1, dash: tested ? [] : [4]))
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 6)
    }

    private func readySubtitle(screenGranted: Bool, accessibilityGranted: Bool) -> String {
        guard screenGranted else { return "Screen Recording is required before Aeroshot can capture. Grant it in System Settings, then return here." }
        return accessibilityGranted
            ? "Both grants are live. Scrolling capture and click highlights are available."
            : "Screen Recording is live. Scrolling capture stays manual until Accessibility is granted."
    }

    private func choiceGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(title)
            HStack(spacing: 6) { content() }
        }
    }

    private func choiceButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(selected ? OnboardingPalette.accent : OnboardingPalette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(selected ? OnboardingPalette.accent.opacity(0.11) : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(selected ? OnboardingPalette.accent.opacity(0.34) : OnboardingPalette.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(selected ? "Selected" : "")
    }

    private func summaryRow(_ key: String, _ value: String, warning: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(key.uppercased())
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(OnboardingPalette.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(warning ? OnboardingPalette.warning : OnboardingPalette.textSecondary)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(OnboardingPalette.surface)
    }

    private var permissionChips: some View {
        HStack(spacing: 6) {
            permissionChip("Screen Recording", granted: SettingsPermissions.screenRecordingGranted, target: .screenRecording) { navigate(to: .screenRecording) }
            permissionChip("Accessibility", granted: SettingsPermissions.accessibilityGranted, target: .accessibility) { navigate(to: .accessibility) }
            Spacer()
        }
        .id(permissionRefresh)
        .padding(.horizontal, 30)
        .padding(.top, 12)
    }

    private func permissionChip(_ label: String, granted: Bool, target: OnboardingStep, action: @escaping () -> Void) -> some View {
        let available = canNavigate(to: target)
        return Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(granted ? OnboardingPalette.success : OnboardingPalette.textTertiary)
                    .frame(width: 5, height: 5)
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(granted ? OnboardingPalette.success : OnboardingPalette.textTertiary)
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(granted ? OnboardingPalette.success.opacity(0.35) : OnboardingPalette.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.45)
        .accessibilityValue(granted ? "Granted" : available ? "Needs attention" : "Complete Screen Recording first")
        .accessibilityHint(available ? "Opens the \(label) permission step" : "Complete Screen Recording first")
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Back") {
                guard let previous = step.previous else { return }
                navigate(to: previous)
            }
            .buttonStyle(OnboardingOutlineButtonStyle())
            .disabled(step == .welcome)
            .opacity(step == .welcome ? 0.3 : 1)
            .focused($focusedControl, equals: .back)

            Spacer()

            if isPermissionStep, !currentPermissionGranted {
                Button("Skip for now") { advance(skippingPermission: true) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(OnboardingPalette.textTertiary)
            }

            Button(primaryTitle, action: primary)
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .focused($focusedControl, equals: .primary)
                .accessibilityHint(step == .ready && !SettingsPermissions.screenRecordingGranted ? "Opens Screen Recording settings" : "Activates the current setup step")
        }
        .padding(.horizontal, 30)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    private var isPermissionStep: Bool { step == .screenRecording || step == .accessibility }
    private var currentPermissionGranted: Bool {
        switch step {
        case .screenRecording: SettingsPermissions.screenRecordingGranted
        case .accessibility: SettingsPermissions.accessibilityGranted
        default: false
        }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Start"
        case .ready: SettingsPermissions.screenRecordingGranted ? "Finish" : "Grant Screen Recording"
        case .screenRecording, .accessibility: currentPermissionGranted ? "Continue" : "Open System Settings"
        }
    }

    private var stepTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .offset(x: goingForward ? 14 : -14)),
            removal: .opacity.combined(with: .offset(x: goingForward ? -14 : 14))
        )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(OnboardingPalette.textTertiary)
    }

    private func hotkeyLabel(for kind: OnboardingCaptureKind) -> String {
        (settings.hotkeys()[kind.action] ?? kind.action.defaultHotkey).displayString
    }

    private var captureResultSummary: String {
        let dimensions = capturedSize.map { "\(Int($0.width)) × \(Int($0.height))" } ?? "Capture complete"
        return "\(dimensions) · \(destination.title) · it's in your library"
    }

    private func setDestination(_ newDestination: OnboardingDestination) {
        destination = newDestination
        switch newDestination {
        case .desktop:
            settings.saveDirectoryPath = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0].path
            settings.saveToDiskAfterCapture = true
            settings.copyToClipboardAfterCapture = false
        case .clipboard:
            settings.saveToDiskAfterCapture = false
            settings.copyToClipboardAfterCapture = true
        case .library:
            settings.saveToDiskAfterCapture = false
            settings.copyToClipboardAfterCapture = false
        }
    }

    private func testCapture() {
        guard SettingsPermissions.screenRecordingGranted, !isTestingCapture else { return }
        setDestination(destination)
        isTestingCapture = true
        runTestCapture(captureKind) { image in
            DispatchQueue.main.async {
                isTestingCapture = false
                if let image {
                    capturedSize = CGSize(width: image.width, height: image.height)
                    tested = true
                }
                onTestCaptureFinished()
                focusPrimaryControl()
            }
        }
    }

    private func primary() {
        switch step {
        case .welcome:
            advance()
        case .screenRecording:
            if SettingsPermissions.screenRecordingGranted { advance() } else { openScreenRecordingSettings() }
        case .accessibility:
            if SettingsPermissions.accessibilityGranted { advance() } else { openAccessibilitySettings() }
        case .ready:
            guard SettingsPermissions.screenRecordingGranted else {
                navigate(to: .screenRecording)
                openScreenRecordingSettings()
                return
            }
            settings.hasCompletedOnboarding = true
            onComplete()
        }
    }

    private func advance(skippingPermission: Bool = false) {
        guard let next = step.next else { return }
        if skippingPermission || currentPermissionGranted || !isPermissionStep {
            navigate(to: next, allowRequiredSkip: skippingPermission)
        }
    }

    private func canNavigate(to newStep: OnboardingStep) -> Bool {
        guard newStep.rawValue > step.rawValue else { return true }
        guard SettingsPermissions.screenRecordingGranted else {
            return newStep == .screenRecording
        }
        return true
    }

    private func navigate(to newStep: OnboardingStep, allowRequiredSkip: Bool = false) {
        guard allowRequiredSkip || canNavigate(to: newStep) else { return }
        goingForward = newStep.rawValue >= step.rawValue
        step = newStep
        SettingsTheme.performHaptic()
    }

    private func openScreenRecordingSettings() {
        requestedScreenRecording = true
        SettingsPermissions.requestScreenRecording()
        permissionRefresh = UUID()
    }

    private func openAccessibilitySettings() {
        requestedAccessibility = true
        SettingsPermissions.requestAccessibility()
        permissionRefresh = UUID()
    }

    private func relaunch() {
        UserDefaults.standard.set(OnboardingStep.screenRecording.rawValue, forKey: "onboardingResumeStep")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}

private struct OnboardingOutlineButtonStyle: ButtonStyle {
    var tint = OnboardingPalette.textSecondary
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 10.5 : 11.5, weight: compact ? .medium : .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, compact ? 10 : 14)
            .frame(height: compact ? 26 : 34)
            .background(configuration.isPressed ? Color.white.opacity(0.05) : Color.clear, in: RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
                    .strokeBorder(compact ? tint.opacity(0.5) : OnboardingPalette.borderStrong, lineWidth: 1)
            }
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    var monospaced = false

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.label
            if !monospaced {
                Text("↵")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .opacity(0.6)
            }
        }
        .font(.system(size: monospaced ? 11.5 : 12, weight: .semibold, design: monospaced ? .monospaced : .default))
        .foregroundStyle(Color(red: 18 / 255, green: 21 / 255, blue: 28 / 255))
        .padding(.horizontal, monospaced ? 12 : 16)
        .frame(height: monospaced ? 30 : 34)
        .background(OnboardingPalette.accent.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: monospaced ? 8 : 9, style: .continuous))
    }
}
