import Testing
@testable import Aeroshot

@Suite("Atlas workbench")
struct AtlasWorkbenchTests {
    @Test func catalogMatchesTheMockupSurfaces() {
        #expect(AtlasWorkbenchSurface.allCases.count == 10)
        #expect(AtlasWorkbenchSurface.allCases.map(\.rawValue).contains("selection"))
        #expect(AtlasWorkbenchSurface.allCases.map(\.rawValue).contains("settings"))
    }
}

