import AppKit
import ImageIO
import SwiftUI

/// The capture tray is deliberately one view: the stack, searchable library,
/// and selected-item inspector share the same HistoryStore and action closures.
@MainActor
struct CaptureTrayView: View {
    @ObservedObject var appState: AppState
    @EnvironmentObject private var history: HistoryStore

    @State private var query = ""
    @State private var selectedKind: CaptureTrayKind = .all
    @State private var selectedID: UUID?
    @State private var stackHover = false
    @State private var hiddenStackIDs = Set<UUID>()
    @State private var toast: String?
    @State private var tagItem: HistoryItem?
    @State private var tagText = ""
    @State private var trashItem: HistoryItem?

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                trayHeader
                Divider().overlay(CaptureTrayPalette.border)
                HStack(spacing: 0) {
                    libraryColumn
                    Divider().overlay(CaptureTrayPalette.border)
                    detailColumn
                        .frame(width: 352)
                }
            }
            .background(CaptureTrayPalette.background)

            if let toast {
                Text(toast)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CaptureTrayPalette.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(CaptureTrayPalette.borderStrong))
                    .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(3)
            }
        }
        .overlay(alignment: .bottomLeading) {
            stackOverlay
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("capture.tray")
        .onAppear { ensureSelection() }
        .onChange(of: query) { _, _ in ensureSelection() }
        .onChange(of: selectedKind) { _, _ in ensureSelection() }
        .onChange(of: history.items) { _, _ in ensureSelection() }
        .onExitCommand {
            NSApp.keyWindow?.orderOut(nil)
        }
        .alert("Edit tags", isPresented: Binding(
            get: { tagItem != nil },
            set: { if !$0 { tagItem = nil } }
        )) {
            TextField("Comma-separated tags", text: $tagText)
            Button("Cancel", role: .cancel) { tagItem = nil }
            Button("Save") {
                if let tagItem {
                    history.setTags(tagText.split(separator: ",").map(String.init), for: tagItem)
                }
                tagItem = nil
            }
        } message: {
            Text("Tags are searchable across file names, OCR text, and this library.")
        }
        .alert("Capture Tray", isPresented: Binding(
            get: { history.lastError != nil },
            set: { if !$0 { history.dismissLastError() } }
        )) {
            Button("OK") { history.dismissLastError() }
        } message: {
            Text(history.lastError?.localizedDescription ?? "An unknown library error occurred.")
        }
        .confirmationDialog(
            "Move capture to Trash?",
            isPresented: Binding(
                get: { trashItem != nil },
                set: { if !$0 { trashItem = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let trashItem { moveToTrash(trashItem) }
                trashItem = nil
            }
            Button("Cancel", role: .cancel) { trashItem = nil }
        } message: {
            Text("The capture is removed from Aeroshot and its library file is moved to the macOS Trash.")
        }
    }

    private var filteredItems: [HistoryItem] {
        history.search(query, filter: HistoryFilter(kinds: selectedKind.kinds))
    }

    private var selectedItem: HistoryItem? {
        if let selectedID,
           let selected = filteredItems.first(where: { $0.id == selectedID }) {
            return selected
        }
        return filteredItems.first
    }

    private var stackItems: [HistoryItem] {
        Array(history.items.filter { !hiddenStackIDs.contains($0.id) }.prefix(3))
    }

    private var trayHeader: some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Library")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CaptureTrayPalette.text)
                Text("\(history.items.count) of 500 items · \(history.directory.path)")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(CaptureTrayPalette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: 182, alignment: .leading)

            Rectangle()
                .fill(CaptureTrayPalette.border)
                .frame(width: 1, height: 28)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CaptureTrayPalette.muted)
                TextField("Search file names, tags, and recognised text…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(CaptureTrayPalette.text)
                    .accessibilityLabel("Search library")
                    .accessibilityIdentifier("capture.tray.search")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(CaptureTrayPalette.muted)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .captureTrayInteractive(cornerRadius: 7)
                    .accessibilityLabel("Clear search")
                    .accessibilityIdentifier("capture.tray.search.clear")
                    .help("Clear search")
                }
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("\(filteredItems.count) match\(filteredItems.count == 1 ? "" : "es")")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(CaptureTrayPalette.muted)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(CaptureTrayPalette.surface2, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(CaptureTrayPalette.border))
            .frame(maxWidth: .infinity)

            HStack(spacing: 2) {
                ForEach(CaptureTrayKind.allCases) { kind in
                    Button {
                        selectedKind = kind
                    } label: {
                        Text(kind.label)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(selectedKind == kind ? CaptureTrayPalette.accent : CaptureTrayPalette.muted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .background(
                                selectedKind == kind ? CaptureTrayPalette.accent.opacity(0.14) : .clear,
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show \(kind.label)")
                }
            }
            .padding(3)
            .background(CaptureTrayPalette.surface2, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(CaptureTrayPalette.border))

            Button {
                NSApp.keyWindow?.orderOut(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CaptureTrayPalette.muted)
                    .frame(width: 30, height: 30)
                    .background(CaptureTrayPalette.surface2, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(CaptureTrayPalette.border))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .captureTrayInteractive(cornerRadius: 9)
            .accessibilityLabel("Close Capture Tray")
            .accessibilityIdentifier("capture.tray.close")
            .help("Close Capture Tray")
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
        .background(CaptureTrayPalette.surface.opacity(0.94))
    }

    private var libraryColumn: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                let grouped = groupedSessions(filteredItems)
                if grouped.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: query.isEmpty ? "tray" : "magnifyingglass")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(CaptureTrayPalette.muted)
                        Text(query.isEmpty ? "No captures yet" : "Nothing matches “\(query)”")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CaptureTrayPalette.secondary)
                        Text(query.isEmpty ? "Capture an image, recording, or OCR snippet to start your library." : "Search covers names, tags, and recognised text.")
                            .font(.system(size: 11))
                            .foregroundStyle(CaptureTrayPalette.muted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 300)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ForEach(grouped) { session in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Text(session.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(CaptureTrayPalette.text)
                                Text(session.meta)
                                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(CaptureTrayPalette.muted)
                                Rectangle()
                                    .fill(CaptureTrayPalette.border)
                                    .frame(height: 1)
                            }
                            .accessibilityElement(children: .combine)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 186, maximum: 220), spacing: 9)], spacing: 9) {
                                ForEach(session.items) { item in
                                    CaptureTrayCard(
                                        item: item,
                                        isSelected: selectedItem?.id == item.id,
                                        onSelect: { selectedID = item.id },
                                        onOpen: performOpen,
                                        onCopy: performCopy,
                                        onEdit: performEdit,
                                        onShare: performShare,
                                        onShareSafe: performShareSafe,
                                        onReveal: performReveal,
                                        onTrash: performTrash,
                                        onToggleFavorite: { history.toggleFavorite($0) },
                                        onEditTags: editTags
                                    )
                                    .environmentObject(history)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CaptureTrayPalette.background)
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let item = selectedItem {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    CaptureTrayPreview(item: item, height: 168, isDetail: true)
                        .environmentObject(history)

                    HStack(alignment: .top, spacing: 9) {
                        Text(displayName(for: item))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CaptureTrayPalette.text)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            history.toggleFavorite(item)
                        } label: {
                            Image(systemName: item.isFavorite ? "star.fill" : "star")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(item.isFavorite ? CaptureTrayPalette.accent : CaptureTrayPalette.muted)
                                .frame(width: 26, height: 26)
                                .background(CaptureTrayPalette.surface2, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(CaptureTrayPalette.border))
                        }
                        .buttonStyle(.plain)
                        .captureTrayInteractive(cornerRadius: 8)
                        .accessibilityLabel(item.isFavorite ? "Remove from Favorites" : "Add to Favorites")
                        .accessibilityValue(item.isFavorite ? "On" : "Off")
                        .accessibilityAddTraits(.isToggle)
                        .accessibilityIdentifier("capture.tray.favorite.\(item.id.uuidString)")
                        .help(item.isFavorite ? "Remove from Favorites" : "Add to Favorites")
                    }
                    Text(item.fileName.isEmpty ? item.projectURL?.lastPathComponent ?? "Untitled project" : item.fileName)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(CaptureTrayPalette.muted)
                        .textSelection(.enabled)
                        .lineLimit(2)

                    tagsView(item)
                    metadataView(item)

                    if let ocr = item.ocrText, !ocr.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Recognised text")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CaptureTrayPalette.text)
                            Text(ocr)
                                .font(.system(size: 11))
                                .foregroundStyle(CaptureTrayPalette.secondary)
                                .lineSpacing(2)
                                .textSelection(.enabled)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(CaptureTrayPalette.surface2, in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(CaptureTrayPalette.border))
                        }
                    }

                    if item.recoveryState == .recoverable && item.sourceState == .missing {
                        recoveryView(item)
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CaptureTrayPalette.background2)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                detailActions(item)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(CaptureTrayPalette.muted)
                Text("Pick a capture to inspect it")
                    .font(.system(size: 11.5))
                    .foregroundStyle(CaptureTrayPalette.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CaptureTrayPalette.background2)
        }
    }

    private func tagsView(_ item: HistoryItem) -> some View {
        HStack(spacing: 5) {
            ForEach(item.tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CaptureTrayPalette.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(CaptureTrayPalette.surface2, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(CaptureTrayPalette.border))
            }
            Button {
                editTags(item)
            } label: {
                Text("+ tag")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CaptureTrayPalette.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(CaptureTrayPalette.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }

    private func metadataView(_ item: HistoryItem) -> some View {
        VStack(spacing: 1) {
            metadataRow("KIND", value: item.kind.rawValue.capitalized)
            metadataRow("PIXELS", value: pixelDescription(item))
            metadataRow("CREATED", value: relativeDate(item.createdAt))
            metadataRow("LAST OPENED", value: item.lastOpenedAt.map(relativeDate) ?? "—")
            metadataRow("CHECKSUM", value: item.checksum ?? "Not available")
            metadataRow(
                "SOURCE",
                value: item.sourceState == .missing ? "missing" : item.recoveryState == .recovered ? "recovered" : "available",
                valueColor: item.sourceState == .missing ? CaptureTrayPalette.warning : CaptureTrayPalette.secondary
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(CaptureTrayPalette.border))
    }

    private func metadataRow(_ key: String, value: String, valueColor: Color = CaptureTrayPalette.secondary) -> some View {
        HStack(spacing: 10) {
            Text(key)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(CaptureTrayPalette.muted)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(valueColor)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CaptureTrayPalette.surface2)
    }

    private func recoveryView(_ item: HistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Artifact missing from the library folder", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CaptureTrayPalette.warning)
            Text("The index entry survived but the capture is unavailable. Open the autosaved project package to recover it.")
                .font(.system(size: 10.5))
                .foregroundStyle(CaptureTrayPalette.secondary)
            Button("Recover") {
                performRecovery(item)
            }
            .font(.system(size: 11, weight: .semibold))
            .buttonStyle(.bordered)
            .tint(CaptureTrayPalette.warning)
        }
        .padding(11)
        .background(CaptureTrayPalette.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(CaptureTrayPalette.warning.opacity(0.35)))
    }

    private func detailActions(_ item: HistoryItem) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button(canRecover(item) ? "Recover" : item.kind == .image || item.kind == .project || item.kind == .gif ? "Edit" : "Open") {
                    performOpen(item)
                }
                .buttonStyle(CaptureTrayAccentButtonStyle())
                .captureTrayInteractive(cornerRadius: 9)
                .disabled(!canOpen(item))

                Button("Copy") { performCopy(item) }
                    .buttonStyle(CaptureTrayQuietButtonStyle())
                    .captureTrayInteractive(cornerRadius: 9)
                    .disabled(actionURL(for: item) == nil && item.kind != .text)
            }
            HStack(spacing: 6) {
                Button("Reveal") { performReveal(item) }
                    .buttonStyle(CaptureTrayQuietButtonStyle())
                    .captureTrayInteractive(cornerRadius: 9)
                    .disabled(actionURL(for: item) == nil)
                Button("Share Safe") { performShareSafe(item) }
                    .buttonStyle(CaptureTrayQuietButtonStyle())
                    .captureTrayInteractive(cornerRadius: 9)
                    .disabled(item.kind != .image || history.primaryURL(for: item) == nil)
                Button(role: .destructive) {
                    performTrash(item)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CaptureTrayPalette.danger)
                        .frame(width: 40, height: 30)
                }
                .buttonStyle(.plain)
                .background(CaptureTrayPalette.surface2, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(CaptureTrayPalette.border))
                .captureTrayInteractive(cornerRadius: 9)
                .accessibilityLabel("Move to Trash")
                .accessibilityIdentifier("capture.tray.trash.\(item.id.uuidString)")
                .help("Move to Trash")
            }
        }
        .padding(12)
        .background(CaptureTrayPalette.background2)
        .overlay(alignment: .top) { Divider().overlay(CaptureTrayPalette.border) }
    }

    private var stackOverlay: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if stackHover && !stackItems.isEmpty {
                VStack(alignment: .trailing, spacing: 6) {
                    Text("TRACKPAD · TWO FINGERS")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(CaptureTrayPalette.muted)
                    HStack(spacing: 5) {
                        stackGesture("arrow.left", "Dismiss") { dismissTopStack() }
                        stackGesture("arrow.right", "Keep") { showToast("Kept in corner") }
                        stackGesture("arrow.up", "Tuck") { dismissTopStack() }
                        stackGesture("magnifyingglass", "Reveal") { revealTopStack() }
                    }
                }
                .padding(.bottom, 4)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            VStack(alignment: .trailing, spacing: 6) {
                if stackHover, let top = stackItems.first {
                    HStack(spacing: 4) {
                        stackAction("pencil.tip.crop.circle", "Edit") { performEdit(top) }
                        stackAction("doc.on.doc", "Copy") { performCopy(top) }
                        stackAction("magnifyingglass", "Reveal") { revealTopStack() }
                        stackAction("square.and.arrow.up", "Share") { performShare(top) }
                        stackAction("text.viewfinder", "Copy Text") { copyOCR(top) }
                        stackAction("pin", "Pin") { pin(top) }
                        stackAction("shield.checkered", "Share Safe") { performShareSafe(top) }
                    }
                    .padding(5)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(CaptureTrayPalette.borderStrong))
                }
                ZStack(alignment: .topLeading) {
                    ForEach(Array(stackItems.enumerated()).reversed(), id: \.element.id) { index, item in
                        CaptureTrayStackCard(item: item, isTop: index == 0) {
                            selectedID = item.id
                            showToast("Selected \(displayName(for: item))")
                        }
                        .environmentObject(history)
                        .offset(x: CGFloat(index) * 7, y: CGFloat(index) * 7)
                        .rotationEffect(.degrees(Double(index) * -1.1))
                    }
                }
                .frame(width: 200 + CGFloat(max(0, min(stackItems.count, 3) - 1)) * 7,
                       height: 132 + CGFloat(max(0, min(stackItems.count, 3) - 1)) * 7)
                .overlay(alignment: .topLeading) {
                    if stackItems.count > 1 {
                        Text("\(stackItems.count)")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(CaptureTrayPalette.background)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(CaptureTrayPalette.accent, in: Capsule())
                            .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
                            .offset(x: -9, y: -9)
                    }
                }
            }
        }
        .padding(.leading, 18)
        .padding(.bottom, 18)
        .onHover { over in
            withAnimation(.easeOut(duration: 0.16)) { stackHover = over }
        }
        .zIndex(2)
    }

    private func stackAction(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CaptureTrayPalette.secondary)
                .frame(width: 32, height: 32)
                .background(CaptureTrayPalette.surface2, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(CaptureTrayIconButtonStyle())
        .captureTrayInteractive(cornerRadius: 5)
        .accessibilityLabel(label)
        .accessibilityIdentifier("capture.tray.stack.\(label.lowercased().replacingOccurrences(of: " ", with: "-"))")
        .help(label)
    }

    private func stackGesture(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CaptureTrayPalette.secondary)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(CaptureTrayPalette.surface2, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(CaptureTrayPalette.border))
        }
        .buttonStyle(.plain)
        .captureTrayInteractive(cornerRadius: 8)
        .accessibilityLabel(label)
        .accessibilityIdentifier("capture.tray.stack.gesture.\(label.lowercased())")
    }

    private func groupedSessions(_ items: [HistoryItem]) -> [CaptureTraySession] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: $0.createdAt) }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        return grouped.keys.sorted(by: >).map { day in
            let sessionItems = grouped[day, default: []].sorted { $0.createdAt > $1.createdAt }
            let title: String
            if calendar.isDateInToday(day) { title = "This session" }
            else if calendar.isDateInYesterday(day) { title = "Yesterday" }
            else { title = dateFormatter.string(from: day) }
            let dates = sessionItems.map(\.createdAt).sorted()
            let meta = dates.count == 1 ? "1 capture" : "\(dates.count) captures"
            return CaptureTraySession(id: day, title: title, meta: meta, items: sessionItems)
        }
    }

    private func ensureSelection() {
        if let selectedID, filteredItems.contains(where: { $0.id == selectedID }) { return }
        selectedID = filteredItems.first?.id
    }

    private func displayName(for item: HistoryItem) -> String {
        if !item.fileName.isEmpty {
            return URL(fileURLWithPath: item.fileName).deletingPathExtension().lastPathComponent
        }
        return item.projectURL?.deletingPathExtension().lastPathComponent ?? item.kind.rawValue.capitalized
    }

    private func pixelDescription(_ item: HistoryItem) -> String {
        if item.kind == .text { return "\(item.pixelWidth) line\(item.pixelWidth == 1 ? "" : "s")" }
        if item.pixelWidth > 0 || item.pixelHeight > 0 { return "\(item.pixelWidth) × \(item.pixelHeight)" }
        if let duration = item.durationSeconds { return durationDescription(duration) }
        return "—"
    }

    private func durationDescription(_ duration: Double) -> String {
        let seconds = max(0, Int(duration.rounded()))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func showToast(_ message: String) {
        withAnimation(.easeOut(duration: 0.16)) { toast = message }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            if toast == message {
                withAnimation(.easeIn(duration: 0.18)) { toast = nil }
            }
        }
    }

    private func editTags(_ item: HistoryItem) {
        tagText = item.tags.joined(separator: ", ")
        tagItem = item
    }

    private func performOpen(_ item: HistoryItem) {
        if canRecover(item), actionURL(for: item) == nil {
            performRecovery(item)
            return
        }
        guard let url = actionURL(for: item) else {
            showToast("Source is missing")
            return
        }
        history.markOpened(item)
        do {
            switch item.kind {
            case .image:
                guard let image = loadImage(item) else {
                    if item.recoveryState == .recoverable {
                        performRecovery(item)
                    } else {
                        showToast("Image source is missing")
                    }
                    return
                }
                appState.openEditor(with: image, sourceScale: CGFloat(item.sourceScale ?? 1))
            case .project:
                try ProjectWindowRouter.openProject(at: url, appState: appState)
            case .gif:
                try ProjectWindowRouter.openGIF(at: url)
            case .text, .recording:
                NSWorkspace.shared.open(url)
            }
            showToast("Opened \(displayName(for: item))")
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t Open \(displayName(for: item))"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func performEdit(_ item: HistoryItem) {
        guard item.kind == .image else {
            performOpen(item)
            return
        }
        guard let image = loadImage(item) else {
            showToast("Image source is missing")
            return
        }
        history.markOpened(item)
        appState.openEditor(with: image, sourceScale: CGFloat(item.sourceScale ?? 1))
    }

    private func performCopy(_ item: HistoryItem) {
        switch item.kind {
        case .image:
            performProtectedImageAction(item) { image, fileURL in
                _ = PasteboardWriter.copy(
                    image: image,
                    fileURL: fileURL,
                    sourceScale: CGFloat(item.sourceScale ?? 1)
                )
                showToast("Copied to clipboard")
            }
            return
        case .text:
            guard let text = item.ocrText ?? loadText(item) else { showToast("No text available"); return }
            PasteboardWriter.copy(text: text)
        case .recording, .gif, .project:
            guard let url = history.primaryURL(for: item) else { showToast("Source is missing"); return }
            PasteboardWriter.copy(fileURL: url)
        }
        showToast("Copied to clipboard")
    }

    private func performShare(_ item: HistoryItem) {
        switch item.kind {
        case .image:
            performProtectedImageAction(item) { image, fileURL in
                ShareService.shareImage(image, fileURL: fileURL, from: nil)
            }
            return
        case .text:
            ShareService.shareText(item.ocrText ?? loadText(item) ?? "", from: nil)
        case .recording, .gif, .project:
            guard let url = history.primaryURL(for: item) else { showToast("Source is missing"); return }
            ShareService.shareFile(at: url, from: nil)
        }
    }

    private func performProtectedImageAction(
        _ item: HistoryItem,
        action: @escaping @MainActor (CGImage, URL?) -> Void
    ) {
        guard let image = loadImage(item) else { showToast("Image source is missing"); return }
        Task { @MainActor in
            do {
                let result = try await appState.prepareCaptureOutput(image)
                action(result.image, result.matchCount == 0 ? history.fileURL(for: item) : nil)
            } catch {
                showToast("Sensitive-data scan failed. Nothing was copied or shared.")
            }
        }
    }

    private func performShareSafe(_ item: HistoryItem) {
        guard item.kind == .image, let image = loadImage(item) else {
            showToast("ShareSafe only scans images")
            return
        }
        Task { @MainActor in
            await ShareSafeService.shareSafe(
                image: image,
                fileURL: history.fileURL(for: item),
                from: nil,
                style: appState.settings.shareSafeRedactionStyle,
                useSmartScan: appState.settings.shareSafeSmartScan,
                usePrivacyFilter: appState.settings.shareSafePrivacyFilter,
                redactBeforeSharing: appState.settings.shareSafeRedactBeforeSharing
            )
        }
        showToast("Re-running ShareSafe")
    }

    private func performReveal(_ item: HistoryItem) {
        guard let url = actionURL(for: item) else { showToast("Source is missing"); return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func performRecovery(_ item: HistoryItem) {
        guard let projectURL = item.projectURL, FileManager.default.fileExists(atPath: projectURL.path) else {
            showToast("Recovery project is missing")
            return
        }
        do {
            try ProjectWindowRouter.openProject(at: projectURL, appState: appState)
            showToast("Opened recovery project")
        } catch {
            showToast(error.localizedDescription)
        }
    }

    private func performTrash(_ item: HistoryItem) {
        trashItem = item
    }

    private func moveToTrash(_ item: HistoryItem) {
        guard history.remove(item) else { return }
        hiddenStackIDs.remove(item.id)
        if selectedID == item.id { selectedID = nil }
        showToast("Moved to Trash")
    }

    private func copyOCR(_ item: HistoryItem) {
        guard let text = item.ocrText ?? loadText(item) else { showToast("No recognised text"); return }
        PasteboardWriter.copy(text: text)
        showToast("Recognised text copied")
    }

    private func pin(_ item: HistoryItem) {
        guard item.kind == .image, let image = loadImage(item) else { return }
        appState.pinController.pin(image: image, sourceScale: CGFloat(item.sourceScale ?? 1))
        showToast("Pinned in corner")
    }

    private func revealTopStack() {
        guard let item = stackItems.first else { return }
        if canRecover(item), actionURL(for: item) == nil {
            performRecovery(item)
            return
        }
        guard let url = actionURL(for: item) else {
            showToast("Source is missing")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        showToast("Revealed in Finder")
    }

    private func dismissTopStack() {
        guard let item = stackItems.first else { return }
        hiddenStackIDs.insert(item.id)
        showToast("Tucked away · still in Library")
    }

    private func loadText(_ item: HistoryItem) -> String? {
        try? String(contentsOf: history.fileURL(for: item), encoding: .utf8)
    }

    private func loadImage(_ item: HistoryItem) -> CGImage? {
        guard let url = item.kind == .image ? history.fileURL(for: item) : history.primaryURL(for: item),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func actionURL(for item: HistoryItem) -> URL? {
        if item.kind == .image || item.kind == .text {
            let url = history.fileURL(for: item)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        return history.primaryURL(for: item)
    }

    private func canRecover(_ item: HistoryItem) -> Bool {
        item.recoveryState == .recoverable && actionURL(for: item) == nil
    }

    private func canOpen(_ item: HistoryItem) -> Bool {
        actionURL(for: item) != nil || canRecover(item)
    }
}

private struct CaptureTraySession: Identifiable {
    let id: Date
    let title: String
    let meta: String
    let items: [HistoryItem]
}

private enum CaptureTrayKind: String, CaseIterable, Identifiable {
    case all, image, text, recording, gif, project

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .image: "Image"
        case .text: "Text"
        case .recording: "Video"
        case .gif: "GIF"
        case .project: "Project"
        }
    }

    var kinds: Set<HistoryCaptureKind> {
        switch self {
        case .all: []
        case .image: [.image]
        case .text: [.text]
        case .recording: [.recording]
        case .gif: [.gif]
        case .project: [.project]
        }
    }
}

@MainActor
private struct CaptureTrayCard: View {
    let item: HistoryItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: (HistoryItem) -> Void
    let onCopy: (HistoryItem) -> Void
    let onEdit: (HistoryItem) -> Void
    let onShare: (HistoryItem) -> Void
    let onShareSafe: (HistoryItem) -> Void
    let onReveal: (HistoryItem) -> Void
    let onTrash: (HistoryItem) -> Void
    let onToggleFavorite: (HistoryItem) -> Void
    let onEditTags: (HistoryItem) -> Void
    @EnvironmentObject private var history: HistoryStore

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    CaptureTrayPreview(item: item, height: 104)
                        .environmentObject(history)
                    Text(item.kind.shortLabel)
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(CaptureTrayPalette.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(CaptureTrayPalette.overlay, in: RoundedRectangle(cornerRadius: 5))
                        .padding(6)
                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(CaptureTrayPalette.accent)
                            .frame(width: 20, height: 20)
                            .background(CaptureTrayPalette.overlay, in: Circle())
                            .padding(5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                    if item.sourceState == .missing {
                        Text("SOURCE MISSING")
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(CaptureTrayPalette.warning)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(CaptureTrayPalette.overlay.opacity(0.76))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(cardTitle)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(CaptureTrayPalette.text)
                        .lineLimit(1)
                    Text(cardMeta)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(CaptureTrayPalette.muted)
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
            }
            .background(isSelected ? CaptureTrayPalette.accent.opacity(0.12) : CaptureTrayPalette.surface2, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(isSelected ? CaptureTrayPalette.accent.opacity(0.62) : CaptureTrayPalette.border))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 11))
        .captureTrayPressable()
        .captureTrayInteractive(cornerRadius: 11)
        .accessibilityLabel(cardTitle)
        .accessibilityValue(item.sourceState == .missing ? "Source missing" : "Available")
        .accessibilityHint("Select to inspect. More actions are available in the context menu.")
        .accessibilityIdentifier("capture.tray.card.\(item.id.uuidString)")
        .contextMenu {
            Button(item.isFavorite ? "Remove from Favorites" : "Add to Favorites") { onToggleFavorite(item) }
            Menu("Tags") {
                ForEach(["Work", "Personal", "Reference"], id: \.self) { tag in
                    Button(item.tags.contains(tag) ? "Remove \(tag)" : "Add \(tag)") {
                        var tags = item.tags
                        if let index = tags.firstIndex(of: tag) { tags.remove(at: index) } else { tags.append(tag) }
                        history.setTags(tags, for: item)
                    }
                }
                Divider()
                Button("Edit Tags…") { onEditTags(item) }
            }
            Divider()
            Button(item.recoveryState == .recoverable && actionURL == nil ? "Recover" : "Open") { onOpen(item) }
                .disabled(actionURL == nil && item.recoveryState != .recoverable)
            Button("Copy") { onCopy(item) }
            Button("Edit") { onEdit(item) }.disabled(item.kind != .image)
            Button("Share…") { onShare(item) }
            Button("Share Safe…") { onShareSafe(item) }.disabled(item.kind != .image)
            Button("Reveal") { onReveal(item) }.disabled(actionURL == nil)
            Divider()
            Button("Delete", role: .destructive) { onTrash(item) }
        }
    }

    private var cardTitle: String {
        let source = item.fileName.isEmpty ? item.projectURL?.lastPathComponent ?? "Untitled" : item.fileName
        return URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent
    }

    private var cardMeta: String {
        switch item.kind {
        case .text: return "\(item.pixelWidth) line\(item.pixelWidth == 1 ? "" : "s") · \(shortDate(item.createdAt))"
        case .recording, .gif:
            let duration = item.durationSeconds.map { formatDuration($0) }
            return [duration, shortDate(item.createdAt)].compactMap { $0 }.joined(separator: " · ")
        case .image, .project:
            return "\(item.pixelWidth) × \(item.pixelHeight) · \(shortDate(item.createdAt))"
        }
    }

    private var actionURL: URL? {
        if item.kind == .image || item.kind == .text {
            let url = history.fileURL(for: item)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        return history.primaryURL(for: item)
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: Double) -> String {
        let seconds = max(0, Int(duration.rounded()))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

@MainActor
private struct CaptureTrayStackCard: View {
    let item: HistoryItem
    let isTop: Bool
    let action: () -> Void
    @EnvironmentObject private var history: HistoryStore

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                CaptureTrayPreview(item: item, height: 132)
                    .environmentObject(history)
                if isTop {
                    HStack(spacing: 6) {
                        Text(item.kind.shortLabel)
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(CaptureTrayPalette.accent)
                        Text(stackTitle)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(CaptureTrayPalette.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(item.pixelWidth) × \(item.pixelHeight)")
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(CaptureTrayPalette.muted)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(LinearGradient(colors: [.clear, CaptureTrayPalette.overlay], startPoint: .top, endPoint: .bottom))
                }
            }
            .frame(width: 200, height: 132)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isTop ? CaptureTrayPalette.borderStrong : CaptureTrayPalette.border))
            .shadow(color: .black.opacity(0.45), radius: isTop ? 17 : 10, y: isTop ? 8 : 5)
        }
        .buttonStyle(.plain)
        .captureTrayPressable()
        .captureTrayInteractive(cornerRadius: 10)
        .accessibilityLabel("Select \(stackTitle)")
        .accessibilityValue(item.sourceState == .missing ? "Source missing" : "Available")
        .accessibilityIdentifier("capture.tray.stack.card.\(item.id.uuidString)")
    }

    private var stackTitle: String {
        let source = item.fileName.isEmpty ? item.projectURL?.lastPathComponent ?? "Capture" : item.fileName
        return URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent
    }
}

@MainActor
private struct CaptureTrayPreview: View {
    let item: HistoryItem
    let height: CGFloat
    var isDetail = false
    @EnvironmentObject private var history: HistoryStore

    var body: some View {
        ZStack {
            switch item.kind {
            case .image:
                CaptureTrayAsyncThumbnail(url: history.fileURL(for: item))
            case .text:
                textPreview
            case .recording:
                mediaPreview(symbol: "film", colors: [.red.opacity(0.34), .orange.opacity(0.2)])
            case .gif:
                mediaPreview(symbol: "photo.stack", colors: [.purple.opacity(0.34), .blue.opacity(0.2)])
            case .project:
                mediaPreview(symbol: item.sourceState == .missing ? "exclamationmark.triangle" : "shippingbox", colors: [.green.opacity(0.3), .blue.opacity(0.2)])
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(CaptureTrayPalette.surface3)
        .clipShape(RoundedRectangle(cornerRadius: isDetail ? 11 : 0))
    }

    private var textPreview: some View {
        ZStack {
            LinearGradient(colors: [CaptureTrayPalette.textPreviewTop, CaptureTrayPalette.textPreviewBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: max(4, height / 22)) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(Color.white.opacity(index == 0 ? 0.24 : 0.14))
                        .frame(width: CGFloat([0.76, 0.92, 0.64, 0.84][index]) * (isDetail ? 240 : 150), height: isDetail ? 6 : 5)
                }
            }
            .padding(isDetail ? 18 : 10)
        }
    }

    private func mediaPreview(symbol: String, colors: [Color]) -> some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: symbol)
                .font(.system(size: isDetail ? 38 : 27, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))
        }
    }
}

