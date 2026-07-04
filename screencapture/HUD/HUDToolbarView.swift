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

struct HUDToolbarView: View {
    @ObservedObject var model: HUDToolbarModel
    @State private var hoveredIntent: CaptureIntent? = nil

    private let group1: [CaptureIntent] = [.area, .window, .fullScreen, .scrolling]
    private let group2: [CaptureIntent] = [.recordArea, .recordScreen]
    private let group3: [CaptureIntent] = [.ocr]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(group1) { intent in
                intentButton(intent)
            }
            
            Divider()
                .frame(height: 24)
                .background(Color.primary.opacity(0.12))
                .padding(.horizontal, 2)
            
            ForEach(group2) { intent in
                intentButton(intent)
            }
            
            Divider()
                .frame(height: 24)
                .background(Color.primary.opacity(0.12))
                .padding(.horizontal, 2)
            
            ForEach(group3) { intent in
                intentButton(intent)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        )
        .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 6)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                NSCursor.arrow.set()
            case .ended:
                NSCursor.crosshair.set()
            }
        }
    }

    @ViewBuilder
    private func intentButton(_ intent: CaptureIntent) -> some View {
        let isSelected = model.selected == intent
        let isHovered = hoveredIntent == intent

        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                model.onSelect?(intent)
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 2) {
                    Image(systemName: intent.symbol)
                        .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.white : iconColor(for: intent))
                        .frame(height: 18)
                    Text(intent.title)
                        .font(.system(size: 9, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.85))
                }
                .frame(width: 58, height: 42)
                .background(
                    ZStack {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(color: Color.accentColor.opacity(0.35), radius: 4, x: 0, y: 2)
                        } else if isHovered {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.primary.opacity(0.08))
                        }
                    }
                )
                
                if let digit = digitString(for: intent) {
                    Text(digit)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.65) : Color.primary.opacity(0.35))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 0.5)
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(isSelected ? Color.white.opacity(0.15) : Color.primary.opacity(0.04))
                        )
                        .padding(3)
                }
            }
        }
        .buttonStyle(.plain)
        .help(intent.title)
        .onHover { over in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredIntent = over ? intent : nil
            }
        }
    }

    private func iconColor(for intent: CaptureIntent) -> Color {
        switch intent {
        case .area, .window, .fullScreen, .scrolling:
            return .blue
        case .recordArea, .recordScreen:
            return .red
        case .ocr:
            return .purple
        }
    }

    private func digitString(for intent: CaptureIntent) -> String? {
        switch intent {
        case .area: return "1"
        case .window: return "2"
        case .fullScreen: return "3"
        case .scrolling: return "4"
        case .recordArea: return "5"
        case .recordScreen: return "6"
        case .ocr: return "7"
        }
    }
}

