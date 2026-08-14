import Foundation
import Testing

struct ReleaseScriptSafetyTests {
    @Test func uiResultBundleNeverDeletesAnExistingPath() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appending(path: "scripts/run-ui-tests.sh"))

        #expect(!source.contains("rm -rf"))
        #expect(source.contains("[[ -e \"$result_bundle\" || -L \"$result_bundle\" ]]"))
        #expect(source.contains("Refusing to replace existing UI test result path"))
    }

    @Test func releaseScriptsFailClosed() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let build = try String(contentsOf: root.appending(path: "scripts/build-release.sh"))
        let verify = try String(contentsOf: root.appending(path: "scripts/verify-release.sh"))
        let project = try String(contentsOf: root.appending(path: "Aeroshot.xcodeproj/project.pbxproj"))
        let scheme = try String(contentsOf: root.appending(
            path: "Aeroshot.xcodeproj/xcshareddata/xcschemes/Aeroshot.xcscheme"
        ))
        let ignores = try String(contentsOf: root.appending(path: ".gitignore"))
        let workflow = try String(contentsOf: root.appending(path: ".github/workflows/unit-tests.yml"))

        #expect(build.contains("-only-testing:AeroshotTests"))
        #expect(build.contains("-parallel-testing-enabled NO"))
        #expect(verify.contains("\"$artifact_version\" == \"$version\""))
        #expect(verify.contains("FAIL signed entitlements are missing or unreadable"))
        #expect(verify.contains("AEROSHOT_REQUIRE_NOTARIZATION:-1"))
        #expect(!project.contains("INFOPLIST_KEY_NSScreenCaptureUsageDescription"))
        #expect(scheme.contains("BlueprintIdentifier = \"E0B4A02E2FF96D9B00AF9A22\""))
        #expect(scheme.contains("BlueprintName = \"AeroshotTests\""))
        #expect(scheme.contains("BlueprintName = \"AeroshotUITests\""))
        #expect(ignores.contains("*.profraw"))
        #expect(ignores.contains("Aeroshot.xcodeproj/xcuserdata/"))
        #expect(workflow.contains("runs-on: macos-15"))
        #expect(workflow.contains("actions/checkout@v7"))
        #expect(workflow.contains("pnpm install --frozen-lockfile"))
        #expect(workflow.contains("pnpm website:build"))
        #expect(workflow.contains("-only-testing:AeroshotTests"))
        #expect(workflow.contains("-parallel-testing-enabled NO"))
    }

    @Test func websiteClaimsMatchShippingEvidence() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let index = try String(contentsOf: root.appending(path: "website/src/pages/index.astro"))
        let privacy = try String(contentsOf: root.appending(path: "website/src/pages/privacy.astro"))
        let security = try String(contentsOf: root.appending(path: "website/src/pages/security.astro"))
        let privacyEndpoint = try String(contentsOf: root.appending(path: "website/src/pages/privacy.md.ts"))
        let securityEndpoint = try String(contentsOf: root.appending(path: "website/src/pages/security.md.ts"))
        let claims = try String(contentsOf: root.appending(path: "docs/WEBSITE_CLAIMS.md"))
        let project = try String(contentsOf: root.appending(path: "Aeroshot.xcodeproj/project.pbxproj"))

        #expect(!index.contains("href=\"#\""))
        #expect(!index.contains("formatted mock data"))
        #expect(!index.contains("keyboard overlay"))
        #expect(!index.contains("Every capture is auto-tagged"))
        #expect(!index.contains("instantly provides contextual macros"))
        #expect(!index.contains("five independent layers in milliseconds"))
        #expect(index.contains("Public downloads are not available yet"))
        #expect(index.contains("Aeroshot requires macOS 14.6 or newer"))
        #expect(project.contains("MACOSX_DEPLOYMENT_TARGET = 14.6;"))
        #expect(privacy.contains("href=\"/privacy.md\""))
        #expect(security.contains("href=\"/security.md\""))
        #expect(privacyEndpoint.contains("docs/PRIVACY.md?raw"))
        #expect(securityEndpoint.contains("docs/SECURITY.md?raw"))
        #expect(index.contains("id=\"tray-icon-wrapper\" role=\"button\" tabindex=\"0\""))
        #expect(index.contains("id=\"hero-capture-window\" role=\"button\" tabindex=\"0\""))
        #expect(index.contains("function activateWithKeyboard"))
        #expect(index.contains("role=\"dialog\" aria-modal=\"true\""))
        for (heading, evidenceTerm) in [
            ("ShareSafe Redaction", "ShareSafe scans"),
            ("Teach", "Record MP4 or GIF"),
            ("Local Capture History", "History stores captures"),
            ("On-device OCR", "on-device OCR"),
        ] {
            #expect(index.contains(heading))
            #expect(claims.localizedCaseInsensitiveContains(evidenceTerm))
        }
    }
}
