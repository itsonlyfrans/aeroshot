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
            rootView: AtlasOnboardingProductionView(startStep: startStep, onComplete: onComplete)
                .environmentObject(appState.settings)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Aeroshot setup"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.setContentSize(NSSize(width: 720, height: 650))
        window.minSize = NSSize(width: 680, height: 610)
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

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .screenRecording: "Screen Recording"
        case .accessibility: "Accessibility"
        case .ready: "All set"
        }
    }

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
}

struct OnboardingView: View {
    @EnvironmentObject private var settings: SettingsStore
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
        VStack(spacing: 0) {
            setupHeader

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .id(step)
                .transition(stepTransition)

            Divider().opacity(0.4)
            footer
        }
        .frame(width: 560, height: 520)
        .background(SettingsShellBackground())
        .animation(SettingsTheme.spring(reducedMotion: reduceMotion), value: step)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            DispatchQueue.main.async { permissionRefresh = UUID() }
        }
    }

    private var setupHeader: some View {
        VStack(spacing: SettingsTheme.spacingM) {
            HStack(spacing: SettingsTheme.spacingS) {
                RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                    .fill(SettingsTheme.accent)
                    .frame(width: 34, height: 34)
                    .overlay {
                        Text("A")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AeroTokens.ColorRole.onAccent)
                    }
                    .accessibilityHidden(true)

                Text("Aeroshot setup")
                    .font(SettingsTheme.typeBody(weight: .semibold))

                Spacer()

                Text("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                    .font(SettingsTheme.typeMicro(weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: SettingsTheme.spacingXS) {
                ForEach(OnboardingStep.allCases) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? SettingsTheme.accent : SettingsTheme.fillPressed)
                        .frame(height: 4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count): \(step.title)")
        }
        .padding(.horizontal, SettingsTheme.spacingXL)
        .padding(.top, SettingsTheme.spacingL)
        .padding(.bottom, SettingsTheme.spacingM)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            OnboardingWelcomeStep()
        case .screenRecording:
            OnboardingPermissionStep(
                symbol: "rectangle.inset.filled.and.person.filled",
                title: "Screen Recording",
                subtitle: "Aeroshot needs this to capture windows, areas, and video.",
                path: "Privacy & Security  →  Screen & System Audio Recording  →  Aeroshot",
                granted: SettingsPermissions.screenRecordingGranted,
                action: { SettingsPermissions.requestScreenRecording() }
            )
            .id(permissionRefresh)
        case .accessibility:
            OnboardingPermissionStep(
                symbol: "accessibility",
                title: "Accessibility",
                subtitle: "This powers global shortcuts, click highlights, and scrolling auto-scroll.",
                path: "Privacy & Security  →  Accessibility  →  Aeroshot",
                granted: SettingsPermissions.accessibilityGranted,
                action: { SettingsPermissions.requestAccessibility() }
            )
            .id(permissionRefresh)
        case .ready:
            OnboardingReadyStep()
        }
    }

    private var footer: some View {
        HStack(spacing: SettingsTheme.spacingM) {
            if let previous = step.previous {
                Button("Back") {
                    goingForward = false
                    step = previous
                    SettingsTheme.performHaptic()
                }
                .buttonStyle(AeroButtonStyle(kind: .quiet, size: .regular))
            } else {
                Color.clear.frame(width: 72, height: 1)
            }

            Spacer()

            Text("Aeroshot 1.0")
                .font(SettingsTheme.typeMicro(design: .monospaced))
                .foregroundStyle(.tertiary)

            Spacer()

            Button(primaryTitle, action: advance)
                .buttonStyle(AeroButtonStyle(kind: .primary, size: .regular))
                .keyboardShortcut(.defaultAction)
                .frame(minWidth: 104, alignment: .trailing)
        }
        .padding(.horizontal, SettingsTheme.spacingXL)
        .padding(.vertical, SettingsTheme.spacingM)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Let’s go"
        case .screenRecording: "Continue"
        case .accessibility: "Finish"
        case .ready: "Start capturing"
        }
    }

    private var stepTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .offset(x: goingForward ? 28 : -28)),
            removal: .opacity.combined(with: .offset(x: goingForward ? -28 : 28))
        )
    }

    private func advance() {
        SettingsTheme.performHaptic()
        guard let next = step.next else {
            settings.hasCompletedOnboarding = true
            onComplete()
            return
        }
        goingForward = true
        step = next
    }
}

