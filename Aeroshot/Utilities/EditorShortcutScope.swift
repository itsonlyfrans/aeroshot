import AppKit

@MainActor
enum EditorShortcutScope {
    static var allowsDocumentShortcuts: Bool {
        allowsDocumentShortcuts(firstResponder: NSApp.keyWindow?.firstResponder)
    }

    static func allowsDocumentShortcuts(firstResponder: NSResponder?) -> Bool {
        !(firstResponder is NSTextView)
    }
}
