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

    func outputTransform(to destination: MediaCropLayout) -> CGAffineTransform? {
        guard scale > 0, destination.scale.isFinite else { return nil }
        let scale = destination.scale / scale
        guard scale.isFinite else { return nil }
        return .init(a: scale, b: 0, c: 0, d: scale,
                     tx: destination.transformedSourceRect.minX - transformedSourceRect.minX * scale,
                     ty: destination.transformedSourceRect.minY - transformedSourceRect.minY * scale)
    }

    func calayerTransform(to destination: MediaCropLayout) -> CGAffineTransform? {
        guard let transform = outputTransform(to: destination) else { return nil }
        let yAxis = outputRect.minY + outputRect.maxY
        return .init(a: transform.a, b: -transform.b, c: -transform.c, d: transform.d,
                     tx: transform.tx + transform.c * yAxis,
                     ty: yAxis * (1 - transform.d) - transform.ty)
    }
}

nonisolated enum MediaExportVideoComposition {
    static func make(
        asset: AVAsset,
        snapshot: MediaExportSnapshot,
        preset: MediaExportPreset
    ) async throws -> AVMutableVideoComposition {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = videoTracks.first else {
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

        guard let transformed = MediaSourceGeometry.orientedRect(
            naturalSize: naturalSize, preferredTransform: preferredTransform
        ) else { throw MediaExportError.invalidResolution }
        let baseCrop = snapshot.canvas.crop
        let punchEvents = snapshot.effects.events.filter { event in
            event.kind == .click && snapshot.effects.punchInClickTimes.contains(event.timeMicroseconds)
        }
        let timing = MediaOutputTiming(freezeFrame: snapshot.effects.freezeFrame)
        let shiftedPunches = punchEvents.map { event -> (RecordedEffectEvent, Double) in
            (event, Double(timing.outputTimeMicroseconds(forSourceTime: event.timeMicroseconds)) / 1_000_000)
        }
        let punchInDuration = Double(MediaOutputTiming.punchInDurationMicroseconds) / 1_000_000
        let boundaries = ([0, duration.seconds] + shiftedPunches.flatMap { [$0.1, min(duration.seconds, $0.1 + punchInDuration)] })
            .filter { $0 >= 0 && $0 <= duration.seconds }.sorted()
        let uniqueBoundaries = boundaries.enumerated().compactMap { index, value in
            index == 0 || value > boundaries[index - 1] ? value : nil
        }
        var instructions: [AVMutableVideoCompositionInstruction] = []
        for (index, start) in uniqueBoundaries.dropLast().enumerated() {
            let end = uniqueBoundaries[index + 1]
            guard end > start else { continue }
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = .init(start: CMTime(seconds: start, preferredTimescale: 600),
                                          duration: CMTime(seconds: end - start, preferredTimescale: 600))
            let punch = timing.activePunchIn(in: punchEvents, atOutputTime: Int64(start * 1_000_000))
            let crop = timing.crop(baseCrop, for: punch)
            let mainInstruction = try layerInstruction(for: track, naturalSize: naturalSize,
                preferredTransform: preferredTransform, sourceRect: transformed,
                outputRect: CGRect(origin: .zero, size: outputSize), crop: crop)
            var layers = [mainInstruction]
            if snapshot.effects.webcam.isEnabled, let webcamTrack = videoTracks.dropFirst().first {
                let webcamSize = try await webcamTrack.load(.naturalSize)
                let webcamTransform = try await webcamTrack.load(.preferredTransform)
                if let webcamRect = MediaSourceGeometry.orientedRect(naturalSize: webcamSize, preferredTransform: webcamTransform) {
                    let corner = snapshot.effects.webcam.corner
                    let frame = webcamFrame(outputSize: outputSize, corner: corner,
                                            isCircular: snapshot.effects.webcam.isCircular)
                    let webcamInstruction = try layerInstruction(for: webcamTrack, naturalSize: webcamSize,
                        preferredTransform: webcamTransform, sourceRect: webcamRect, outputRect: frame, crop: .full)
                    layers.insert(webcamInstruction, at: 0)
                }
            }
            instruction.layerInstructions = layers
            instructions.append(instruction)
        }
        composition.instructions = instructions

        guard let layout = MediaCropLayout.make(sourceRect: transformed, outputRect: CGRect(origin: .zero, size: outputSize),
                                                 normalizedCrop: CGRect(x: baseCrop.x, y: baseCrop.y, width: baseCrop.width, height: baseCrop.height))
        else { throw MediaExportError.invalidResolution }

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
        var videoLayers = [videoLayer]
        if snapshot.effects.webcam.isEnabled, videoTracks.count > 1 {
            let frame = webcamFrame(outputSize: outputSize, corner: snapshot.effects.webcam.corner,
                                    isCircular: snapshot.effects.webcam.isCircular)
            let webcamLayer = CALayer()
            webcamLayer.frame = frame
            if snapshot.effects.webcam.isCircular {
                let mask = CAShapeLayer()
                mask.path = CGPath(ellipseIn: webcamLayer.bounds, transform: nil)
                mask.fillColor = CGColor(gray: 1, alpha: 1)
                webcamLayer.mask = mask
            }
            parentLayer.addSublayer(webcamLayer)
            videoLayers.append(webcamLayer)
        }
        let commands = MediaOverlayCompiler.compile(snapshot)
        for command in commands where command.content?.hasPrefix("effect.") != true {
            parentLayer.addSublayer(try layer(for: command, outputSize: outputSize, duration: duration.seconds))
        }
        let effectCommands = commands.filter { $0.content?.hasPrefix("effect.") == true }
        if !effectCommands.isEmpty {
            let effectsLayer = CALayer()
            effectsLayer.bounds = CGRect(origin: .zero, size: outputSize)
            effectsLayer.anchorPoint = .zero
            effectsLayer.position = .zero
            for command in effectCommands {
                effectsLayer.addSublayer(try layer(for: command, outputSize: outputSize, duration: duration.seconds))
            }
            if let animation = effectTransformAnimation(baseLayout: layout, sourceRect: transformed,
                                                        outputRect: CGRect(origin: .zero, size: outputSize), baseCrop: baseCrop,
                                                        timing: timing, punchEvents: punchEvents,
                                                        boundaries: uniqueBoundaries, duration: duration.seconds) {
                effectsLayer.add(animation, forKey: "punchInCrop")
            }
            parentLayer.addSublayer(effectsLayer)
        }
        composition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayers: videoLayers, in: parentLayer)
        return composition
    }

    private static func effectTransformAnimation(baseLayout: MediaCropLayout, sourceRect: CGRect, outputRect: CGRect,
                                                 baseCrop: AeroNormalizedRect, timing: MediaOutputTiming,
                                                 punchEvents: [RecordedEffectEvent], boundaries: [Double],
                                                 duration: Double) -> CAKeyframeAnimation? {
        guard duration > 0, !punchEvents.isEmpty else { return nil }
        let transforms = boundaries.compactMap { time -> CGAffineTransform? in
            let punch = timing.activePunchIn(in: punchEvents, atOutputTime: Int64(time * 1_000_000))
            let crop = timing.crop(baseCrop, for: punch)
            guard let layout = MediaCropLayout.make(sourceRect: sourceRect, outputRect: outputRect,
                                                     normalizedCrop: CGRect(x: crop.x, y: crop.y,
                                                                            width: crop.width, height: crop.height)) else { return nil }
            return baseLayout.calayerTransform(to: layout)
        }
        guard transforms.count == boundaries.count else { return nil }
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = transforms.map { NSValue(caTransform3D: CATransform3DMakeAffineTransform($0)) }
        animation.keyTimes = boundaries.map { NSNumber(value: $0 / duration) }
        animation.calculationMode = .discrete
        animation.duration = duration
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        return animation
    }

    private static func layerInstruction(for track: AVAssetTrack, naturalSize: CGSize, preferredTransform: CGAffineTransform,
                                         sourceRect: CGRect, outputRect: CGRect, crop: AeroNormalizedRect) throws -> AVMutableVideoCompositionLayerInstruction {
        guard let layout = MediaCropLayout.make(sourceRect: sourceRect, outputRect: outputRect,
                                                normalizedCrop: CGRect(x: crop.x, y: crop.y, width: crop.width, height: crop.height)) else {
            throw MediaExportError.invalidResolution
        }
        let instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        let translation = CGAffineTransform(translationX: layout.sourceTranslation.x, y: layout.sourceTranslation.y)
        instruction.setTransform(preferredTransform.concatenating(CGAffineTransform(scaleX: layout.scale, y: layout.scale)).concatenating(translation), at: .zero)
        return instruction
    }

    static func webcamFrame(outputSize: CGSize, corner: String, isCircular: Bool) -> CGRect {
        let side = min(outputSize.width, outputSize.height) * 0.24
        let size = isCircular ? CGSize(width: side, height: side) : CGSize(width: side, height: side * 0.75)
        let inset = min(outputSize.width, outputSize.height) * 0.04
        return CGRect(x: corner.contains("L") ? inset : outputSize.width - inset - size.width,
                      y: corner.contains("T") ? inset : outputSize.height - inset - size.height,
                      width: size.width, height: size.height)
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
        layer.contents = MediaTextOverlayRasterizer.render(command: command, size: size)
        layer.contentsGravity = .resize
        return layer
    }

    private static func color(_ components: [Double]) -> CGColor {
        let values = components + Array(repeating: 1, count: max(0, 4 - components.count))
        return CGColor(red: values[0], green: values[1], blue: values[2], alpha: values[3])
    }
}