private struct OnboardingStepScaffold<Content: View>: View {
    let symbol: String?
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.spacingL) {
            HStack(spacing: SettingsTheme.spacingM) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(SettingsTheme.accent)
                        .frame(width: 42, height: 42)
                        .background(SettingsTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: SettingsTheme.spacingXS) {
                    Text(title)
                        .font(.title2.bold())
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content()
        }
        .frame(maxWidth: 440, alignment: .leading)
        .padding(.horizontal, SettingsTheme.spacingXL)
        .padding(.vertical, SettingsTheme.spacingL)
    }
}

private struct OnboardingWelcomeStep: View {
    var body: some View {
        OnboardingStepScaffold(
            symbol: nil,
            title: "Welcome to Aeroshot",
            subtitle: "Screenshots, recordings, and GIFs — all from one shortcut. Before you start, macOS needs your OK on two permissions. Takes about a minute."
        ) {
            HStack(spacing: SettingsTheme.spacingM) {
                capability(
                    symbol: "rectangle.inset.filled.and.person.filled",
                    title: "Screen Recording",
                    detail: "Lets Aeroshot see what’s on your screen"
                )
                capability(
                    symbol: "accessibility",
                    title: "Accessibility",
                    detail: "Makes shortcuts work from any app"
                )
            }
        }
    }

    private func capability(symbol: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
            Image(systemName: symbol)
                .font(.headline.weight(.semibold))
                .foregroundStyle(SettingsTheme.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(SettingsTheme.typeBody(weight: .semibold))
            Text(detail)
                .font(SettingsTheme.typeSmall())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 106, alignment: .topLeading)
        .padding(SettingsTheme.spacingM)
        .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous)
                .strokeBorder(SettingsTheme.borderSubtle, lineWidth: AeroTokens.Stroke.hairlineWidth)
        }
    }
}

private struct OnboardingPermissionStep: View {
    let symbol: String
    let title: String
    let subtitle: String
    let path: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        OnboardingStepScaffold(symbol: symbol, title: title, subtitle: subtitle) {
            VStack(alignment: .leading, spacing: SettingsTheme.spacingM) {
                HStack(spacing: SettingsTheme.spacingM) {
                    Image(systemName: granted ? "checkmark.circle.fill" : "gearshape")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(granted ? SettingsTheme.success : SettingsTheme.accent)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: SettingsTheme.spacingXS) {
                        Text("System Settings")
                            .font(SettingsTheme.typeBody(weight: .semibold))
                        Text(path)
                            .font(SettingsTheme.typeSmall(design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: SettingsTheme.spacingS)

                    Button(granted ? "Granted ✓" : "Open System Settings…", action: action)
                        .buttonStyle(AeroButtonStyle(kind: granted ? .secondary : .primary, size: .regular))
                        .disabled(granted)
                }
                .padding(SettingsTheme.spacingM)
                .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous)
                        .strokeBorder(SettingsTheme.borderSubtle, lineWidth: AeroTokens.Stroke.hairlineWidth)
                }

                Label(
                    granted ? "Access granted — you can continue." : "Enable Aeroshot, then return here. The status refreshes automatically.",
                    systemImage: granted ? "checkmark.circle.fill" : "arrow.uturn.backward.circle"
                )
                .font(SettingsTheme.typeSmall(weight: .medium))
                .foregroundStyle(granted ? SettingsTheme.success : Color.secondary)
            }
        }
    }
}

private struct OnboardingReadyStep: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        OnboardingStepScaffold(
            symbol: "checkmark",
            title: "You’re all set",
            subtitle: "Press the All-in-One shortcut anytime to capture. Everything else is waiting in Settings."
        ) {
            HStack(spacing: SettingsTheme.spacingM) {
                Image(systemName: "command")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(SettingsTheme.accent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: SettingsTheme.spacingXS) {
                    Text("All-in-One capture")
                        .font(SettingsTheme.typeBody(weight: .semibold))
                    Text((settings.hotkeys()[.allInOne] ?? HotkeyAction.allInOne.defaultHotkey).displayString)
                        .font(SettingsTheme.typeTitle(weight: .bold, design: .monospaced))
                        .foregroundStyle(SettingsTheme.accent)
                }
            }
            .padding(SettingsTheme.spacingL)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous)
                    .strokeBorder(SettingsTheme.borderSubtle, lineWidth: AeroTokens.Stroke.hairlineWidth)
            }
        }
    }
}
