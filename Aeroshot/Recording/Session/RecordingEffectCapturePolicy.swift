import Foundation

nonisolated enum RecordingEffectKind: String, Codable, CaseIterable, Equatable, Sendable {
    case cursor
    case click
    case keystroke
    case webcam
}

nonisolated enum RecordingEffectStorage: String, Codable, Equatable, Sendable {
    case disabled
    case editableMetadata
    case bakedIntoMedia
}

nonisolated struct RecordingEffectCaptureDecision: Codable, Equatable, Sendable {
    let kind: RecordingEffectKind
    let storage: RecordingEffectStorage
    let isInspectable: Bool
    let isDeletable: Bool
    let excludesSecureInput: Bool
    let requiresVisibleIndicator: Bool
    let isExcludedFromDiagnostics: Bool
}

nonisolated struct RecordingEffectCaptureCapabilities: Codable, Equatable, Sendable {
    let cursorMetadata: Bool
    let clickMetadata: Bool
    let webcamSeparateStream: Bool

    init(cursorMetadata: Bool, clickMetadata: Bool, webcamSeparateStream: Bool) {
        self.cursorMetadata = cursorMetadata
        self.clickMetadata = clickMetadata
        self.webcamSeparateStream = webcamSeparateStream
    }
}

nonisolated enum RecordingEffectCapturePolicy {
    static func matrix(
        configuration: RecordingSessionConfiguration,
        capabilities: RecordingEffectCaptureCapabilities,
        secureInputActive: Bool
    ) -> [RecordingEffectCaptureDecision] {
        let cursorEnabled = configuration.cursorMode != .hidden
        let cursorStorage: RecordingEffectStorage = !cursorEnabled
            ? .disabled
            : (capabilities.cursorMetadata ? .editableMetadata : .bakedIntoMedia)

        let clicksEnabled = configuration.events.capturesClicks
            || configuration.cursorMode == .visibleWithClickEffects
        let clickStorage: RecordingEffectStorage = !clicksEnabled
            ? .disabled
            : (capabilities.clickMetadata ? .editableMetadata : .bakedIntoMedia)

        // Keystrokes have no baked fallback: sensitive text must remain opt-in,
        // visibly active, removable metadata and must stop under secure input.
        let keystrokesEnabled = configuration.events.capturesKeystrokes
            && configuration.events.showsKeystrokeCaptureIndicator
            && !secureInputActive
        let webcamEnabled = configuration.webcam != nil
        let webcamStorage: RecordingEffectStorage = !webcamEnabled
            ? .disabled
            : (capabilities.webcamSeparateStream ? .editableMetadata : .bakedIntoMedia)

        return [
            decision(kind: .cursor, storage: cursorStorage),
            decision(kind: .click, storage: clickStorage),
            RecordingEffectCaptureDecision(
                kind: .keystroke,
                storage: keystrokesEnabled ? .editableMetadata : .disabled,
                isInspectable: keystrokesEnabled,
                isDeletable: keystrokesEnabled,
                excludesSecureInput: true,
                requiresVisibleIndicator: true,
                isExcludedFromDiagnostics: true
            ),
            decision(kind: .webcam, storage: webcamStorage)
        ]
    }

    private static func decision(
        kind: RecordingEffectKind,
        storage: RecordingEffectStorage
    ) -> RecordingEffectCaptureDecision {
        let isMetadata = storage == .editableMetadata
        return RecordingEffectCaptureDecision(
            kind: kind,
            storage: storage,
            isInspectable: isMetadata,
            isDeletable: isMetadata,
            excludesSecureInput: false,
            requiresVisibleIndicator: false,
            isExcludedFromDiagnostics: true
        )
    }
}
