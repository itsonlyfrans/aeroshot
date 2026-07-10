import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {
    private unowned let appState: AppState
    private let onComplete: () -> Void

    init(appState: AppState, startStep: OnboardingStep = .welcome, onComplete: @escaping () -> Void) {
        self.appState = appState
        self.onComplete = onComplete
        let hosting = NSHostingController(
            rootView: OnboardingView(startStep: startStep, onComplete: onComplete)
                .environmentObject(appState.settings)
                .environmentObject(appState)
        )

        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Aeroshot"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.setContentSize(NSSize(width: 560, height: 600))
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

// MARK: - Steps

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome, permissions, shortcuts, ready

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .permissions: return "Permissions"
        case .shortcuts: return "Shortcuts"
        case .ready: return "Ready"
        }
    }
}

// MARK: - Root view

struct OnboardingView: View {
    @EnvironmentObject var settings: SettingsStore
    let onComplete: () -> Void

    @State private var step: OnboardingStep
    @State private var goingForward = true
    @State private var permissionRefresh = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(startStep: OnboardingStep, onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        _step = State(initialValue: startStep)
    }

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(step)
                    .transition(stepTransition)

                Divider().opacity(0.4)

                footer
                    .padding(.horizontal, SettingsTheme.spacingXL)
                    .padding(.vertical, SettingsTheme.spacingL)
            }
        }
        .frame(width: 560, height: 600)
        .animation(SettingsTheme.spring(reducedMotion: reduceMotion), value: step)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            DispatchQueue.main.async { permissionRefresh = UUID() }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            OnboardingWelcomeStep()
        case .permissions:
            OnboardingPermissionsStep()
                .id(permissionRefresh)
        case .shortcuts:
            OnboardingShortcutsStep()
        case .ready:
            OnboardingReadyStep()
        }
    }

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: goingForward ? 32 : -32)),
            removal: .opacity.combined(with: .offset(x: goingForward ? -32 : 32))
        )
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: SettingsTheme.spacingM) {
            if step == .welcome {
                Button("Skip setup") { finish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .font(.callout)
                    .focusable(false)
            } else {
                Button {
                    goingForward = false
                    step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome
                    SettingsTheme.performHaptic()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.titleOnly)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.callout)
            }

            Spacer()

            OnboardingProgressDots(current: step)

            Spacer()

            Button(primaryTitle) {
                advance()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .focusEffectDisabled()
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "Get Started"
        case .permissions: return SettingsPermissions.allGranted ? "Continue" : "Continue Anyway"
        case .shortcuts: return "Continue"
        case .ready: return "Start Capturing"
        }
    }

    private func advance() {
        SettingsTheme.performHaptic()
        if step == .ready {
            finish()
            return
        }
        goingForward = true
        step = OnboardingStep(rawValue: step.rawValue + 1) ?? .ready
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        onComplete()
    }
}

// MARK: - Progress dots

private struct OnboardingProgressDots: View {
    let current: OnboardingStep
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases) { step in
                Capsule()
                    .fill(step == current ? SettingsTheme.accent : Color.primary.opacity(0.15))
                    .frame(width: step == current ? 22 : 7, height: 7)
            }
        }
        .animation(SettingsTheme.spring(reducedMotion: reduceMotion), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current.rawValue + 1) of \(OnboardingStep.allCases.count): \(current.title)")
    }
}

// MARK: - Background

private struct OnboardingBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SettingsShellBackground()
    }
}

// MARK: - Shared step scaffold

private struct OnboardingStepScaffold<Content: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: SettingsTheme.spacingL) {
            OnboardingMark(symbol: symbol)
                .padding(.top, SettingsTheme.spacingXL + SettingsTheme.spacingM)

            VStack(spacing: SettingsTheme.spacingS) {
                Text(title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, SettingsTheme.spacingXL)

            content()
                .frame(maxWidth: 430)
                .padding(.horizontal, SettingsTheme.spacingXL)

            Spacer(minLength: 0)
        }
    }
}

/// Gradient app-style mark with a soft pulse ring.
private struct OnboardingMark: View {
    let symbol: String
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(SettingsTheme.accent)
                .frame(width: 68, height: 68)
                .shadow(color: SettingsTheme.accent.opacity(0.30), radius: pulse ? 18 : 10, y: 6)

            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Step 1: Welcome

private struct OnboardingWelcomeStep: View {
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let features: [(symbol: String, tint: Color, title: String, detail: String)] = [
        ("rectangle.dashed", SettingsTheme.accent, "Pixel-perfect screenshots", "Area, window, full screen, and repeat-last-region capture."),
        ("record.circle", .red, "Recordings & GIFs", "MP4 or GIF with webcam bubble, mic, and click highlights."),
        ("arrow.up.and.down.text.horizontal", .teal, "Scrolling capture", "Stitch long pages into one tall, seamless image."),
        ("text.viewfinder", SettingsTheme.warning, "Text & privacy tools", "Grab text with OCR and auto-redact sensitive info with Share Safe.")
    ]

