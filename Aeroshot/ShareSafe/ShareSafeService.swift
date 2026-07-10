import AppKit
import CoreGraphics

enum ShareSafeRedactionStyle: String, CaseIterable, Identifiable {
    case blur
    case pixelate
    case solid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blur: return "Blur"
        case .pixelate: return "Pixelate"
        case .solid: return "Redact"
        }
    }

    var annotationKind: AnnotationKind {
        switch self {
        case .blur: return .redactBlur
        case .pixelate: return .redactPixelate
        case .solid: return .redactSolid
        }
    }
}

struct ShareSafeResult: Sendable {
    let image: CGImage
    let matchCount: Int
}

/// The only outcomes Share Safe is allowed to take after scanning. A scan error is
/// deliberately distinct from a clean result: we cannot safely infer that an image
/// contains no sensitive data when it has not been scanned.
nonisolated enum ShareSafeShareAction: Equatable {
    case shareOriginal
    case shareRedacted
    case block
}

enum ShareSafeService {
    nonisolated private static let lineMergeThreshold: CGFloat = 8

    /// Scan the image for sensitive text regions and bake redactions.
    nonisolated static func process(
        image: CGImage,
        style: ShareSafeRedactionStyle,
        useSmartScan: Bool,
        usePrivacyFilter: Bool = false
    ) async throws -> ShareSafeResult {
        let rects = try await detectSensitiveRects(in: image, useSmartScan: useSmartScan, usePrivacyFilter: usePrivacyFilter)
        let redacted = await bakeRedactions(on: image, rects: rects, style: style)
        return ShareSafeResult(image: redacted, matchCount: rects.count)
    }

    nonisolated static func detectSensitiveRects(
        in image: CGImage,
        useSmartScan: Bool = false,
        usePrivacyFilter: Bool = false
    ) async throws -> [CGRect] {
        let observations = try await OCRService.recognizeObservations(in: image)
        let lineGroups = groupObservationsByLine(observations)
        let lineTexts = lineGroups.map { $0.map(\.text).joined(separator: " ") }
        let flagged = await sensitiveLineIndices(from: lineTexts, useSmartScan: useSmartScan, usePrivacyFilter: usePrivacyFilter)
        let bounds = CGRect(origin: .zero, size: CGSize(width: image.width, height: image.height))
        return rects(for: lineGroups, flaggedIndices: flagged, bounds: bounds)
    }

    /// Chooses whether sharing can proceed after a scan. Scan failures always fail
    /// closed, preventing an unverified original from being passed to the share sheet.
    nonisolated static func shareAction(
        scanSucceeded: Bool,
        matchCount: Int,
        redactBeforeSharing: Bool
    ) -> ShareSafeShareAction {
        guard scanSucceeded else { return .block }
        guard matchCount > 0, redactBeforeSharing else { return .shareOriginal }
        return .shareRedacted
    }

    /// Pattern matching plus optional on-device model reviews (Apple Intelligence
    /// and/or the OpenAI privacy filter), all funneled through the same line policy.
    nonisolated static func sensitiveLineIndices(
        from lineTexts: [String],
        useSmartScan: Bool,
        usePrivacyFilter: Bool = false
    ) async -> Set<Int> {
        var flagged = Set<Int>()
        for (index, text) in lineTexts.enumerated() where PIIDetector.lineShouldBeRedacted(text) {
            flagged.insert(index)
        }

        var smartScanFindings: [SmartScanFinding] = []
        var privacyFilterFindings: [SmartScanFinding] = []
        if useSmartScan {
            smartScanFindings = await ShareSafeSmartScanSupport.findings(lineTexts: lineTexts)
        }
        if usePrivacyFilter,
           ShareSafeLinePolicy.needsPrivacyFilterReview(lineTexts: lineTexts, patternMatched: flagged) {
            privacyFilterFindings = await PrivacyFilterScanner.shared.findings(lineTexts: lineTexts)
        }
        if !smartScanFindings.isEmpty {
            flagged.formUnion(ShareSafeLinePolicy.filterSmartScanFindings(
                smartScanFindings,
                lineTexts: lineTexts,
                patternMatched: flagged
            ))
        }
        if !privacyFilterFindings.isEmpty {
            flagged.formUnion(ShareSafeLinePolicy.filterPrivacyFilterFindings(
                privacyFilterFindings,
                lineTexts: lineTexts,
                patternMatched: flagged
            ))
        }

        let aiFindings = smartScanFindings + privacyFilterFindings
        flagged.formUnion(ShareSafeLinePolicy.corroboratedMediumLines(
            lineTexts: lineTexts,
            flagged: flagged,
            aiFindings: aiFindings
        ))

        return ShareSafeLinePolicy.expandForLabeledFieldValues(
            ShareSafeLinePolicy.expandForContinuations(flagged, lineTexts: lineTexts),
            lineTexts: lineTexts
        )
    }

