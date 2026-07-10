import SwiftUI

struct SettingsPaneLayout<Content: View>: View {
    var pane: SettingsPane?
    @ViewBuilder let content: () -> Content

    @State private var scrollOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Once the hero title has scrolled past, the compact bar takes over as
    /// the pane's title so content never scrolls without context.
    private var showsPinnedTitle: Bool { scrollOffset > 56 }

    init(pane: SettingsPane? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.pane = pane
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsTheme.spacingL) {
                content()

                if let pane {
                    SettingsPanePager(current: pane)
                        .padding(.top, SettingsTheme.spacingS)
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, SettingsTheme.spacingXL)
            .padding(.vertical, SettingsTheme.spacingL)
            .background {
                SettingsScrollOffsetProbe { offset in
                    scrollOffset = offset
                }
            }
        }
        .overlay(alignment: .top) {
            if let pane, showsPinnedTitle {
                SettingsPinnedTitleBar(pane: pane)
                    .transition(pinnedBarTransition)
            }
        }
        .animation(
            reduceMotion ? nil : SettingsTheme.hoverAnimation,
            value: showsPinnedTitle
        )
        .scrollIndicators(.automatic)
    }

    private var pinnedBarTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -8))
    }
}

/// SwiftUI's GeometryReader/preference pattern never re-evaluates during
/// NSScrollView-backed scrolling on macOS, so the offset is read the AppKit
/// way: observe the enclosing clip view's bounds changes.
private struct SettingsScrollOffsetProbe: NSViewRepresentable {
    var onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.onChange = onChange
    }

    final class ProbeView: NSView {
        var onChange: ((CGFloat) -> Void)?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            if window == nil {
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                    self.observer = nil
                }
                return
            }

            guard observer == nil, let clipView = enclosingScrollView?.contentView else { return }
            clipView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let clip = self.enclosingScrollView?.contentView else { return }
                    self.onChange?(clip.documentVisibleRect.origin.y)
                }
            }
        }
    }
}

/// Compact material title bar pinned over the pane while the hero header is
/// scrolled out of view. Duplicates the hero visually, so it stays silent to
/// VoiceOver.
private struct SettingsPinnedTitleBar: View {
    let pane: SettingsPane

    var body: some View {
        HStack(spacing: SettingsTheme.spacingS) {
            Image(systemName: pane.symbol)
                .font(.system(size: SettingsTheme.iconSizeMedium, weight: .semibold))
                .foregroundStyle(SettingsTheme.accent)
            Text(pane.title)
                .font(SettingsTheme.typeTitle())
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SettingsTheme.spacingXL)
        .padding(.vertical, SettingsTheme.spacingM)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityHidden(true)
    }
}

/// Previous/next section navigation shown at the bottom of every pane.
struct SettingsPanePager: View {
    let current: SettingsPane
    @Environment(\.settingsNavigate) private var navigate

    private var previous: SettingsPane? {
        let all = SettingsPane.allCases
        guard let index = all.firstIndex(of: current), index > 0 else { return nil }
        return all[index - 1]
    }

    private var next: SettingsPane? {
        let all = SettingsPane.allCases
        guard let index = all.firstIndex(of: current), index < all.count - 1 else { return nil }
        return all[index + 1]
    }

    var body: some View {
        HStack(spacing: SettingsTheme.spacingM) {
            if let previous {
                pagerCard(previous, edge: .leading)
                    .frame(maxWidth: next != nil ? .infinity : nil, alignment: .leading)
            }
            if previous != nil && next != nil {
                Spacer(minLength: SettingsTheme.spacingM)
            }
            if let next {
                pagerCard(next, edge: .trailing)
                    .frame(maxWidth: previous != nil ? .infinity : nil, alignment: .trailing)
            }
        }
    }

    private func pagerCard(_ pane: SettingsPane, edge: HorizontalEdge) -> some View {
        SettingsPagerCard(pane: pane, edge: edge) {
            SettingsTheme.performHaptic()
            navigate(pane)
        }
    }
}

