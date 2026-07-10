import SwiftUI

struct SettingsHeroHeader: View {
    enum ChipTone {
        case neutral, accent, success, warning
    }

    struct Chip: Identifiable {
        let id: String
        let text: String
        let tone: ChipTone

        /// Chips are informational, not interactive — neutral by default so
        /// the accent keeps meaning "you can click/select this."
        init(_ text: String, tone: ChipTone = .neutral) {
            self.id = text
            self.text = text
            self.tone = tone
        }
    }

    let title: String
    let subtitle: String?
    let symbol: String?
    let chips: [Chip]

    init(_ title: String, symbol: String? = nil, subtitle: String? = nil, chips: [Chip] = []) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.chips = chips
    }

    init(_ title: String, symbol: String? = nil, subtitle: String? = nil, chips: [String]) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.chips = chips.map { Chip($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTheme.spacingS) {
            HStack(spacing: SettingsTheme.spacingM) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(SettingsTheme.typeTitle())
                        .foregroundStyle(SettingsTheme.accent)
                        .frame(width: SettingsTheme.iconBadgeSize, height: SettingsTheme.iconBadgeSize)
                        .background(
                            SettingsTheme.accent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                        )
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
            }

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !chips.isEmpty {
                HStack(spacing: SettingsTheme.spacingS) {
                    ForEach(chips) { chip in
                        Text(chip.text)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(foreground(for: chip.tone))
                            .padding(.horizontal, SettingsTheme.spacingS)
                            .padding(.vertical, SettingsTheme.spacingXS)
                            .background(background(for: chip.tone), in: Capsule())
                    }
                }
                .padding(.top, SettingsTheme.spacingXS)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, SettingsTheme.spacingS)
    }

    private func foreground(for tone: ChipTone) -> Color {
        switch tone {
        case .neutral: return .secondary
        case .accent: return SettingsTheme.accent
        case .success: return SettingsTheme.success
        case .warning: return SettingsTheme.warning
        }
    }

    private func background(for tone: ChipTone) -> Color {
        switch tone {
        case .neutral: return AeroTokens.Fill.hover
        case .accent, .success, .warning: return foreground(for: tone).opacity(0.12)
        }
    }
}
