import Foundation

enum WP09Benchmark {
    static func samples(count: Int, operation: () throws -> Void) rethrows -> [Double] {
        var values: [Double] = []
        values.reserveCapacity(count)
        for _ in 0..<count {
            let start = ContinuousClock.now
            try operation()
            values.append(milliseconds(ContinuousClock.now - start))
        }
        return values
    }

    static func milliseconds(_ duration: Duration) -> Double {
        let c = duration.components
        return Double(c.seconds) * 1_000 + Double(c.attoseconds) / 1_000_000_000_000_000
    }

    static func percentile(_ p: Double, of values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let rank = max(1, Int(ceil(p * Double(sorted.count))))
        return sorted[min(rank - 1, sorted.count - 1)]
    }

    static func emit(_ name: String, values: [Double], state: String) {
        let raw = values.map { String(format: "%.3f", $0) }.joined(separator: ",")
        print("WP09_METRIC name=\(name) unit=ms n=\(values.count) state=\(state) p50=\(String(format: "%.3f", percentile(0.50, of: values))) p95=\(String(format: "%.3f", percentile(0.95, of: values))) raw=[\(raw)]")
    }
}
