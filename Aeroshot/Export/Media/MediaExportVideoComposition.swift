@preconcurrency import AVFoundation
import CoreGraphics
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
        let scale = min(outputSize.width / transformed.width, outputSize.height / transformed.height)
        let fitted = CGSize(width: transformed.width * scale, height: transformed.height * scale)
        let translation = CGAffineTransform(
            translationX: (outputSize.width - fitted.width) / 2 - transformed.minX * scale,
            y: (outputSize.height - fitted.height) / 2 - transformed.minY * scale
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
            let text = CATextLayer()
            text.string = command.kind == .step ? "•" : ""
            text.alignmentMode = .center
            text.fontSize = max(12, frame.height * 0.6)
            text.foregroundColor = color(command.appearance.strokeRGBA)
            text.contentsScale = 2
            layer = text
        } else {
            let shape = CAShapeLayer()
            let path = CGMutablePath()
            if command.points.count > 1 {
                let first = command.points[0]
                path.move(to: CGPoint(x: first.x * frame.width, y: (1 - first.y) * frame.height))
                for point in command.points.dropFirst() {
                    path.addLine(to: CGPoint(x: point.x * frame.width, y: (1 - point.y) * frame.height))
                }
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
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            animation.values = [0, command.appearance.opacity, command.appearance.opacity, 0]
            animation.keyTimes = [0, NSNumber(value: start / duration), NSNumber(value: end / duration), 1]
            animation.duration = duration
            animation.beginTime = AVCoreAnimationBeginTimeAtZero
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: "visibility")
        }
        return layer
    }

    private static func color(_ components: [Double]) -> CGColor {
        let values = components + Array(repeating: 1, count: max(0, 4 - components.count))
        return CGColor(red: values[0], green: values[1], blue: values[2], alpha: values[3])
    }
}
