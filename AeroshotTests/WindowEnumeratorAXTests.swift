import ApplicationServices
import Testing
@testable import Aeroshot

@MainActor
struct WindowEnumeratorAXTests {
    @Test func accessibilityGeometryRejectsWrongTypesWithoutCasting() throws {
        var point = CGPoint(x: 12, y: 34)
        var size = CGSize(width: 56, height: 78)
        let pointValue = try #require(AXValueCreate(.cgPoint, &point))
        let sizeValue = try #require(AXValueCreate(.cgSize, &size))
        let text = "not an AX value" as CFString

        #expect(WindowEnumerator.accessibilityPoint(from: pointValue) == point)
        #expect(WindowEnumerator.accessibilitySize(from: sizeValue) == size)
        #expect(WindowEnumerator.accessibilityPoint(from: sizeValue) == nil)
        #expect(WindowEnumerator.accessibilitySize(from: pointValue) == nil)
        #expect(WindowEnumerator.accessibilityPoint(from: text) == nil)
    }
}
