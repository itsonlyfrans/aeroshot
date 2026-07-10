import AppKit
import Foundation
import Testing
@testable import Aeroshot

@MainActor
struct EditorProjectBridgeTests {
    @Test func screenshotProjectRoundTripPreservesEveryEditorField() throws {
        try withPackage { packageURL in
            let document = EditorDocument(image: makeImage())
            document.annotations = makeAnnotations()
            document.cropRect = CGRect(x: 0.25, y: 0.5, width: 2.5, height: 1.25)
            document.straightenDegrees = 2.5
            document.beautify = BeautifySettings(
                enabled: true,
                padding: 87.5,
                cornerRadius: 19.25,
                shadowRadius: 41.75,
                shadowOpacity: 0.3125,
                gradient: .candy,
                aspectPreset: .fourByThree
            )

            let firstManifest = try EditorProjectBridge.save(document, to: packageURL)
            let asset = try #require(firstManifest.assets.first)
            let sourceURL = try AeroProjectPackageStore(packageURL: packageURL)
                .URL(forRelativePath: asset.relativePath)
            let originalData = try Data(contentsOf: sourceURL)

            #expect(firstManifest.primarySourceAssetID == asset.id)
            #expect(asset.isImmutableOriginal)
            #expect(asset.metadata.mediaType == .image)
            #expect(asset.relativePath.hasSuffix(".png"))
            #expect(asset.sha256 == AeroProjectPackageStore.sha256(of: originalData))

            let reopened = try EditorProjectBridge.open(from: packageURL)
            #expect(reopened.pixelSize == document.pixelSize)
            #expect(reopened.annotations == document.annotations)
            #expect(reopened.annotations.map(\.id) == document.annotations.map(\.id))
            #expect(reopened.cropRect == document.cropRect)
            #expect(reopened.straightenDegrees == 2.5)
            #expect(reopened.beautify == document.beautify)

            let secondManifest = try EditorProjectBridge.save(reopened, to: packageURL)
            let secondAsset = try #require(secondManifest.assets.first)
            #expect(secondAsset.id == asset.id)
            #expect(secondAsset.sha256 == asset.sha256)
            #expect(try Data(contentsOf: sourceURL) == originalData)
        }
    }

    @Test func newEditorFieldsDecodeAsBackwardCompatibleDefaults() throws {
        let original = AeroProjectManifest()
        var object = try #require(
            JSONSerialization.jsonObject(with: AeroProjectMigrator.encode(original)) as? [String: Any]
        )
        object.removeValue(forKey: "editorCropRectPixels")
        object.removeValue(forKey: "editorBeautify")
        object.removeValue(forKey: "editorStraightenDegrees")

        let decoded = try AeroProjectMigrator.decodeAndMigrate(
            JSONSerialization.data(withJSONObject: object)
        )

