import Combine
import SwiftUI

@MainActor
final class HUDToolbarModel: ObservableObject {
    @Published var selected: CaptureIntent
    var onSelect: ((CaptureIntent) -> Void)?
    var onCancel: (() -> Void)?

    init(selected: CaptureIntent) {
        self.selected = selected
    }
}

/// The capture HUD is deliberately a single command surface: capture modes
/// lead, while recording and text utilities remain reachable without competing
/// with the active selection mode.
struct HUDToolbarView: View {
    @ObservedObject var model: HUDToolbarModel
    @State private var hoveredIntent: CaptureIntent?

    private let captureIntents: [CaptureIntent] = [.area, .window, .fullScreen, .scrolling]
    private var isRecordingSelected: Bool { model.selected == .recordArea || model.selected == .recordScreen }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(captureIntents) { intent in
                intentButton(intent)
            }

            Divider().frame(height: 30).padding(.horizontal, 3)

            recordingMenu
            intentButton(.ocr)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(AeroTheme.strokeHairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 6)
    }

    private var recordingMenu: some View {
        Menu {
            Button { model.onSelect?(.recordArea) } label: {
                Label("Record Area", systemImage: CaptureIntent.recordArea.symbol)
            }
            Button { model.onSelect?(.recordScreen) } label: {
                Label("Record Screen", systemImage: CaptureIntent.recordScreen.symbol)
            }
        } label: {
            commandLabel(
                title: "Record",
                symbol: "record.circle",
                selected: isRecordingSelected,
                hovered: hoveredIntent == .recordArea || hoveredIntent == .recordScreen,
                tint: nil
            )
        }
        .menuStyle(.button)
        .buttonStyle(HUDCommandButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Recording options")
        .accessibilityLabel("Recording options")
        .onHover { hovering in
            hoveredIntent = hovering ? .recordArea : nil
        }
    }

    private func intentButton(_ intent: CaptureIntent) -> some View {
        let isSelected = model.selected == intent
        let isHovered = hoveredIntent == intent
        return Button {
            model.onSelect?(intent)
        } label: {
            commandLabel(
                title: intent.title,
                symbol: intent.symbol,
                selected: isSelected && !intent.isInstant,
                hovered: isHovered,
                tint: intent.isInstant ? AeroTheme.accent : nil,
                isInstant: intent.isInstant
            )
        }
        .buttonStyle(HUDCommandButtonStyle())
        .help("\(intent.title)\(intent.digitKey == nil ? "" : " (\(digitLabel(for: intent)))")")
        .accessibilityLabel(intent.title)
        .accessibilityAddTraits(isSelected && !intent.isInstant ? .isSelected : [])
        .onHover { hovering in
            hoveredIntent = hovering ? intent : nil
        }
    }

    private func commandLabel(
        title: String,
        symbol: String,
        selected: Bool,
        hovered: Bool,
        tint: Color?,
        isInstant: Bool = false
    ) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: selected ? .semibold : .medium))
            Text(title)
                .font(.system(size: 10, weight: selected ? .semibold : .medium))
                .lineLimit(1)
        }
        .foregroundStyle(selected ? AeroTheme.accent : (hovered ? (tint ?? Color.primary) : Color.secondary))
        .padding(.horizontal, 6)
        .frame(minWidth: 52, minHeight: 46)
        .background {
            if isInstant {
                RoundedRectangle(cornerRadius: AeroTheme.controlRadiusS, style: .continuous)
                    .fill(AeroTheme.accent.opacity(hovered ? 0.14 : 0.07))
            }
        }
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(Color.accentColor)
                .frame(width: selected ? 18 : 0, height: 2)
        }
        .contentShape(Rectangle())
    }

    private func digitLabel(for intent: CaptureIntent) -> String {
        guard let keyCode = intent.digitKey,
              let index = CaptureIntent.allCases.firstIndex(where: { $0.digitKey == keyCode })
        else { return "" }
        return String(index + 1)
    }
}

private struct HUDCommandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? AeroTheme.pressOpacity : 1)
            .scaleEffect(configuration.isPressed ? AeroTheme.pressScale : 1)
    }
}
