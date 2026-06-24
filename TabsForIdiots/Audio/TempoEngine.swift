import Foundation

@MainActor
final class TempoEngine: ObservableObject {
    @Published var currentStrokeIndex: Int = 0
    @Published var isRunning: Bool = false

    private var timer: Timer?
    private var strokeCount: Int = 4

    // Each stroke = (beatsPerMeasure * 60 / bpm) / strokeCount seconds.
    // Assumes 4/4 time.
    func start(bpm: Double, strokeCount: Int) {
        guard bpm > 0, strokeCount > 0 else { return }
        stop()
        self.strokeCount = strokeCount
        let interval = (4.0 * 60.0 / bpm) / Double(strokeCount)
        currentStrokeIndex = 0
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.currentStrokeIndex = (self.currentStrokeIndex + 1) % strokeCount
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        currentStrokeIndex = 0
    }
}