private struct SettingsPagerCard: View {
    let pane: SettingsPane
    let edge: HorizontalEdge
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: SettingsTheme.spacingS) {
                if edge == .leading {
                    chevron("chevron.left")
                }

                VStack(alignment: edge == .leading ? .leading : .trailing, spacing: 1) {
                    Text(edge == .leading ? "Previous" : "Next")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                    HStack(spacing: SettingsTheme.spacingXS + 1) {
                        if edge == .trailing {
                            Image(systemName: pane.symbol)
                                .font(.system(size: SettingsTheme.iconSizeSmall, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(pane.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if edge == .leading {
                            Image(systemName: pane.symbol)
                                .font(.system(size: SettingsTheme.iconSizeSmall, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if edge == .trailing {
                    chevron("chevron.right")
                }
            }
            .padding(.horizontal, SettingsTheme.spacingM)
            .padding(.vertical, SettingsTheme.spacingS + 2)
            .frame(minHeight: 52)
            .background {
                RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                    .fill(isHovered ? SettingsTheme.fillHover : SettingsTheme.fillRest)
            }
            .overlay {
                RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                    .strokeBorder(isHovered ? SettingsTheme.borderHover : SettingsTheme.borderSubtle, lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            SettingsTheme.animateHover(reducedMotion: reduceMotion) {
                isHovered = hovering
            }
        }
        .accessibilityLabel("\(edge == .leading ? "Previous" : "Next") section: \(pane.title)")
    }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: SettingsTheme.iconSizeSmall, weight: .semibold))
            .foregroundStyle(.tertiary)
            .offset(x: isHovered ? (edge == .leading ? -2 : 2) : 0)
    }
}

struct SettingsStatCard: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = SettingsTheme.accent

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
            Image(systemName: symbol)
                .font(.system(size: SettingsTheme.iconSizeLarge, weight: .semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(SettingsTheme.spacingM)
        .frame(maxWidth: .infinity, minHeight: SettingsTheme.statCardMinHeight, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous)
                .strokeBorder(isHovered ? SettingsTheme.borderHover : SettingsTheme.borderSubtle, lineWidth: 0.5)
        }
        .shadow(
            color: Color.black.opacity(AeroTokens.Elevation.card.opacity),
            radius: AeroTokens.Elevation.card.radius,
            x: AeroTokens.Elevation.card.x,
            y: AeroTokens.Elevation.card.y
        )
        .scaleEffect(isHovered && !reduceMotion ? 1.01 : 1)
        .onHover { hovering in
            SettingsTheme.animateHover(reducedMotion: reduceMotion) {
                isHovered = hovering
            }
        }
    }
}

struct SettingsJumpCard: View {
    let pane: SettingsPane
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: SettingsTheme.spacingM) {
                Image(systemName: pane.symbol)
                    .font(.system(size: SettingsTheme.iconSizeLarge, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: SettingsTheme.iconBadgeSize, height: SettingsTheme.iconBadgeSize)
                    .background(AeroTokens.Fill.hover, in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(pane.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(pane.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: SettingsTheme.iconSizeSmall, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .offset(x: isHovered ? 2 : 0)
            }
            .padding(SettingsTheme.spacingM)
            .background {
                RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous)
                    .fill(isHovered ? SettingsTheme.fillHover : SettingsTheme.fillRest)
            }
            .overlay {
                RoundedRectangle(cornerRadius: SettingsTheme.cardRadius, style: .continuous)
                    .strokeBorder(isHovered ? SettingsTheme.borderHover : SettingsTheme.borderSubtle, lineWidth: 0.5)
            }
            .scaleEffect(isHovered && !reduceMotion ? 1.01 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            SettingsTheme.animateHover(reducedMotion: reduceMotion) {
                isHovered = hovering
            }
        }
    }
}

struct SettingsQuickLink: View {
    let title: String
    let subtitle: String
    let pane: SettingsPane

    @Environment(\.settingsNavigate) private var navigate
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            SettingsTheme.performHaptic()
            navigate(pane)
        } label: {
            HStack(spacing: SettingsTheme.spacingM) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text(pane.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SettingsTheme.accent)
                    Image(systemName: "arrow.right")
                        .font(SettingsTheme.typeMicro(weight: .bold))
                        .foregroundStyle(SettingsTheme.accent)
                        .offset(x: isHovered ? 2 : 0)
                }
                .opacity(isHovered ? 1 : 0.7)
            }
            .padding(.vertical, SettingsTheme.spacingXS)
            .padding(.horizontal, SettingsTheme.spacingXS)
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: SettingsTheme.controlRadius - 2, style: .continuous)
                        .fill(SettingsTheme.fillHover)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            SettingsTheme.animateHover(reducedMotion: reduceMotion) {
                isHovered = hovering
            }
        }
    }
}
