import SwiftUI

struct SettingsHeroHeader: View {
    enum ChipTone {
        case accent, success, warning
    }

    struct Chip: Identifiable {
        let id: String
        let text: String
        let tone: ChipTone

        init(_ text: String, tone: ChipTone = .accent) {
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
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SettingsTheme.accent)
                        .frame(width: 38, height: 38)
                        .background(
                            SettingsTheme.accent.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
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
        case .accent: return SettingsTheme.accent
        case .success: return SettingsTheme.success
        case .warning: return SettingsTheme.warning
        }
    }

    private func background(for tone: ChipTone) -> Color {
        foreground(for: tone).opacity(0.12)
    }
}