private struct CaptureTrayAsyncThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [CaptureTrayPalette.accent.opacity(0.3), Color.blue.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .task(id: url) {
            image = await Self.load(url: url)
        }
    }

    private static func load(url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 720,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }.value
    }
}

private struct CaptureTrayIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct CaptureTrayPressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct CaptureTrayInteractiveModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($isFocused)
            .onHover { isHovered = $0 }
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered ? CaptureTrayPalette.surface3.opacity(0.8) : .clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isFocused ? CaptureTrayPalette.accent : isHovered ? CaptureTrayPalette.borderStrong : .clear,
                        lineWidth: isFocused ? 1.25 : 0.75
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: isFocused)
            .transaction { transaction in
                if reduceMotion { transaction.animation = nil }
            }
    }
}

private extension View {
    func captureTrayInteractive(cornerRadius: CGFloat) -> some View {
        modifier(CaptureTrayInteractiveModifier(cornerRadius: cornerRadius))
    }

    func captureTrayPressable() -> some View {
        buttonStyle(CaptureTrayPressableStyle())
    }
}

private struct CaptureTrayAccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(CaptureTrayPalette.background)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(CaptureTrayPalette.accent.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: 9))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct CaptureTrayQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(CaptureTrayPalette.secondary.opacity(configuration.isPressed ? 0.7 : 1))
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(CaptureTrayPalette.surface2, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(CaptureTrayPalette.border))
    }
}

