import Foundation
import Testing

struct AllInOneLifecycleTests {
    @Test func terminalPathsReleaseFrozenDisplayImagesAfterSnapshottingThem() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appending(path: "Aeroshot/HUD/AllInOneController.swift"))
        let snapshots = try #require(source.range(of: "let frozenImages = self.frozenImages"))
        let finish = try #require(source.range(of: "finish(cancelled: false)", range: snapshots.upperBound..<source.endIndex))
        #expect(snapshots.lowerBound < finish.lowerBound)

        let cleanupStart = try #require(source.range(of: "private func finish(cancelled:"))
        let cleanupEnd = try #require(source.range(of: "private func dispatchInstant", range: cleanupStart.upperBound..<source.endIndex))
        let cleanup = source[cleanupStart.lowerBound..<cleanupEnd.lowerBound]
        #expect(cleanup.contains("displays = []"))
        #expect(cleanup.contains("frozenImages = [:]"))
        #expect(cleanup.contains("freezesScreen = false"))
    }
}
