import Foundation
import Testing
@testable import Aeroshot

struct PrivacyFilterModelIntegrityTests {
    @Test func artifactIntegrityMustMatchThePinnedDigest() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "PrivacyFilterIntegrity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data("reviewed model bytes".utf8)
        try data.write(to: url)
        let digest = AeroProjectPackageStore.sha256(of: data)

        try PrivacyFilterModel.verifyArtifact(at: url, expectedSHA256: digest)
        #expect(throws: PrivacyFilterModelError.integrityCheckFailed(url.lastPathComponent)) {
            try PrivacyFilterModel.verifyArtifact(
                at: url,
                expectedSHA256: String(repeating: "0", count: 64)
            )
        }
        #expect(PrivacyFilterModel.artifactRevision.count == 40)
    }
}
