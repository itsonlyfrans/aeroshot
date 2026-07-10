import Foundation
import Testing
@testable import Aeroshot

@Suite("Export recipes")
struct ExportRecipeTests {
    @Test func builtInPresetsAreStableAndCodable() throws {
        let presets = ExportRecipe.builtIns
        #expect(presets.map(\.id) == [.documentation, .socialSquare, .socialLandscape, .retinaAsset, .downscaledAsset])
        let data = try JSONEncoder().encode(presets)
        #expect(try JSONDecoder().decode([ExportRecipe].self, from: data) == presets)
    }

    @Test func documentationRecipeCompilesStillInputAndSafeName() throws {
        let recipe = ExportRecipe.documentation
        let review = PrivacyReview.passed(reviewID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!)
        let compiled = try ExportRecipeCompiler.compile(
            recipe: recipe,
            source: .init(pixelSize: .init(width: 2400, height: 1600), scale: 2),
            baseName: "Login / dialog?",
            privacyReview: review
        )
        let expectedSize = try AeroPixelSize(width: 1200, height: 800)
        #expect(compiled.pixelSize == expectedSize)
        #expect(compiled.fileName == "login-dialog.png")
        guard case .still(let input) = compiled.exportInput else {
            Issue.record("Expected the still exporter input")
            return
        }
        #expect(input.format == .png)
        #expect(input.downscaleToPoints)
        #expect(input.scale == 2)
    }

    @Test func socialRecipeAppliesRatioAndEvenMediaDimensions() throws {
        var recipe = ExportRecipe.socialLandscape
        recipe.format = .mp4(codec: .h264, frameRate: 30)
        let compiled = try ExportRecipeCompiler.compile(
            recipe: recipe,
            source: .init(pixelSize: .init(width: 2001, height: 1400), scale: 1),
            baseName: "Launch Demo",
            privacyReview: .passed(reviewID: UUID())
        )
        let expectedSize = try AeroPixelSize(width: 1600, height: 900)
        #expect(compiled.pixelSize == expectedSize)
        guard case .media(let preset) = compiled.exportInput else {
            Issue.record("Expected media exporter input")
            return
        }
        #expect(preset.pixelSize == expectedSize)
        try preset.validate()
    }

    @Test func gifRecipeCompilesExistingSettings() throws {
        var recipe = ExportRecipe.downscaledAsset
        recipe.format = .gif(paletteSize: 64)
        let compiled = try ExportRecipeCompiler.compile(
            recipe: recipe,
            source: .init(pixelSize: .init(width: 1800, height: 1200), scale: 1),
            baseName: "Tour",
            privacyReview: .passed(reviewID: UUID())
        )
        guard case .gif(let settings) = compiled.exportInput else {
            Issue.record("Expected GIF writer settings")
            return
        }
        #expect(settings.outputWidth == 900)
        #expect(settings.outputHeight == 600)
        #expect(settings.paletteSize == 64)
        _ = try settings.validated()
    }

    @Test func requiredPrivacyReviewFailsClosed() {
        for review in [PrivacyReview.notPerformed, .failed(reason: .scannerUnavailable)] {
            #expect(throws: ExportRecipeError.privacyReviewRequired) {
                try ExportRecipeCompiler.compile(
                    recipe: .documentation,
                    source: .init(pixelSize: .init(width: 100, height: 100), scale: 1),
                    baseName: "capture",
                    privacyReview: review
                )
            }
        }
    }

    @Test func resultAuditContainsNoCapturedContent() throws {
        let reviewID = UUID()
        let compiled = try ExportRecipeCompiler.compile(
            recipe: .documentation,
            source: .init(pixelSize: .init(width: 100, height: 100), scale: 1),
            baseName: "secret customer dashboard",
            privacyReview: .passed(reviewID: reviewID)
        )
        let result = compiled.auditResult(destination: .clipboard, byteCount: 42)
        #expect(result.recipeID == .documentation)
        #expect(result.reviewID == reviewID)
        #expect(result.destinationKind == .clipboard)
        #expect(result.byteCount == 42)
        #expect(!String(describing: result).contains("secret customer"))
    }

    @Test func destinationsExposeExplicitAvailabilityAndRequests() throws {
        let local = URL(fileURLWithPath: "/tmp/capture.png")
        #expect(ExportDestination.file(local).availability == .available)
        #expect(ExportDestination.revealInFinder(local).availability == .available)
        #expect(ExportDestination.clipboard.availability == .available)
        #expect(ExportDestination.drag.availability == .requiresUserInteraction)
        #expect(ExportDestination.shareSheet.availability == .requiresUserInteraction)

        let share = try ExportDestination.shareSheet.request(for: local)
        #expect(share == .shareSheet(.init(itemURL: local)))
        let clipboard = try ExportDestination.clipboard.request(for: local)
        #expect(clipboard == .clipboard(.init(itemURL: local)))
    }

    @Test func endpointValidationIsUserOwnedHTTPSAndOffline() throws {
        let endpoint = try UserOwnedEndpoint(
            url: URL(string: "https://uploads.example.test/aeroshot")!,
            method: .put,
            headers: ["X-Workspace": "docs"]
        )
        let output = URL(fileURLWithPath: "/tmp/capture.png")
        let destination = ExportDestination.userOwnedEndpoint(endpoint)
        #expect(destination.availability == .available)
        guard case .endpoint(let request) = try destination.request(for: output) else {
            Issue.record("Expected endpoint request metadata")
            return
        }
        #expect(request.url == endpoint.url)
        #expect(request.method == .put)
        #expect(request.localFileURL == output)
        #expect(request.headers == ["X-Workspace": "docs"])

        #expect(throws: ExportDestinationError.endpointMustUseHTTPS) {
            try UserOwnedEndpoint(url: URL(string: "http://example.test/upload")!, method: .post)
        }
        #expect(throws: ExportDestinationError.endpointCannotContainCredentials) {
            try UserOwnedEndpoint(url: URL(string: "https://user:pass@example.test/upload")!, method: .post)
        }
    }
}
