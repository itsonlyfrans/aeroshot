@preconcurrency import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import QuartzCore

nonisolated struct MediaCropLayout: Equatable, Sendable {
    let sourceRect: CGRect
    let outputRect: CGRect
    let cropRect: CGRect
    let fittedCropRect: CGRect
    let transformedSourceRect: CGRect
    let scale: CGFloat

    var sourceTranslation: CGPoint {
        CGPoint(x: fittedCropRect.minX - cropRect.minX * scale,
                y: fittedCropRect.minY - cropRect.minY * scale)
    }

    static func make(sourceRect: CGRect, outputRect: CGRect, normalizedCrop: CGRect) -> MediaCropLayout? {
        let values = [sourceRect.minX, sourceRect.minY, sourceRect.width, sourceRect.height,
                      outputRect.minX, outputRect.minY, outputRect.width, outputRect.height,
                      normalizedCrop.minX, normalizedCrop.minY, normalizedCrop.width, normalizedCrop.height]
        guard values.allSatisfy(\.isFinite), sourceRect.width > 0, sourceRect.height > 0,
              outputRect.width > 0, outputRect.height > 0,
              normalizedCrop.minX >= 0, normalizedCrop.minY >= 0,
              normalizedCrop.width > 0, normalizedCrop.height > 0,
              normalizedCrop.maxX <= 1, normalizedCrop.maxY <= 1 else { return nil }

        let cropRect = CGRect(
            x: sourceRect.minX + normalizedCrop.minX * sourceRect.width,
            y: sourceRect.minY + normalizedCrop.minY * sourceRect.height,
            width: normalizedCrop.width * sourceRect.width,
            height: normalizedCrop.height * sourceRect.height
        )
        let scale = min(outputRect.width / cropRect.width, outputRect.height / cropRect.height)
        guard scale.isFinite, scale > 0 else { return nil }
        let fittedSize = CGSize(width: cropRect.width * scale, height: cropRect.height * scale)
        let fittedCropRect = CGRect(
            x: outputRect.midX - fittedSize.width / 2,
            y: outputRect.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
        let transformedSourceRect = CGRect(
            x: fittedCropRect.minX - (cropRect.minX - sourceRect.minX) * scale,
            y: fittedCropRect.minY - (cropRect.minY - sourceRect.minY) * scale,
            width: sourceRect.width * scale,
            height: sourceRect.height * scale
        )
        let derivedValues = [cropRect.minX, cropRect.minY, cropRect.width, cropRect.height,
                             fittedCropRect.minX, fittedCropRect.minY, fittedCropRect.width, fittedCropRect.height,
                             transformedSourceRect.minX, transformedSourceRect.minY,
                             transformedSourceRect.width, transformedSourceRect.height]
        let layout = MediaCropLayout(sourceRect: sourceRect, outputRect: outputRect, cropRect: cropRect,
                               fittedCropRect: fittedCropRect, transformedSourceRect: transformedSourceRect,
                               scale: scale)
        guard derivedValues.allSatisfy(\.isFinite), layout.sourceTranslation.x.isFinite,
              layout.sourceTranslation.y.isFinite else { return nil }
        return layout
    }

    func outputPoint(forSourceNormalized point: CGPoint) -> CGPoint? {
        guard point.x.isFinite, point.y.isFinite, point.x >= 0, point.x <= 1,
              point.y >= 0, point.y <= 1 else { return nil }
        let sourcePoint = CGPoint(x: sourceRect.minX + point.x * sourceRect.width,
                                  y: sourceRect.minY + point.y * sourceRect.height)
        guard sourcePoint.x >= cropRect.minX, sourcePoint.x <= cropRect.maxX,
              sourcePoint.y >= cropRect.minY, sourcePoint.y <= cropRect.maxY else { return nil }
        let mapped = CGPoint(x: transformedSourceRect.minX + (sourcePoint.x - sourceRect.minX) * scale,
                             y: transformedSourceRect.minY + (sourcePoint.y - sourceRect.minY) * scale)
        return mapped.x.isFinite && mapped.y.isFinite ? mapped : nil
    }

    func normalizedOutputPoint(forSourceNormalized point: CGPoint) -> CGPoint? {
        guard let mapped = outputPoint(forSourceNormalized: point) else { return nil }
        return CGPoint(x: (mapped.x - outputRect.minX) / outputRect.width,
                       y: (mapped.y - outputRect.minY) / outputRect.height)
    }
}

nonisolated enum MediaExportVideoComposition {
    static func make(
        asset: AVAsset,
        snapshot: MediaExportSnapshot,
        preset: MediaExportPreset
    ) async throws -> AVMutableVideoComposition {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw MediaExportError.sourceHasNoVideo
        }
        let duration = try await asset.load(.duration)
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let outputSize = CGSize(width: preset.pixelSize.width, height: preset.pixelSize.height)

        let composition = AVMutableVideoComposition()
        composition.renderSize = outputSize
        guard preset.frameRate.value <= Int64(Int32.max) else { throw MediaExportError.invalidFrameRate }
        composition.frameDuration = CMTime(value: Int64(preset.frameRate.timescale), timescale: CMTimeScale(preset.frameRate.value))
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        guard let transformed = MediaSourceGeometry.orientedRect(
            naturalSize: naturalSize, preferredTransform: preferredTransform
        ) else { throw MediaExportError.invalidResolution }
        let crop = snapshot.canvas.crop
        guard let layout = MediaCropLayout.make(
            sourceRect: transformed,
            outputRect: CGRect(origin: .zero, size: outputSize),
            normalizedCrop: CGRect(x: crop.x, y: crop.y, width: crop.width, height: crop.height)
        ) else { throw MediaExportError.invalidResolution }
        let translation = CGAffineTransform(
            translationX: layout.sourceTranslation.x,
            y: layout.sourceTranslation.y
        )
        layerInstruction.setTransform(preferredTransform.concatenating(CGAffineTransform(scaleX: layout.scale, y: layout.scale)).concatenating(translation), at: .zero)
        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: outputSize)
        let cropMask = CALayer()
        cropMask.frame = layout.fittedCropRect
        cropMask.backgroundColor = CGColor(gray: 1, alpha: 1)
        videoLayer.mask = cropMask
        let parentLayer = CALayer()
        parentLayer.frame = videoLayer.frame
        parentLayer.backgroundColor = CGColor(gray: 0, alpha: 1)
        parentLayer.addSublayer(videoLayer)
        for command in MediaOverlayCompiler.compile(snapshot) {
            parentLayer.addSublayer(try layer(for: command, outputSize: outputSize, duration: duration.seconds))
        }
        composition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
        return composition
    }

    private static func layer(
        for command: MediaOverlayCommand,
        outputSize: CGSize,
        duration: Double
    ) throws -> CALayer {
        guard command.kind != .blur, command.kind != .pixelate else {
            throw MediaExportError.unsupportedOfflineOverlay(command.id)
        }
        let normalized = command.bounds
        let frame = CGRect(
            x: normalized.x * outputSize.width,
            y: (1 - normalized.y - normalized.height) * outputSize.height,
            width: normalized.width * outputSize.width,
            height: normalized.height * outputSize.height
        )
        let layer: CALayer
        if command.kind == .text || command.kind == .step {
            layer = rasterizedTextLayer(for: command, size: frame.size)
        } else {
            let shape = CAShapeLayer()
            let path = CGMutablePath()
            if command.points.count > 1 {
                let first = command.points[0]
                path.move(to: CGPoint(x: first.x * frame.width, y: (1 - first.y) * frame.height))
                for point in command.points.dropFirst() {
                    path.addLine(to: CGPoint(x: point.x * frame.width, y: (1 - point.y) * frame.height))
                }
            } else if command.content?.hasPrefix("effect.") == true {
                path.addEllipse(in: CGRect(origin: .zero, size: frame.size))
            } else {
                path.addRect(CGRect(origin: .zero, size: frame.size))
            }
            shape.path = path
            shape.strokeColor = color(command.appearance.strokeRGBA)
            shape.fillColor = command.appearance.fillRGBA.map(color) ?? (command.kind == .solidRedaction ? color(command.appearance.strokeRGBA) : nil)
            shape.lineWidth = command.appearance.strokeWidth
            layer = shape
        }
        layer.frame = frame
        layer.opacity = Float(command.appearance.opacity)
        layer.setAffineTransform(CGAffineTransform(rotationAngle: command.transform.rotationRadians)
            .scaledBy(x: command.transform.scaleX, y: command.transform.scaleY))
        if let range = command.timeRange, duration > 0 {
            let start = max(0, Double(range.start.value) / Double(range.start.timescale))
            let end = min(duration, start + Double(range.duration.value) / Double(range.duration.timescale))
            if start > 0 || end < duration {
                let animation = CAKeyframeAnimation(keyPath: "opacity")
                var values: [Double] = []
                var keyTimes: [NSNumber] = []
                if start > 0 {
                    values.append(0)
                    keyTimes.append(0)
                }
                values.append(command.appearance.opacity)
                keyTimes.append(NSNumber(value: start / duration))
                if end < duration {
                    values.append(0)
                    keyTimes.append(NSNumber(value: end / duration))
                }
                animation.values = values
                animation.keyTimes = keyTimes
                animation.calculationMode = .discrete
                animation.duration = duration
                animation.beginTime = AVCoreAnimationBeginTimeAtZero
                animation.fillMode = .both
                animation.isRemovedOnCompletion = false
                layer.add(animation, forKey: "visibility")
            }
        }
        return layer
    }

    private static func rasterizedTextLayer(for command: MediaOverlayCommand, size: CGSize) -> CALayer {
        let layer = CALayer()
        let width = max(1, Int(size.width.rounded(.up)))
        let height = max(1, Int(size.height.rounded(.up)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return layer }
        let rect = CGRect(x: 1, y: 1, width: CGFloat(width - 2), height: CGFloat(height - 2))
        let radius = min(8, rect.height / 4)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if let fill = command.appearance.fillRGBA {
            context.addPath(path)
            context.setFillColor(color(fill))
            context.fillPath()
        }
        context.addPath(path)
        context.setStrokeColor(color(command.appearance.strokeRGBA))
        context.setLineWidth(command.appearance.strokeWidth)
        context.strokePath()

        let content = command.content ?? (command.kind == .step ? "•" : "")
        let fitWidth = max(12, (rect.width - 16) / max(1, CGFloat(content.count)) * 1.6)
        let fontSize = min(48, rect.height * 0.4, fitWidth)
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let string = CFAttributedStringCreate(nil, content as CFString, [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color(command.appearance.strokeRGBA),
        ] as CFDictionary)!
        let line = CTLineCreateWithAttributedString(string)
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        context.textPosition = CGPoint(x: (CGFloat(width) - bounds.width) / 2 - bounds.minX,
                                       y: (CGFloat(height) - bounds.height) / 2 - bounds.minY)
        CTLineDraw(line, context)
        layer.contents = context.makeImage()
        layer.contentsGravity = .resize
        return layer
    }

    private static func color(_ components: [Double]) -> CGColor {
        let values = components + Array(repeating: 1, count: max(0, 4 - components.count))
        return CGColor(red: values[0], green: values[1], blue: values[2], alpha: values[3])
    }
}