    nonisolated static func rects(
        for lineGroups: [[OCRTextObservation]],
        flaggedIndices: Set<Int>,
        bounds: CGRect
    ) -> [CGRect] {
        var rects: [CGRect] = []

        for (index, group) in lineGroups.enumerated() {
            guard flaggedIndices.contains(index) else { continue }

            let partial = partialRedactionRects(in: group)
            if !partial.isEmpty {
                let lineText = group
                    .sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                    .map(\.text)
                    .joined(separator: " ")
                let horizontalPadding: CGFloat = PIIDetector.envAssignmentValueRange(in: lineText) == nil ? -8 : 0
                rects.append(contentsOf: partial.compactMap { rect in
                    // Partial ranges already map to the exact sensitive characters.
                    // Expanding horizontally can cover a preceding `.env` variable
                    // name (for example, `AWS_ACCESS_KEY_ID=`), which is useful
                    // non-sensitive context that should remain readable.
                    let padded = rect.insetBy(dx: horizontalPadding, dy: -10).intersection(bounds)
                    return padded.isEmpty ? nil : padded
                })
                continue
            }

            // No in-line range (label-adjacent value, continuation fragment, AI-flagged
            // line): redact the value observations wholesale.
            for observation in ShareSafeLinePolicy.redactableObservations(in: group) {
                let padded = observation.boundingBox.insetBy(dx: -12, dy: -10).intersection(bounds)
                if !padded.isEmpty { rects.append(padded) }
            }
        }

        return mergeRects(rects)
    }

    /// Redact only the sensitive character ranges of a flagged line, so surrounding
    /// copy ("Deploy complete — ping … if issues") stays readable. Ranges come from
    /// pattern matching on the joined line text; when the line is a labeled contact
    /// field with no pattern match ("Name Jordan Alvarez"), the value portion is used.
    nonisolated static func partialRedactionRects(in group: [OCRTextObservation]) -> [CGRect] {
        guard !group.isEmpty else { return [] }
        let sorted = group.sorted { $0.boundingBox.minX < $1.boundingBox.minX }

        // Joined line text with each observation's UTF-16 span.
        var lineText = ""
        var segments: [(observation: OCRTextObservation, span: Range<Int>)] = []
        for observation in sorted {
            if !lineText.isEmpty { lineText += " " }
            let start = lineText.utf16.count
            lineText += observation.text
            segments.append((observation, start..<lineText.utf16.count))
        }

        let ranges = PIIDetector.redactionRanges(in: lineText)
        guard !ranges.isEmpty else { return [] }

        var rects: [CGRect] = []
        for range in ranges {
            let lower = range.lowerBound.utf16Offset(in: lineText)
            var upper = range.upperBound.utf16Offset(in: lineText)
            // Vision splits some tokens ("support@company" + ".internal"); when a match
            // runs to the end of a segment and the next segment is a dot/at fragment of
            // the same token, absorb it so no tail of the value stays visible.
            while let currentIndex = segments.firstIndex(where: { $0.span.contains(upper - 1) }),
                  upper >= segments[currentIndex].span.upperBound - 1,
                  currentIndex + 1 < segments.count,
                  segments[currentIndex + 1].observation.text.range(
                      of: #"^[.@][A-Za-z0-9._%@-]+$"#, options: .regularExpression
                  ) != nil {
                upper = segments[currentIndex + 1].span.upperBound
            }
            for segment in segments {
                let overlapStart = max(lower, segment.span.lowerBound)
                let overlapEnd = min(upper, segment.span.upperBound)
                guard overlapStart < overlapEnd else { continue }

                let box = segment.observation.boundingBox
                let length = CGFloat(segment.span.count)
                var startFraction = CGFloat(overlapStart - segment.span.lowerBound) / length
                var endFraction = CGFloat(overlapEnd - segment.span.lowerBound) / length
                // Character-proportional interpolation is approximate; snap near-edges
                // to the box edge so glyph-width variance can't leave a sliver visible.
                if startFraction < 0.08 { startFraction = 0 }
                if endFraction > 0.92 { endFraction = 1 }

                rects.append(CGRect(
                    x: box.minX + startFraction * box.width,
                    y: box.minY,
                    width: (endFraction - startFraction) * box.width,
                    height: box.height
                ))
            }
        }
        return rects
    }