nonisolated enum MediaTextOverlayRasterizer {
    static func render(command: MediaOverlayCommand, size: CGSize) -> CGImage? {
        let width = max(1, Int(size.width.rounded(.up)))
        let height = max(1, Int(size.height.rounded(.up)))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: 1, y: 1, width: CGFloat(max(0, width - 2)), height: CGFloat(max(0, height - 2)))
        let radius = min(rect.width, rect.height) * 0.08
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
        let textRect = rect.insetBy(dx: max(4, rect.width * 0.06), dy: max(3, rect.height * 0.08))
        var alignment = CTTextAlignment.center
        var lineBreak = CTLineBreakMode.byWordWrapping
        let paragraph = withUnsafePointer(to: &alignment) { alignmentPointer in
            withUnsafePointer(to: &lineBreak) { lineBreakPointer in
                let settings = [
                    CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: alignmentPointer),
                    CTParagraphStyleSetting(spec: .lineBreakMode, valueSize: MemoryLayout<CTLineBreakMode>.size, value: lineBreakPointer),
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
        let fontSize = fittedFontSize(content: content, paragraph: paragraph, rect: textRect)
        let attributed = attributedString(content: content, fontSize: fontSize, paragraph: paragraph,
                                          color: color(command.appearance.strokeRGBA))
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(), CGPath(rect: textRect, transform: nil), nil), context)
        return context.makeImage()
    }

    private static func fittedFontSize(content: String, paragraph: CTParagraphStyle, rect: CGRect) -> CGFloat {
        guard rect.width > 0, rect.height > 0 else { return 1 }
        var low: CGFloat = 1
        var high = max(1, rect.height * 0.6)
        for _ in 0..<8 {
            let candidate = (low + high) / 2
            let framesetter = CTFramesetterCreateWithAttributedString(
                attributedString(content: content, fontSize: candidate, paragraph: paragraph, color: CGColor(gray: 1, alpha: 1))
            )
            let measured = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter, CFRange(), nil, CGSize(width: rect.width, height: .greatestFiniteMagnitude), nil
            )
            if measured.height <= rect.height { low = candidate } else { high = candidate }
        }
        return low
    }

    private static func attributedString(
        content: String, fontSize: CGFloat, paragraph: CTParagraphStyle, color: CGColor
    ) -> CFAttributedString {
        NSAttributedString(string: content, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil),
            kCTForegroundColorAttributeName as NSAttributedString.Key: color,
            kCTParagraphStyleAttributeName as NSAttributedString.Key: paragraph,
        ])
    }

    private static func color(_ components: [Double]) -> CGColor {
        let values = components + Array(repeating: 1, count: max(0, 4 - components.count))
        return CGColor(red: values[0], green: values[1], blue: values[2], alpha: values[3])
    }
}