private enum CaptureTrayPalette {
    static let background = Color(nsColor: NSColor(calibratedWhite: 0.055, alpha: 1))
    static let background2 = Color(nsColor: NSColor(calibratedWhite: 0.045, alpha: 1))
    static let surface = Color(nsColor: NSColor(calibratedWhite: 0.075, alpha: 1))
    static let surface2 = Color(nsColor: NSColor(calibratedWhite: 0.10, alpha: 1))
    static let surface3 = Color(nsColor: NSColor(calibratedWhite: 0.065, alpha: 1))
    static let text = Color(nsColor: NSColor(calibratedWhite: 0.93, alpha: 1))
    static let secondary = Color(nsColor: NSColor(calibratedWhite: 0.65, alpha: 1))
    static let muted = Color(nsColor: NSColor(calibratedWhite: 0.40, alpha: 1))
    static let border = Color.white.opacity(0.075)
    static let borderStrong = Color.white.opacity(0.15)
    static let accent = Color(red: 1, green: 0.541, blue: 0.42)
    static let warning = Color(red: 1, green: 0.706, blue: 0.33)
    static let danger = Color(red: 0.90, green: 0.28, blue: 0.30)
    static let overlay = Color.black.opacity(0.76)
    static let textPreviewTop = Color(nsColor: NSColor(calibratedWhite: 0.22, alpha: 1))
    static let textPreviewBottom = Color(nsColor: NSColor(calibratedWhite: 0.13, alpha: 1))
}

private extension HistoryCaptureKind {
    var shortLabel: String {
        switch self {
        case .image: "IMG"
        case .text: "TXT"
        case .recording: "REC"
        case .gif: "GIF"
        case .project: "AERO"
        }
    }
}
