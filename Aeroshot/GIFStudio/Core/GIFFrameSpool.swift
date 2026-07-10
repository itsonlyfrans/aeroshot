import CoreGraphics
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers

/// Disk-backed capture spool. Its resident state contains URLs and integers only, never decoded frames.
nonisolated final class GIFFrameSpool: @unchecked Sendable {
    struct Limits: Equatable, Sendable {
        var maximumFrameCount: Int
        var maximumBytes: Int64

        static let recordingDefault = Limits(maximumFrameCount: 18_000, maximumBytes: 4 * 1_024 * 1_024 * 1_024)
    }

    struct Statistics: Equatable, Sendable {
        var frameCount: Int
        var byteCount: Int64
        /// Always zero by construction; useful as an executable memory-shape invariant.
        var residentDecodedFrameCount: Int { 0 }
    }

    private struct Entry: Codable {
        var id: UUID
        var fileName: String
        var durationMicroseconds: Int64
        var byteCount: Int64
    }

    private struct State {
        var entries: [Entry] = []
        var byteCount: Int64 = 0
        var isClosed = false
    }

    let directoryURL: URL
    let limits: Limits
    private let ownsDirectory: Bool
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(directoryURL: URL? = nil, limits: Limits = .recordingDefault) throws {
        guard limits.maximumFrameCount > 0, limits.maximumBytes > 0 else { throw GIFCoreError.invalidSettings }
        self.limits = limits
        self.ownsDirectory = directoryURL == nil
        self.directoryURL = directoryURL ?? FileManager.default.temporaryDirectory
            .appending(path: "Aeroshot-GIF-Spool-" + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
    }

    deinit { if ownsDirectory { try? FileManager.default.removeItem(at: directoryURL) } }

    var statistics: Statistics {
        state.withLock { Statistics(frameCount: $0.entries.count, byteCount: $0.byteCount) }
    }

    @discardableResult
    func append(_ image: CGImage, durationMicroseconds: Int64) throws -> Bool {
        guard durationMicroseconds > 0 else { throw GIFCoreError.invalidDuration }
        let id = UUID()
        let fileName = id.uuidString + ".png"
        let destinationURL = directoryURL.appending(path: fileName)
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw GIFCoreError.imageWriteFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw GIFCoreError.imageWriteFailed }
        let byteCount = Int64((try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)

        let accepted = state.withLock { current -> Bool in
            guard !current.isClosed,
                  current.entries.count < limits.maximumFrameCount,
                  current.byteCount + byteCount <= limits.maximumBytes else { return false }
            current.entries.append(Entry(id: id, fileName: fileName, durationMicroseconds: durationMicroseconds, byteCount: byteCount))
            current.byteCount += byteCount
            return true
        }
        if !accepted { try? FileManager.default.removeItem(at: destinationURL) }
        return accepted
    }

    func makeDocument(settings: GIFExportSettings = .init()) throws -> GIFDocument {
        let entries = state.withLock { current -> [Entry] in
            current.isClosed = true
            return current.entries
        }
        return try GIFDocument(frames: entries.map {
            try GIFFrame(id: $0.id, sourceURL: directoryURL.appending(path: $0.fileName), durationMicroseconds: $0.durationMicroseconds)
        }, settings: settings)
    }

    func removeAll() {
        let names = state.withLock { current -> [String] in
            let names = current.entries.map(\.fileName)
            current.entries = []
            current.byteCount = 0
            current.isClosed = true
            return names
        }
        for name in names { try? FileManager.default.removeItem(at: directoryURL.appending(path: name)) }
        if ownsDirectory { try? FileManager.default.removeItem(at: directoryURL) }
    }

    /// Removes abandoned owned spools from previous process lifetimes.
    static func recoverAbandonedSpools(
        in root: URL = FileManager.default.temporaryDirectory,
        olderThan maximumAge: TimeInterval = 24 * 60 * 60
    ) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return }
        for url in urls where url.lastPathComponent.hasPrefix("Aeroshot-GIF-Spool-") {
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if modified.map({ Date().timeIntervalSince($0) >= maximumAge }) ?? true {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
