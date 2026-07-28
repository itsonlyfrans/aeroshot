import Foundation

/// Named bundle of capture-related settings (format, workflow, beautify defaults).
struct CaptureProfile: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let symbol: String
    let summary: String

    var imageFormat: ImageFormat
    var copyToClipboardAfterCapture: Bool
    var saveToDiskAfterCapture: Bool
    var showThumbnailAfterCapture: Bool
    var openEditorAfterCapture: Bool
    var playCaptureSound: Bool
    var filenameTemplate: String
    var beautifyEnabledDefault: Bool
    var beautifyPadding: Double
    var beautifyCornerRadius: Double
    var beautifyShadowRadius: Double
    var beautifyShadowOpacity: Double
    var beautifyGradientRaw: String
    var beautifyAspectRaw: String

    init(
        id: String,
        name: String,
        symbol: String,
        summary: String,
        imageFormat: ImageFormat,
        copyToClipboardAfterCapture: Bool,
        saveToDiskAfterCapture: Bool,
        showThumbnailAfterCapture: Bool,
        openEditorAfterCapture: Bool,
        playCaptureSound: Bool,
        filenameTemplate: String,
        beautifyEnabledDefault: Bool,
        beautifyPadding: Double,
        beautifyCornerRadius: Double,
        beautifyShadowRadius: Double,
        beautifyShadowOpacity: Double,
        beautifyGradientRaw: String,
        beautifyAspectRaw: String
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.summary = summary
        self.imageFormat = imageFormat
        self.copyToClipboardAfterCapture = copyToClipboardAfterCapture
        self.saveToDiskAfterCapture = saveToDiskAfterCapture
        self.showThumbnailAfterCapture = showThumbnailAfterCapture
        self.openEditorAfterCapture = openEditorAfterCapture
        self.playCaptureSound = playCaptureSound
        self.filenameTemplate = filenameTemplate
        self.beautifyEnabledDefault = beautifyEnabledDefault
        self.beautifyPadding = beautifyPadding
        self.beautifyCornerRadius = beautifyCornerRadius
        self.beautifyShadowRadius = beautifyShadowRadius
        self.beautifyShadowOpacity = beautifyShadowOpacity
        self.beautifyGradientRaw = beautifyGradientRaw
        self.beautifyAspectRaw = beautifyAspectRaw
    }

    static let standard = CaptureProfile(
        id: "standard",
        name: "Standard",
        symbol: "camera.viewfinder",
        summary: "Save and thumbnail, without changing your clipboard.",
        imageFormat: .png,
        copyToClipboardAfterCapture: false,
        saveToDiskAfterCapture: true,
        showThumbnailAfterCapture: true,
        openEditorAfterCapture: false,
        playCaptureSound: true,
        filenameTemplate: "Screenshot {date} at {time}",
        beautifyEnabledDefault: false,
        beautifyPadding: 64,
        beautifyCornerRadius: 12,
        beautifyShadowRadius: 30,
        beautifyShadowOpacity: 0.45,
        beautifyGradientRaw: BeautifySettings.GradientPreset.indigo.rawValue,
        beautifyAspectRaw: BeautifySettings.AspectPreset.auto.rawValue
    )

    static let bugReport = CaptureProfile(
        id: "bug-report",
        name: "Bug Report",
        symbol: "ladybug.fill",
        summary: "PNG with app name in filename; opens editor for annotations.",
        imageFormat: .png,
        copyToClipboardAfterCapture: true,
        saveToDiskAfterCapture: true,
        showThumbnailAfterCapture: true,
        openEditorAfterCapture: true,
        playCaptureSound: true,
        filenameTemplate: "{app} {date} {time}",
        beautifyEnabledDefault: false,
        beautifyPadding: 64,
        beautifyCornerRadius: 12,
        beautifyShadowRadius: 30,
        beautifyShadowOpacity: 0.45,
        beautifyGradientRaw: BeautifySettings.GradientPreset.mono.rawValue,
        beautifyAspectRaw: BeautifySettings.AspectPreset.auto.rawValue
    )

    static let social = CaptureProfile(
        id: "social",
        name: "Social",
        symbol: "sparkles.rectangle.stack",
        summary: "Beautify on with 1:1 frame; copy to clipboard for quick posting.",
        imageFormat: .png,
        copyToClipboardAfterCapture: true,
        saveToDiskAfterCapture: false,
        showThumbnailAfterCapture: true,
        openEditorAfterCapture: false,
        playCaptureSound: false,
        filenameTemplate: "Share {date} at {time}",
        beautifyEnabledDefault: true,
        beautifyPadding: 72,
        beautifyCornerRadius: 16,
        beautifyShadowRadius: 36,
        beautifyShadowOpacity: 0.5,
        beautifyGradientRaw: BeautifySettings.GradientPreset.sunset.rawValue,
        beautifyAspectRaw: BeautifySettings.AspectPreset.square.rawValue
    )

    static let docs = CaptureProfile(
        id: "docs",
        name: "Docs",
        symbol: "doc.richtext",
        summary: "Save PNGs with dated filenames; no clipboard noise.",
        imageFormat: .png,
        copyToClipboardAfterCapture: false,
        saveToDiskAfterCapture: true,
        showThumbnailAfterCapture: false,
        openEditorAfterCapture: false,
        playCaptureSound: true,
        filenameTemplate: "Docs {date} {time}",
        beautifyEnabledDefault: false,
        beautifyPadding: 48,
        beautifyCornerRadius: 8,
        beautifyShadowRadius: 20,
        beautifyShadowOpacity: 0.35,
        beautifyGradientRaw: BeautifySettings.GradientPreset.ocean.rawValue,
        beautifyAspectRaw: BeautifySettings.AspectPreset.auto.rawValue
    )

    static let builtIn: [CaptureProfile] = [.standard, .bugReport, .social, .docs]

    static func profile(for id: String) -> CaptureProfile? {
        builtIn.first { $0.id == id }
    }

    @MainActor
    func matches(_ store: SettingsStore) -> Bool {
        imageFormat == store.imageFormat
            && copyToClipboardAfterCapture == store.copyToClipboardAfterCapture
            && saveToDiskAfterCapture == store.saveToDiskAfterCapture
            && showThumbnailAfterCapture == store.showThumbnailAfterCapture
            && openEditorAfterCapture == store.openEditorAfterCapture
            && playCaptureSound == store.playCaptureSound
            && filenameTemplate == store.filenameTemplate
            && beautifyEnabledDefault == store.beautifyEnabledDefault
            && beautifyPadding == store.beautifyPadding
            && beautifyCornerRadius == store.beautifyCornerRadius
            && beautifyShadowRadius == store.beautifyShadowRadius
            && beautifyShadowOpacity == store.beautifyShadowOpacity
            && beautifyGradientRaw == store.beautifyGradientPreset.rawValue
            && beautifyAspectRaw == store.beautifyAspectPreset.rawValue
    }

    func apply(to store: SettingsStore) {
        store.imageFormat = imageFormat
        store.copyToClipboardAfterCapture = copyToClipboardAfterCapture
        store.saveToDiskAfterCapture = saveToDiskAfterCapture
        store.showThumbnailAfterCapture = showThumbnailAfterCapture
        store.openEditorAfterCapture = openEditorAfterCapture
        store.playCaptureSound = playCaptureSound
        store.filenameTemplate = filenameTemplate
        store.beautifyEnabledDefault = beautifyEnabledDefault
        store.beautifyPadding = beautifyPadding
        store.beautifyCornerRadius = beautifyCornerRadius
        store.beautifyShadowRadius = beautifyShadowRadius
        store.beautifyShadowOpacity = beautifyShadowOpacity
        store.beautifyGradientPreset = BeautifySettings.GradientPreset(rawValue: beautifyGradientRaw) ?? .indigo
        store.beautifyAspectPreset = BeautifySettings.AspectPreset(rawValue: beautifyAspectRaw) ?? .auto
    }
}
