import Foundation
import Testing
@testable import Aeroshot

@Suite("Automation parser and router")
@MainActor
struct AutomationRouterTests {
    @Test func urlRoutesEveryAction() throws {
        #expect(try AutomationActionParser.parse(url: #require(URL(string: "aeroshot://capture?mode=area"))) == .capture(.area))
        #expect(try AutomationActionParser.parse(url: #require(URL(string: "aeroshot://open-project?path=%2Ftmp%2Fdemo.aeroshot"))) == .openProject(URL(fileURLWithPath: "/tmp/demo.aeroshot")))
        #expect(try AutomationActionParser.parse(url: #require(URL(string: "aeroshot://reveal?path=%2Ftmp%2Fshot.png"))) == .reveal(URL(fileURLWithPath: "/tmp/shot.png")))
        #expect(try AutomationActionParser.parse(url: #require(URL(string: "aeroshot://privacy-review"))) == .privacyReview)
        #expect(try AutomationActionParser.parse(url: #require(URL(string: "aeroshot://export?preset=png&project=%2Ftmp%2Fa.aeroshot&destination=%2Ftmp%2Fa.png"))) == .exportPreset(.png, project: URL(fileURLWithPath: "/tmp/a.aeroshot"), destination: URL(fileURLWithPath: "/tmp/a.png")))
    }

    @Test func commandLineRoutesEveryAction() throws {
        #expect(try AutomationActionParser.parse(arguments: ["app", "--aeroshot-action", "capture", "--mode", "record-screen"]) == .capture(.recordScreen))
        #expect(try AutomationActionParser.parse(arguments: ["app", "--aeroshot-action", "privacy-review"]) == .privacyReview)
        #expect(try AutomationActionParser.parse(arguments: ["app", "--aeroshot-action", "reveal", "--path", "/tmp/a.png"]) == .reveal(URL(fileURLWithPath: "/tmp/a.png")))
    }

    @Test func rejectsRemoteTraversalUnknownAndDuplicateInputs() {
        #expect(throws: AutomationParseError.self) { try AutomationActionParser.parse(url: #require(URL(string: "https://capture?mode=area"))) }
        #expect(throws: AutomationParseError.self) { try AutomationActionParser.parse(url: #require(URL(string: "aeroshot://open-project?path=https%3A%2F%2Fexample.com%2Fx"))) }
        #expect(throws: AutomationParseError.self) { try AutomationActionParser.parse(url: #require(URL(string: "aeroshot://capture?mode=area&mode=screen"))) }
        #expect(throws: AutomationParseError.self) { try AutomationActionParser.parse(url: #require(URL(string: "aeroshot://shell?command=rm"))) }
        #expect(throws: AutomationParseError.self) { try AutomationActionParser.parse(arguments: ["app", "--aeroshot-action", "capture", "--mode", "area", "--command", "whoami"]) }
        #expect(throws: AutomationParseError.self) { try AutomationActionParser.localURL("relative/file", name: "path") }
    }

    @Test func externalURLCaptureRequiresFreshConsent() {
        #expect(!AutomationAction.capture(.area).allowsExternalURL { _ in false })
        #expect(AutomationAction.capture(.recordScreen).allowsExternalURL { _ in true })

        var askedForNonCaptureAction = false
        #expect(AutomationAction.privacyReview.allowsExternalURL { _ in
            askedForNonCaptureAction = true
            return false
        })
        #expect(!askedForNonCaptureAction)
    }

    @Test func routerUsesOneTypedHostAndNeverNetworks() {
        let host = Host()
        let router = AutomationRouter(host: host)
        #expect(router.route(.capture(.window)).succeeded)
        #expect(router.route(.privacyReview).succeeded)
        #expect(router.route(.exportPreset(.h264, project: URL(fileURLWithPath: "/missing.aeroshot"), destination: URL(fileURLWithPath: "/tmp/x.mp4"))) == .rejected("export precondition"))
        #expect(host.actions == ["capture:window", "privacy", "export:h264"])
        #expect(host.networkRequests == 0)
    }

    @MainActor final class Host: AutomationActionHosting {
        var actions: [String] = []
        var networkRequests = 0
        func capture(_ mode: AutomationCaptureMode) -> AutomationResult { actions.append("capture:\(mode.rawValue)"); return .accepted("ok") }
        func openProject(at url: URL) -> AutomationResult { actions.append("open"); return .accepted("ok") }
        func export(_ preset: AutomationExportPreset, project: URL, destination: URL) -> AutomationResult { actions.append("export:\(preset.rawValue)"); return .rejected("export precondition") }
        func reveal(_ url: URL) -> AutomationResult { actions.append("reveal"); return .accepted("ok") }
        func reviewPrivacy() -> AutomationResult { actions.append("privacy"); return .accepted("ok") }
    }
}