        #expect(decoded.editorCropRectPixels == nil)
        #expect(decoded.editorBeautify == nil)
        #expect(decoded.editorStraightenDegrees == nil)
    }

    @Test func legacyOverlayAppearanceDecodesToByteEquivalentRenderingDefaults() throws {
        try withPackage { packageURL in
            let document = EditorDocument(image: makeImage())
            document.annotations = [Annotation(kind: .arrow, points: [.zero, CGPoint(x: 3, y: 2)])]
            var manifest = try EditorProjectBridge.save(document, to: packageURL)
            manifest.overlays[0].editor?.appearance = nil
            try writeManifestDirectly(manifest, to: packageURL)

            let reopened = try EditorProjectBridge.open(from: packageURL)
            #expect(try #require(reopened.annotations.first).appearance == AnnotationAppearance())
        }
    }

    @Test func malformedAnnotationAppearanceIsRejected() throws {
        try withPackage { packageURL in
            let document = EditorDocument(image: makeImage())
            document.annotations = [makeAnnotations()[0]]
            var manifest = try EditorProjectBridge.save(document, to: packageURL)
            manifest.overlays[0].editor?.appearance?.strokeOpacity = 1.01
            try writeManifestDirectly(manifest, to: packageURL)
            let id = manifest.overlays[0].id

            #expect(throws: EditorProjectBridgeError.invalidAnnotationAppearance(id)) {
                try EditorProjectBridge.open(from: packageURL)
            }
        }
    }

    @Test func malformedAnnotationAppearanceEnumsAndColorsAreRejected() throws {
        try withPackage { packageURL in
            let document = EditorDocument(image: makeImage())
            document.annotations = [makeAnnotations()[0]]
            var manifest = try EditorProjectBridge.save(document, to: packageURL)
            manifest.overlays[0].editor?.appearance?.strokeLineCap = "triangle"
            manifest.overlays[0].editor?.appearance?.strokeShadow.colorRGBA = [0, 0, 0, 2]
            try writeManifestDirectly(manifest, to: packageURL)
            let id = manifest.overlays[0].id

            #expect(throws: EditorProjectBridgeError.invalidAnnotationAppearance(id)) {
                try EditorProjectBridge.open(from: packageURL)
            }
        }
    }

    @Test func missingSourceAssetIsRejectedWithoutFlattening() throws {
        try withSavedProject { packageURL, manifest in
            let sourceID = try #require(manifest.primarySourceAssetID)
            let source = try #require(manifest.assets.first { $0.id == sourceID })
            try FileManager.default.removeItem(
                at: AeroProjectPackageStore(packageURL: packageURL)
                    .URL(forRelativePath: source.relativePath)
            )

            #expect(throws: AeroProjectPackageError.missingAsset(sourceID)) {
                try EditorProjectBridge.open(from: packageURL)
            }
        }
    }

    @Test func wrongTypeSourceAssetIsRejected() throws {
        try withSavedProject { packageURL, saved in
            var manifest = saved
            let sourceID = try #require(manifest.primarySourceAssetID)
            let index = try #require(manifest.assets.firstIndex { $0.id == sourceID })
            let source = manifest.assets[index]
            manifest.assets[index] = AeroProjectAsset(
                id: source.id,
                relativePath: source.relativePath,
                sha256: source.sha256,
                byteCount: source.byteCount,
                isImmutableOriginal: source.isImmutableOriginal,
                metadata: AeroMediaMetadata(
                    mediaType: .video,
                    pixelSize: source.metadata.pixelSize,
                    duration: nil,
                    nominalFrameRate: nil,
                    colorSpaceName: source.metadata.colorSpaceName,
                    hasAudio: false
                )
            )
            try writeManifestDirectly(manifest, to: packageURL)

            #expect(throws: EditorProjectBridgeError.wrongSourceMediaType(sourceID, .video)) {
                try EditorProjectBridge.open(from: packageURL)
            }
        }
    }

    @Test func mutablePrimarySourceIsRejected() throws {
        try withSavedProject { packageURL, saved in
            var manifest = saved
            let sourceID = try #require(manifest.primarySourceAssetID)
            let index = try #require(manifest.assets.firstIndex { $0.id == sourceID })
            let source = manifest.assets[index]
            manifest.assets[index] = AeroProjectAsset(
                id: source.id,
                relativePath: source.relativePath,
                sha256: source.sha256,
                byteCount: source.byteCount,
                isImmutableOriginal: false,
                metadata: source.metadata
            )
            try writeManifestDirectly(manifest, to: packageURL)

            #expect(throws: EditorProjectBridgeError.sourceIsNotImmutable(sourceID)) {
                try EditorProjectBridge.open(from: packageURL)
            }
        }
    }

    @Test func corruptSourceWithMatchingChecksumIsRejected() throws {
        try withSavedProject { packageURL, saved in
            var manifest = saved
            let sourceID = try #require(manifest.primarySourceAssetID)
            let index = try #require(manifest.assets.firstIndex { $0.id == sourceID })
            let source = manifest.assets[index]
            let corruptData = Data("not an image".utf8)
            let store = AeroProjectPackageStore(packageURL: packageURL)
            try corruptData.write(to: store.URL(forRelativePath: source.relativePath), options: .atomic)
            manifest.assets[index] = AeroProjectAsset(
                id: source.id,
                relativePath: source.relativePath,
                sha256: AeroProjectPackageStore.sha256(of: corruptData),
                byteCount: Int64(corruptData.count),
                isImmutableOriginal: source.isImmutableOriginal,
                metadata: source.metadata
            )
            try writeManifestDirectly(manifest, to: packageURL)

            #expect(throws: EditorProjectBridgeError.corruptSourceImage(sourceID)) {
                try EditorProjectBridge.open(from: packageURL)
            }
        }
    }

    @Test func unsupportedOverlayIsRejectedRatherThanFlattened() throws {
        try withPackage { packageURL in
            let document = EditorDocument(image: makeImage())
            document.annotations = [makeAnnotations()[0]]
            var manifest = try EditorProjectBridge.save(document, to: packageURL)
            let overlayID = try #require(manifest.overlays.first?.id)
            manifest.overlays[0].editor = nil
            try writeManifestDirectly(manifest, to: packageURL)

            #expect(throws: EditorProjectBridgeError.unsupportedOverlay(overlayID)) {
                try EditorProjectBridge.open(from: packageURL)
            }
        }
    }

    @Test func existingImmutableSourceCannotBeReboundToAnotherImage() throws {
        try withSavedProject { packageURL, manifest in
            let sourceID = try #require(manifest.primarySourceAssetID)
            let context = CGContext(
                data: nil,
                width: 4,
                height: 3,
                bitsPerComponent: 8,
                bytesPerRow: 16,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
            let otherDocument = EditorDocument(image: context.makeImage()!)

            #expect(throws: EditorProjectBridgeError.sourceDoesNotMatchDocument(sourceID)) {
                try EditorProjectBridge.save(otherDocument, to: packageURL)
            }
        }
    }

    private func makeAnnotations() -> [Annotation] {
        let kinds: [AnnotationKind] = [
            .arrow, .rectangle, .ellipse, .line, .freehand, .highlighter,
            .text, .redactBlur, .redactPixelate, .redactSolid, .step,
        ]
        return kinds.enumerated().map { index, kind in
            Annotation(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                kind: kind,
                points: [
                    CGPoint(x: Double(index) + 0.125, y: Double(index) + 0.25),
                    CGPoint(x: Double(index) + 1.5, y: Double(index) + 1.75),
                    CGPoint(x: Double(index) + 2.875, y: Double(index) + 2.625),
                ],
                color: NSColor(
                    srgbRed: CGFloat(index + 1) / 16,
                    green: CGFloat(index + 2) / 16,
                    blue: CGFloat(index + 3) / 16,
                    alpha: CGFloat(index + 4) / 16
                ),
                lineWidth: CGFloat(index) + 0.375,
                text: "annotation-\(index)",
                fontSize: CGFloat(index) + 12.625,
                stepNumber: index + 3,
                filled: index.isMultiple(of: 2),
                appearance: customizedAppearance(index: index)
            )
        }
    }

    private func customizedAppearance(index: Int) -> AnnotationAppearance {
        AnnotationAppearance(
            stroke: AnnotationStrokeAppearance(
                opacity: 0.8125,
                dash: [1.25, 2.5, 3.75],
                dashPhase: -0.625,
                lineCap: .square,
                shadow: AnnotationShadow(
                    color: NSColor(srgbRed: 0.125, green: 0.25, blue: 0.375, alpha: 0.5),
                    opacity: 0.4375,
                    radius: 6.25,
                    offset: CGSize(width: -2.75, height: 3.5)
                )
            ),
            fill: AnnotationFillAppearance(opacity: 0.6875),
            cornerRadius: 9.125,
            arrow: AnnotationArrowAppearance(
                startStyle: .open,
                endStyle: .filled,
                headLength: 17.25,
                headWidth: 8.75,
                inset: 4.5,
                curve: -11.625
            ),
            typography: AnnotationTypography(
                fontName: "Helvetica Neue",
                weight: .black,
                alignment: .trailing,
                backgroundColor: NSColor(
                    srgbRed: CGFloat(index + 1) / 16,
                    green: 0.3125,
                    blue: 0.5625,
                    alpha: 0.75
                ),
                backgroundOpacity: 0.59375,
                padding: AnnotationInsets(top: 1.25, leading: 2.5, bottom: 3.75, trailing: 5),
                lineHeight: 1.375
            )
        )
    }

    private func makeImage() -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: 4,
            height: 3,
            bitsPerComponent: 8,
            bytesPerRow: 4 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        return context.makeImage()!
    }

    private func withSavedProject(
        _ body: (URL, AeroProjectManifest) throws -> Void
    ) throws {
        try withPackage { packageURL in
            let manifest = try EditorProjectBridge.save(
                EditorDocument(image: makeImage()),
                to: packageURL
            )
            try body(packageURL, manifest)
        }
    }

    private func withPackage(_ body: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "EditorProjectBridgeTests-\(UUID().uuidString).aeroshot")
        defer { try? FileManager.default.removeItem(at: url) }
        try body(url)
    }

    private func writeManifestDirectly(_ manifest: AeroProjectManifest, to packageURL: URL) throws {
        try AeroProjectMigrator.encode(manifest).write(
            to: packageURL.appending(path: AeroProjectPackageStore.manifestFileName),
            options: .atomic
        )
    }
}
