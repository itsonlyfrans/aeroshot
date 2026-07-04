import AppKit

@objc(ScreenCaptureScripting)
final class ScreenCaptureScripting: NSObject {
    @objc func captureArea(_ command: NSScriptCommand) -> Any? {
        MainActor.assumeIsolated {
            AppStateAccessor.shared?.captureController.beginAreaCapture()
        }
        return nil
    }

    @objc func captureWindow(_ command: NSScriptCommand) -> Any? {
        MainActor.assumeIsolated {
            AppStateAccessor.shared?.captureController.beginWindowCapture()
        }
        return nil
    }

    @objc func captureScreen(_ command: NSScriptCommand) -> Any? {
        MainActor.assumeIsolated {
            AppStateAccessor.shared?.captureController.captureFullScreen()
        }
        return nil
    }

    @objc func captureLastRegion(_ command: NSScriptCommand) -> Any? {
        MainActor.assumeIsolated {
            AppStateAccessor.shared?.captureController.captureLastRegion()
        }
        return nil
    }

    @objc func openAllInOne(_ command: NSScriptCommand) -> Any? {
        MainActor.assumeIsolated {
            AppStateAccessor.shared?.allInOneController.begin()
        }
        return nil
    }

    @objc func openHistory(_ command: NSScriptCommand) -> Any? {
        MainActor.assumeIsolated {
            AppStateAccessor.shared?.showHistoryWindow()
        }
        return nil
    }
}