    /// Merge OCR tokens that Vision split onto the same visual line (e.g. email + TLD).
    nonisolated static func groupObservationsByLine(_ observations: [OCRTextObservation]) -> [[OCRTextObservation]] {
        guard !observations.isEmpty else { return [] }
        let sorted = observations.sorted { lhs, rhs in
            if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 1 {
                return lhs.boundingBox.midY < rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        var groups: [[OCRTextObservation]] = []
        var current: [OCRTextObservation] = [sorted[0]]

        for observation in sorted.dropFirst() {
            let previous = current.last!
            let yDelta = abs(observation.boundingBox.midY - previous.boundingBox.midY)
            let lineHeight = max(previous.boundingBox.height, observation.boundingBox.height, 1)
            if yDelta <= max(lineMergeThreshold, lineHeight * 0.6) {
                current.append(observation)
            } else {
                groups.append(current)
                current = [observation]
            }
        }
        groups.append(current)
        return groups
    }

    @MainActor
    static func shareSafe(
        image: CGImage,
        fileURL: URL?,
        from view: NSView?,
        style: ShareSafeRedactionStyle,
        useSmartScan: Bool,
        usePrivacyFilter: Bool = false,
        redactBeforeSharing: Bool
    ) async {
        let scanningLabel: String
        if usePrivacyFilter && PrivacyFilterModel.isDownloaded {
            scanningLabel = "Scanning with privacy filter…"
        } else if useSmartScan && ShareSafeSmartScanSupport.isModelAvailable {
            scanningLabel = "Scanning with Apple Intelligence…"
        } else {
            scanningLabel = "Scanning for sensitive data…"
        }
        ToastController.shared.show(scanningLabel, symbol: "shield.checkered")

        do {
            let rects = try await detectSensitiveRects(in: image, useSmartScan: useSmartScan, usePrivacyFilter: usePrivacyFilter)
            let matchCount = rects.count

            switch shareAction(scanSucceeded: true, matchCount: matchCount, redactBeforeSharing: redactBeforeSharing) {
            case .shareOriginal where matchCount == 0:
                ToastController.shared.show("No sensitive data found", symbol: "checkmark.shield")
                ShareService.shareImage(image, fileURL: fileURL, from: view)
                return
            case .shareOriginal:
                ToastController.shared.show(
                    "Found \(matchCount) sensitive item\(matchCount == 1 ? "" : "s") — shared without redaction",
                    symbol: "checkmark.shield"
                )
                ShareService.shareImage(image, fileURL: fileURL, from: view)
                return
            case .shareRedacted:
                let redacted = bakeRedactions(on: image, rects: rects, style: style)
                ToastController.shared.show(
                    "Redacted \(matchCount) sensitive item\(matchCount == 1 ? "" : "s")",
                    symbol: "checkmark.shield"
                )
                ShareService.shareImage(redacted, fileURL: nil, from: view)
            case .block:
                assertionFailure("A successful scan must not produce a blocked share action")
            }
        } catch {
            // Fail closed: the original image has not been verified safe to share.
            ToastController.shared.show(
                "Share Safe couldn't scan — original not shared. Try again.",
                symbol: "exclamationmark.triangle"
            )
        }
    }

    @MainActor
    private static func bakeRedactions(on image: CGImage, rects: [CGRect], style: ShareSafeRedactionStyle) -> CGImage {
        guard !rects.isEmpty else { return image }
        let document = EditorDocument(image: image)
        document.annotations = rects.map { rect in
            Annotation(
                kind: style.annotationKind,
                points: [rect.origin, CGPoint(x: rect.maxX, y: rect.maxY)],
                lineWidth: 0
            )
        }
        return document.renderFinal() ?? image
    }

    nonisolated private static func mergeRects(_ rects: [CGRect]) -> [CGRect] {
        var merged = rects
        var changed = true
        while changed {
            changed = false
            outer: for i in 0..<merged.count {
                for j in (i + 1)..<merged.count {
                    if merged[i].intersects(merged[j]) {
                        merged[i] = merged[i].union(merged[j])
                        merged.remove(at: j)
                        changed = true
                        break outer
                    }
                }
            }
        }
        return merged
    }
}
