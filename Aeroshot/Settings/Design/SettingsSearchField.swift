import SwiftUI

struct SettingsSearchField: View {
    @Binding var query: String
    var focusBinding: FocusState<Bool>.Binding

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: SettingsTheme.spacingS) {
            Image(systemName: "magnifyingglass")
                .font(SettingsTheme.typeSmall(weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search settings…", text: $query)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .focused(focusBinding)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(SettingsTheme.typeSmall())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, SettingsTheme.spacingM)
        .padding(.vertical, SettingsTheme.spacingS)
        .background(isHovered ? SettingsTheme.fillHover : SettingsTheme.fillRest, in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                .strokeBorder(isHovered ? SettingsTheme.borderHover : SettingsTheme.borderSubtle, lineWidth: 0.5)
        }
        .onHover { hovering in
            SettingsTheme.animateHover(reducedMotion: reduceMotion) {
                isHovered = hovering
            }
        }
    }
}

struct SettingsSearchResultsList: View {
    let results: [SettingsSearchEntry]
    let onSelect: (SettingsSearchEntry) -> Void

    var body: some View {
        if results.isEmpty {
            VStack(spacing: SettingsTheme.spacingS) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("No settings found")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SettingsTheme.spacingXL)
        } else {
            ScrollView {
                VStack(spacing: SettingsTheme.spacingXS) {
                    ForEach(results) { entry in
                        SettingsSearchResultRow(entry: entry, onSelect: onSelect)
                    }
                }
            }
        }
    }
}

private struct SettingsSearchResultRow: View {
    let entry: SettingsSearchEntry
    let onSelect: (SettingsSearchEntry) -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            onSelect(entry)
        } label: {
            HStack(spacing: SettingsTheme.spacingS) {
                Image(systemName: entry.pane.symbol)
                    .font(.system(size: SettingsTheme.iconSizeSmall, weight: .semibold))
                    .foregroundStyle(SettingsTheme.accent)
                    .frame(width: SettingsTheme.iconColumnWidth)

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("\(entry.pane.title) · \(entry.detail)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.right")
                    .font(SettingsTheme.typeMicro(weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .offset(x: isHovered ? 2 : 0)
            }
            .padding(.horizontal, SettingsTheme.spacingM)
            .padding(.vertical, SettingsTheme.spacingS)
            .background(
                isHovered ? SettingsTheme.fillHover : SettingsTheme.fillRest,
                in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                    .strokeBorder(isHovered ? SettingsTheme.borderHover : SettingsTheme.borderSubtle, lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
        }
        .buttonStyle(AeroPressableStyle())
        .onHover { hovering in
            SettingsTheme.animateHover(reducedMotion: reduceMotion) {
                isHovered = hovering
            }
        }
    }
}
