import AppKit

/// Area-select → OCR → clipboard. OCR history depends on the user setting.
@MainActor
final class OCRCaptureController {
    private unowned let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func begin() {
        Task {
            guard let sel = await appState.captureController.selectArea(mode: .area) else { return }
            await process(cocoaRect: sel.rect, display: sel.display)
        }
    }

    func process(cocoaRect: CGRect, display: DisplayInfo) async {
        let local = GeometryConversions.cocoaGlobalToDisplayLocalTopLeft(cocoaRect, screen: display.nsScreen)
        guard let image = try? await ScreenCaptureService.captureArea(local, on: display) else { return }
        let text = (try? await OCRService.recognizeText(in: image)) ?? ""
        if text.isEmpty {
            ToastController.shared.show("No text found", symbol: "text.viewfinder")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        appState.settings.playSelectedSound()
        if appState.settings.addOCRCapturesToHistory {
            appState.history.add(textCapture: text)
        }
    }
}
