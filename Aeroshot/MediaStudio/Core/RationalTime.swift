import CoreMedia
import Foundation

nonisolated enum RationalTimeError: Error, Equatable {
    case invalidDenominator
    case arithmeticOverflow
}

/// An exact, normalized media time. Unlike floating-point seconds this value is
/// stable through repeated edits and Codable round trips.
nonisolated struct RationalTime: Codable, Hashable, Comparable, Sendable {
    let numerator: Int64
    let denominator: Int32

    static let zero = try! RationalTime(0, 1)

    init(_ numerator: Int64, _ denominator: Int32 = 1) throws {
        guard denominator != 0 else { throw RationalTimeError.invalidDenominator }
        let sign: Int64 = denominator < 0 ? -1 : 1
        let positiveDenominator = Int64(denominator).magnitude
        let divisor = Self.gcd(numerator.magnitude, positiveDenominator)
        let normalizedNumerator = numerator / Int64(divisor)
        let normalizedDenominator = positiveDenominator / divisor
        guard normalizedDenominator <= UInt64(Int32.max) else { throw RationalTimeError.arithmeticOverflow }
        let (signedNumerator, overflow) = normalizedNumerator.multipliedReportingOverflow(by: sign)
        guard !overflow else { throw RationalTimeError.arithmeticOverflow }
        self.numerator = signedNumerator
        self.denominator = Int32(normalizedDenominator)
    }

    init(_ time: CMTime) throws {
        guard time.isNumeric, time.timescale != 0 else { throw RationalTimeError.invalidDenominator }
        try self.init(time.value, time.timescale)
    }

    var cmTime: CMTime { CMTime(value: numerator, timescale: denominator) }
    var seconds: Double { Double(numerator) / Double(denominator) }

    static func < (lhs: Self, rhs: Self) -> Bool {
        CMTimeCompare(lhs.cmTime, rhs.cmTime) < 0
    }

    static func + (lhs: Self, rhs: Self) throws -> Self {
        let divisor = Int64(gcd(UInt64(lhs.denominator), UInt64(rhs.denominator)))
        let lhsMultiplier = Int64(rhs.denominator) / divisor
        let rhsMultiplier = Int64(lhs.denominator) / divisor
        let (lhsValue, lhsOverflow) = lhs.numerator.multipliedReportingOverflow(by: lhsMultiplier)
        let (rhsValue, rhsOverflow) = rhs.numerator.multipliedReportingOverflow(by: rhsMultiplier)
        let (sum, sumOverflow) = lhsValue.addingReportingOverflow(rhsValue)
        let (scale, scaleOverflow) = Int64(lhs.denominator).multipliedReportingOverflow(by: lhsMultiplier)
        guard !lhsOverflow, !rhsOverflow, !sumOverflow, !scaleOverflow, scale <= Int64(Int32.max) else {
            throw RationalTimeError.arithmeticOverflow
        }
        return try Self(sum, Int32(scale))
    }

    static func - (lhs: Self, rhs: Self) throws -> Self {
        let (negated, overflow) = rhs.numerator.multipliedReportingOverflow(by: -1)
        guard !overflow else { throw RationalTimeError.arithmeticOverflow }
        return try lhs + Self(negated, rhs.denominator)
    }

    static func * (lhs: Self, rhs: Int64) throws -> Self {
        let (value, overflow) = lhs.numerator.multipliedReportingOverflow(by: rhs)
        guard !overflow else { throw RationalTimeError.arithmeticOverflow }
        return try Self(value, lhs.denominator)
    }

    private static func gcd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        var a = lhs
        var b = rhs
        while b != 0 { (a, b) = (b, a % b) }
        return max(a, 1)
    }
}

nonisolated struct RationalTimeRange: Codable, Hashable, Sendable {
    var start: RationalTime
    var duration: RationalTime

    var end: RationalTime { (try? start + duration) ?? start }
    var isEmpty: Bool { duration <= .zero }

    func contains(_ time: RationalTime, includingEnd: Bool = false) -> Bool {
        time >= start && (includingEnd ? time <= end : time < end)
    }

    func intersection(_ other: Self) -> Self? {
        let lower = max(start, other.start)
        let upper = min(end, other.end)
        guard upper > lower, let duration = try? upper - lower else { return nil }
        return Self(start: lower, duration: duration)
    }
}
