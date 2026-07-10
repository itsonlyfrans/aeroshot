import CoreGraphics
import Foundation

nonisolated final class GIFDeltaEncoder {
    struct Statistics: Equatable { var changedRegionFrameCount = 0 }

    private let handle: FileHandle
    private let width: Int
    private let height: Int
    private let palette: [(UInt8, UInt8, UInt8)]
    private let colorTableSize: Int
    private let minimumCodeSize: Int
    private let preservesTransparency: Bool
    private var previous: [UInt8]?
    private(set) var statistics = Statistics()

    init(url: URL, width: Int, height: Int, settings: GIFExportSettings) throws {
        guard width > 0, height > 0 else { throw GIFCoreError.imageWriteFailed }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else { throw GIFCoreError.imageWriteFailed }
        self.handle = handle
        self.width = width; self.height = height
        preservesTransparency = settings.preservesTransparency
        colorTableSize = Self.nextPowerOfTwo(max(2, min(256, settings.paletteSize)))
        minimumCodeSize = max(2, Int(log2(Double(colorTableSize))))
        palette = Self.makePalette(count: colorTableSize, reservesTransparency: settings.preservesTransparency)
        try writeHeader(loopCount: settings.loop.imageIOLoopCount)
    }

    deinit { try? handle.close() }

    func append(_ image: CGImage, durationMicroseconds: Int64) throws {
        let indexed = try indexedPixels(image)
        let region = changedRegion(current: indexed, previous: previous)
        if Int(region.width) < width || Int(region.height) < height { statistics.changedRegionFrameCount += 1 }
        try writeGraphicControl(delayCentiseconds: max(1, Int((Double(durationMicroseconds) / 10_000).rounded())))
        try writeImageDescriptor(region)
        let regionPixels = pixels(in: region, from: indexed)
        try writeByte(UInt8(minimumCodeSize))
        try writeSubblocks(Self.lzwEncode(regionPixels, minimumCodeSize: minimumCodeSize))
        previous = indexed
    }

    func finish() throws { try writeByte(0x3B); try handle.synchronize(); try handle.close() }

    private func writeHeader(loopCount: Int) throws {
        try write(Data("GIF89a".utf8))
        try writeUInt16(width); try writeUInt16(height)
        let tableBits = UInt8(max(0, minimumCodeSize - 1))
        try writeByte(0x80 | 0x70 | tableBits); try writeByte(0); try writeByte(0)
        for color in palette { try writeByte(color.0); try writeByte(color.1); try writeByte(color.2) }
        if loopCount != 1 {
            try write(Data([0x21, 0xFF, 0x0B])); try write(Data("NETSCAPE2.0".utf8)); try write(Data([0x03, 0x01]))
            try writeUInt16(loopCount == 0 ? 0 : loopCount - 1); try writeByte(0)
        }
    }

    private func writeGraphicControl(delayCentiseconds: Int) throws {
        let transparencyFlag: UInt8 = preservesTransparency ? 1 : 0
        try write(Data([0x21, 0xF9, 0x04, UInt8(1 << 2) | transparencyFlag]))
        try writeUInt16(min(delayCentiseconds, Int(UInt16.max)))
        try writeByte(0); try writeByte(0)
    }

    private func writeImageDescriptor(_ region: CGRect) throws {
        try writeByte(0x2C)
        try writeUInt16(Int(region.minX)); try writeUInt16(Int(region.minY))
        try writeUInt16(Int(region.width)); try writeUInt16(Int(region.height)); try writeByte(0)
    }

    private func indexedPixels(_ image: CGImage) throws -> [UInt8] {
        guard image.width == width, image.height == height else { throw GIFCoreError.imageWriteFailed }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &rgba, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw GIFCoreError.imageWriteFailed }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let opaqueStart = preservesTransparency ? 1 : 0
        return stride(from: 0, to: rgba.count, by: 4).map { offset in
            if preservesTransparency, rgba[offset + 3] < 128 { return 0 }
            var best = opaqueStart, bestDistance = Int.max
            for index in opaqueStart..<palette.count {
                let color = palette[index]
                let dr = Int(rgba[offset]) - Int(color.0), dg = Int(rgba[offset + 1]) - Int(color.1), db = Int(rgba[offset + 2]) - Int(color.2)
                let distance = dr * dr + dg * dg + db * db
                if distance < bestDistance { best = index; bestDistance = distance }
            }
            return UInt8(best)
        }
    }

    private func changedRegion(current: [UInt8], previous: [UInt8]?) -> CGRect {
        guard let previous, previous.count == current.count else { return CGRect(x: 0, y: 0, width: width, height: height) }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for index in current.indices where current[index] != previous[index] {
            let x = index % width, y = index / width
            minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
        }
        return maxX < 0 ? CGRect(x: 0, y: 0, width: 1, height: 1)
            : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func pixels(in region: CGRect, from values: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        for y in Int(region.minY)..<Int(region.maxY) {
            let start = y * width + Int(region.minX), end = y * width + Int(region.maxX)
            result.append(contentsOf: values[start..<end])
        }
        return result
    }

    private static func makePalette(count: Int, reservesTransparency: Bool) -> [(UInt8, UInt8, UInt8)] {
        var result: [(UInt8, UInt8, UInt8)] = reservesTransparency ? [(0, 0, 0)] : []
        let available = count - result.count
        for index in 0..<available {
            let code = index * 255 / max(available - 1, 1)
            let r = UInt8(((code >> 5) & 7) * 255 / 7)
            let g = UInt8(((code >> 2) & 7) * 255 / 7)
            let b = UInt8((code & 3) * 255 / 3)
            result.append((r, g, b))
        }
        while result.count < count { result.append((0, 0, 0)) }
        return result
    }

    private static func nextPowerOfTwo(_ value: Int) -> Int { var result = 2; while result < value { result *= 2 }; return result }

    private static func lzwEncode(_ pixels: [UInt8], minimumCodeSize: Int) -> Data {
        let clear = 1 << minimumCodeSize, end = clear + 1
        var dictionary: [[UInt8]: Int] = [:], next = end + 1, codeSize = minimumCodeSize + 1
        var writer = BitWriter(); writer.write(clear, bits: codeSize)
        guard var sequence = pixels.first.map({ [$0] }) else {
            writer.write(end, bits: codeSize)
            writer.finish()
            return writer.data
        }
        for byte in pixels.dropFirst() {
            let extended = sequence + [byte]
            if dictionary[extended] != nil { sequence = extended; continue }
            writer.write(sequence.count == 1 ? Int(sequence[0]) : dictionary[sequence]!, bits: codeSize)
            if next < 4096 {
                dictionary[extended] = next; next += 1
                if next == (1 << codeSize), codeSize < 12 { codeSize += 1 }
            } else {
                writer.write(clear, bits: codeSize); dictionary.removeAll(keepingCapacity: true); next = end + 1; codeSize = minimumCodeSize + 1
            }
            sequence = [byte]
        }
        writer.write(sequence.count == 1 ? Int(sequence[0]) : dictionary[sequence]!, bits: codeSize)
        writer.write(end, bits: codeSize)
        writer.finish()
        return writer.data
    }

    private func writeSubblocks(_ data: Data) throws {
        var offset = 0
        while offset < data.count { let count = min(255, data.count - offset); try writeByte(UInt8(count)); try write(data.subdata(in: offset..<(offset + count))); offset += count }
        try writeByte(0)
    }
    private func writeUInt16(_ value: Int) throws {
        let value = UInt16(clamping: value)
        try write(Data([UInt8(value & 0xff), UInt8(value >> 8)]))
    }
    private func writeByte(_ value: UInt8) throws { try write(Data([value])) }
    private func write(_ data: Data) throws { try handle.write(contentsOf: data) }
}

private nonisolated struct BitWriter {
    var data = Data(); private var accumulator = 0; private var bitCount = 0
    mutating func write(_ code: Int, bits: Int) {
        accumulator |= code << bitCount; bitCount += bits
        while bitCount >= 8 { data.append(UInt8(accumulator & 0xff)); accumulator >>= 8; bitCount -= 8 }
    }
    mutating func finish() {
        if bitCount > 0 { data.append(UInt8(accumulator & 0xff)) }
        accumulator = 0
        bitCount = 0
    }
}
