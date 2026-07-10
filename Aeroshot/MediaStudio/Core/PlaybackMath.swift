import Foundation

nonisolated enum PlaybackMathError: Error, Equatable { case invalidFrameRate }

nonisolated enum TransportIntent: Sendable { case playReverse, pause, playForward }

nonisolated struct TransportState: Equatable, Sendable {
    var rate: Float = 0

    func applying(_ intent: TransportIntent) -> Self {
        switch intent {
        case .pause: Self(rate: 0)
        case .playForward: Self(rate: rate > 0 ? min(rate * 2, 8) : 1)
        case .playReverse: Self(rate: rate < 0 ? max(rate * 2, -8) : -1)
        }
    }
}

nonisolated enum PlaybackMath {
    static func frameStep(frameRate: RationalTime) throws -> RationalTime {
        guard frameRate > .zero, frameRate.numerator <= Int64(Int32.max) else { throw PlaybackMathError.invalidFrameRate }
        return try RationalTime(Int64(frameRate.denominator), Int32(frameRate.numerator))
    }

    static func timecode(_ time: RationalTime, frameRate: RationalTime) -> String {
        guard time >= .zero, frameRate > .zero else { return "00:00:00:00" }
        let nominalRate = max(1, Int(frameRate.seconds.rounded()))
        let totalFrames = Int((time.seconds * frameRate.seconds).rounded(.down))
        let frames = totalFrames % nominalRate
        let totalSeconds = totalFrames / nominalRate
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3_600
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }
}
