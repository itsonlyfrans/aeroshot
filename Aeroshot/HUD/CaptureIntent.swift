import Foundation

/// User-facing capture mode in the All-in-One HUD.
enum CaptureIntent: CaseIterable, Identifiable {
    case area, window, fullScreen, scrolling, recordArea, recordScreen, ocr

    var id: Self { self }

    var title: String {
        switch self {
        case .area: return "Area"
        case .window: return "Window"
        case .fullScreen: return "Screen"
        case .scrolling: return "Scroll"
        case .recordArea: return "Record Area"
        case .recordScreen: return "Record Screen"
        case .ocr: return "Text"
        }
    }

    var symbol: String {
        switch self {
        case .area: return "rectangle.dashed"
        case .window: return "macwindow"
        case .fullScreen: return "display"
        case .scrolling: return "arrow.up.and.down"
        case .recordArea: return "record.circle"
        case .recordScreen: return "display"
        case .ocr: return "text.viewfinder"
        }
    }

    /// Drag-based intents map to a selection overlay mode; instantaneous intents return nil.
    var selectionMode: SelectionMode? {
        switch self {
        case .area, .recordArea, .ocr: return .area
        case .window: return .window
        case .scrolling: return .scrolling
        case .fullScreen, .recordScreen: return nil
        }
    }

    var isInstant: Bool { selectionMode == nil }

    var hotkeyAction: HotkeyAction? {
        switch self {
        case .area: return .captureArea
        case .window: return .captureWindow
        case .fullScreen: return .captureScreen
        case .scrolling: return .captureScrolling
        case .recordArea: return .recordArea
        case .recordScreen: return .recordScreen
        case .ocr: return .captureOCR
        }
    }

    var storageKey: String {
        switch self {
        case .area: return "area"
        case .window: return "window"
        case .fullScreen: return "fullScreen"
        case .scrolling: return "scrolling"
        case .recordArea: return "recordArea"
        case .recordScreen: return "recordScreen"
        case .ocr: return "ocr"
        }
    }

    static func from(storageKey: String) -> CaptureIntent? {
        allCases.first { $0.storageKey == storageKey }
    }

    /// Keyboard shortcut index (1–7) while the HUD is active.
    var digitKey: UInt16? {
        switch self {
        case .area: return 18      // 1
        case .window: return 19   // 2
        case .fullScreen: return 20 // 3
        case .scrolling: return 21  // 4
        case .recordArea: return 23 // 5
        case .recordScreen: return 22 // 6
        case .ocr: return 26       // 7
        }
    }

    static func forDigit(_ keyCode: UInt16) -> CaptureIntent? {
        allCases.first { $0.digitKey == keyCode }
    }
}
