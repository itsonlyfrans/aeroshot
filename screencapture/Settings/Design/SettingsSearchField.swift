import SwiftUI

struct SettingsSearchField: View {
    @Binding var query: String
    var focusBinding: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: SettingsTheme.spacingS) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
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
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, SettingsTheme.spacingM)
        .padding(.vertical, SettingsTheme.spacingS)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
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
                        Button {
                            onSelect(entry)
                        } label: {
                            HStack(spacing: SettingsTheme.spacingS) {
                                Image(systemName: entry.pane.symbol)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 18)

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
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, SettingsTheme.spacingM)
                            .padding(.vertical, SettingsTheme.spacingS)
                            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: SettingsTheme.controlRadius, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