    var body: some View {
        OnboardingStepScaffold(
            symbol: "camera.viewfinder",
            title: "Welcome to Aeroshot",
            subtitle: "The fast, keyboard-first capture studio for your Mac.\nHere's what it can do."
        ) {
            VStack(spacing: SettingsTheme.spacingS) {
                ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                    HStack(spacing: SettingsTheme.spacingM) {
                        Image(systemName: feature.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(feature.tint)
                            .frame(width: SettingsTheme.iconBadgeSize - 4, height: SettingsTheme.iconBadgeSize - 4)
                            .background(feature.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius - 1, style: .continuous))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(feature.title)
                                .font(.subheadline.weight(.semibold))
                            Text(feature.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 56, alignment: .leading)
                    .padding(SettingsTheme.spacingS + 2)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                            .strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(
                        reduceMotion ? nil : SettingsTheme.spring.delay(0.08 + Double(index) * 0.07),
                        value: appeared
                    )
                }
            }
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Step 2: Permissions

private struct OnboardingPermissionsStep: View {
    var body: some View {
        OnboardingStepScaffold(
            symbol: "lock.shield",
            title: "Grant access",
            subtitle: "macOS asks for these once. Aeroshot never leaves your Mac —\ncaptures stay local unless you share them."
        ) {
            VStack(spacing: SettingsTheme.spacingS) {
                SettingsPermissionTile(
                    title: "Screen Recording",
                    description: "Required for area, window, full-screen, and video capture.",
                    granted: SettingsPermissions.screenRecordingGranted,
                    openSettings: { SettingsPermissions.requestScreenRecording() }
                )

                SettingsPermissionTile(
                    title: "Accessibility",
                    description: "Powers global shortcuts, click highlights, and auto-scroll.",
                    granted: SettingsPermissions.accessibilityGranted,
                    openSettings: { SettingsPermissions.requestAccessibility() }
                )

                if !SettingsPermissions.allGranted {
                    HStack(spacing: SettingsTheme.spacingS) {
                        Image(systemName: "arrow.uturn.backward.circle")
                            .foregroundStyle(.secondary)
                        Text("After enabling in System Settings, switch back here — status updates automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, SettingsTheme.spacingXS)
                } else {
                    HStack(spacing: SettingsTheme.spacingS) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(SettingsTheme.success)
                        Text("All set — you're ready for every capture mode.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, SettingsTheme.spacingXS)
                }
            }
        }
    }
}

// MARK: - Step 3: Shortcuts

private struct OnboardingShortcutsStep: View {
    @EnvironmentObject var settings: SettingsStore

    private let highlighted: [HotkeyAction] = [.allInOne, .captureArea, .captureScrolling, .captureOCR, .recordArea]

    var body: some View {
        OnboardingStepScaffold(
            symbol: "keyboard",
            title: "Capture from anywhere",
            subtitle: "Global shortcuts work in any app. Start with All-in-One —\nit puts every capture mode one keystroke away."
        ) {
            VStack(spacing: 0) {
                let hotkeys = settings.hotkeys()
                ForEach(Array(highlighted.enumerated()), id: \.element.id) { index, action in
                    if index > 0 {
                        SettingsSeparator()
                    }
                    SettingsShortcutRow(
                        symbol: action.symbol,
                        title: action.displayName,
                        keycap: (hotkeys[action] ?? action.defaultHotkey).displayString
                    )
                    .padding(.horizontal, SettingsTheme.spacingS)
                }
            }
            .padding(.vertical, SettingsTheme.spacingXS)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous)
                    .strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5)
            }

            Text("Every shortcut is customizable later in Settings → Shortcuts.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, SettingsTheme.spacingS)
        }
    }
}

// MARK: - Step 4: Ready

private struct OnboardingReadyStep: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        OnboardingStepScaffold(
            symbol: "checkmark",
            title: "You're all set",
            subtitle: "Aeroshot is ready when you are.\nLook for the viewfinder in the menu bar, or add a Dock icon in Settings."
        ) {
            VStack(spacing: SettingsTheme.spacingM) {
                HStack(spacing: SettingsTheme.spacingM) {
                    Image(systemName: "menubar.arrow.up.rectangle")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(SettingsTheme.accent)
                        .frame(width: SettingsTheme.iconBadgeSize, height: SettingsTheme.iconBadgeSize)
                        .background(SettingsTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Menu bar by default")
                            .font(.subheadline.weight(.semibold))
                        Text("Aeroshot stays out of your way in the menu bar. Click the viewfinder icon or press \((settings.hotkeys()[.allInOne] ?? HotkeyAction.allInOne.defaultHotkey).displayString) anytime. Prefer the Dock? Enable \"Show in Dock\" in Settings → System.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(SettingsTheme.spacingM)
                .frame(minHeight: SettingsTheme.selectionCardMinHeight, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous)
                        .strokeBorder(SettingsTheme.borderSubtle, lineWidth: 0.5)
                }

                SettingsLinkButton(title: "Fine-tune everything in Settings", symbol: "gearshape") {
                    settings.hasCompletedOnboarding = true
                    appState.showSettingsWindow()
                }
            }
        }
    }
}
