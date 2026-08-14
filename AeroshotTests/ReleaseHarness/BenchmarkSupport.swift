import AppKit
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

    @MainActor
    static func emit(
        _ name: String,
        values: [Double],
        state: String,
        fixture: String,
        fixtureChecksum: String
    ) {
        let environment = ProcessInfo.processInfo.environment
        let screen = NSScreen.main
        let display = screen.map {
            let pixels = CGSize(width: $0.frame.width * $0.backingScaleFactor,
                                height: $0.frame.height * $0.backingScaleFactor)
            return "\(Int(pixels.width))x\(Int(pixels.height))@\($0.backingScaleFactor)x \($0.colorSpace?.localizedName ?? "unknown")"
        } ?? "UNVERIFIED"
#if DEBUG
        let defaultConfiguration = "Debug"
#else
        let defaultConfiguration = "Release"
#endif
        let metadata = [
            "backgroundLoad": environment["AEROSHOT_BENCH_BACKGROUND_LOAD"] ?? "UNVERIFIED",
            "buildConfiguration": environment["CONFIGURATION"] ?? defaultConfiguration,
            "cpu": environment["AEROSHOT_BENCH_CPU"] ?? "\(ProcessInfo.processInfo.processorCount) logical cores",
            "display": environment["AEROSHOT_BENCH_DISPLAY"] ?? display,
            "evidenceState": environment["AEROSHOT_BENCH_EVIDENCE_STATE"] ?? "NOT MEASURED",
            "fixture": fixture,
            "fixtureChecksum": fixtureChecksum,
            "gpu": environment["AEROSHOT_BENCH_GPU"] ?? "UNVERIFIED",
            "machineModel": environment["AEROSHOT_BENCH_MACHINE_MODEL"] ?? "UNVERIFIED",
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "memoryBytes": String(ProcessInfo.processInfo.physicalMemory),
            "percentileMethod": "nearest-rank",
            "powerSource": environment["AEROSHOT_BENCH_POWER_SOURCE"] ?? "UNVERIFIED",
            "revision": environment["AEROSHOT_BENCH_REVISION"] ?? "UNVERIFIED",
            "thermalState": thermalStateName,
            "workingCopy": environment["AEROSHOT_BENCH_WORKING_COPY"] ?? "UNVERIFIED",
            "xcode": environment["XCODE_VERSION_ACTUAL"] ?? "UNVERIFIED",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            print("WP09_ENV \(json)")
        }
        let raw = values.map { String(format: "%.3f", $0) }.joined(separator: ",")
        let p99 = values.count >= 100
            ? " p99=\(String(format: "%.3f", percentile(0.99, of: values)))"
            : ""
        print("WP09_METRIC name=\(name) unit=ms n=\(values.count) state=\(state) min=\(String(format: "%.3f", values.min() ?? 0)) p50=\(String(format: "%.3f", percentile(0.50, of: values))) p95=\(String(format: "%.3f", percentile(0.95, of: values)))\(p99) max=\(String(format: "%.3f", values.max() ?? 0)) raw=[\(raw)]")
    }

    private static var thermalStateName: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}
