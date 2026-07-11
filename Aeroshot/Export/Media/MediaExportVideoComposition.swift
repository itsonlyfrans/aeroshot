@preconcurrency import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import QuartzCore

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
        let transformed = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform).standardized
        let crop = snapshot.canvas.crop
        let cropped = CGRect(x: transformed.minX + crop.x * transformed.width,
                             y: transformed.minY + crop.y * transformed.height,
                             width: crop.width * transformed.width,
                             height: crop.height * transformed.height)
        let scale = min(outputSize.width / cropped.width, outputSize.height / cropped.height)
        let fitted = CGSize(width: cropped.width * scale, height: cropped.height * scale)
        let translation = CGAffineTransform(
            translationX: (outputSize.width - fitted.width) / 2 - cropped.minX * scale,
            y: (outputSize.height - fitted.height) / 2 - cropped.minY * scale
        )
        layerInstruction.setTransform(preferredTransform.concatenating(CGAffineTransform(scaleX: scale, y: scale)).concatenating(translation), at: .zero)
        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: outputSize)
        let parentLayer = CALayer()
        parentLayer.frame = videoLayer.frame
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
