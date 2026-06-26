import Foundation

@MainActor
final class TempoEngine: ObservableObject {
    @Published var currentStrokeIndex: Int = 0
    @Published var isRunning: Bool = false

    private var runTask: Task<Void, Never>?

    // intervals: quarter-note duration per stroke (empty = equal across 4 beats).
    func start(bpm: Double, strokeCount: Int, intervals: [Double] = []) {
        guard bpm > 0, strokeCount > 0 else { return }
        stop()

        let beatSeconds = 60.0 / bpm
        let resolved: [Double]
        if intervals.count == strokeCount {
            resolved = intervals.map { $0 * beatSeconds }
        } else {
            let equal = 4.0 * beatSeconds / Double(strokeCount)
            resolved = Array(repeating: equal, count: strokeCount)
        }

        currentStrokeIndex = 0
        isRunning = true

        runTask = Task { @MainActor in
            while !Task.isCancelled {
                let sleepNS = UInt64(max(0.01, resolved[currentStrokeIndex]) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: sleepNS)
                guard !Task.isCancelled else { break }
                currentStrokeIndex = (currentStrokeIndex + 1) % strokeCount
            }
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
        currentStrokeIndex = 0
    }
}
