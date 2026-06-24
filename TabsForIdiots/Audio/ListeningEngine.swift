import AVFoundation
import Accelerate

@MainActor
class ListeningEngine: ObservableObject {
    @Published var rawChord: String? = nil
    @Published var rawConfidence: Float = 0.0
    @Published var stableChord: String? = nil
    @Published var stableConfidence: Float = 0.0
    @Published var isRunning = false

    private var audioEngine: AVAudioEngine?
    private let fftSize = 4096
    private let recognizer = ChordRecognizer()
    private var hann: [Float] = []
    private var hardwareSampleRate: Float = 48000

    // Stability gate: chord must be detected N times in a row before it counts
    private var lastRawName: String? = nil
    private var consecutiveCount: Int = 0
    private let requiredConsecutive = 4
    private let minimumConfidence: Float = 0.72
    // Amplitude gate: filters out quiet voices / ambient noise
    private let minimumRMS: Float = 0.008

    init() {
        hann = (0..<4096).map { i in
            0.5 * (1 - cos(2 * .pi * Float(i) / Float(4095)))
        }
    }

    func start() {
        guard !isRunning else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        hardwareSampleRate = Float(format.sampleRate)

        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: format) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        do {
            try engine.start()
            self.audioEngine = engine
            self.isRunning = true
        } catch {
            print("AudioEngine start error: \(error)")
        }
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRunning = false
        rawChord = nil
        rawConfidence = 0
        stableChord = nil
        stableConfidence = 0
        lastRawName = nil
        consecutiveCount = 0
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        let count = min(frameCount, fftSize)

        // Amplitude gate — skip if signal is too quiet (voice, ambient)
        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(count))
        guard rms > minimumRMS else {
            DispatchQueue.main.async { [weak self] in
                self?.rawChord = nil
                self?.rawConfidence = 0
                self?.resetStability()
            }
            return
        }

        var windowed = [Float](repeating: 0, count: fftSize)
        for i in 0..<count {
            windowed[i] = channelData[i] * hann[i]
        }

        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return }
        defer { vDSP_destroy_fftsetup(setup) }

        var real = windowed
        var imag = [Float](repeating: 0, count: fftSize)

        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBytes { rawPtr in
                    let ptr = rawPtr.bindMemory(to: DSPComplex.self)
                    vDSP_ctoz(ptr.baseAddress!, 2, &split, 1, vDSP_Length(fftSize / 2))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))

                var magnitudes = [Float](repeating: 0, count: fftSize / 2)
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))

                let freqResolution = self.hardwareSampleRate / Float(self.fftSize)
                let minBin = Int(150 / freqResolution)   // ignore below 150 Hz (most voice fundamentals)
                let maxBin = Int(5000 / freqResolution)

                var peaks: [(freq: Float, mag: Float)] = []
                for bin in minBin..<min(maxBin, magnitudes.count - 1) {
                    let m = magnitudes[bin]
                    if m > magnitudes[bin - 1] && m > magnitudes[bin + 1] && m > 0.005 {
                        peaks.append((Float(bin) * freqResolution, m))
                    }
                }

                peaks.sort { $0.mag > $1.mag }
                let topPeaks = Array(peaks.prefix(8))
                let pitchClasses = Set(topPeaks.compactMap { self.freqToPitchClass($0.freq) })
                let result = self.recognizer.identify(pitchClasses: pitchClasses)

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.rawChord = result?.name
                    self.rawConfidence = result?.confidence ?? 0

                    if let name = result?.name, (result?.confidence ?? 0) >= self.minimumConfidence {
                        if name == self.lastRawName {
                            self.consecutiveCount += 1
                            if self.consecutiveCount >= self.requiredConsecutive {
                                self.stableChord = name
                                self.stableConfidence = result?.confidence ?? 0
                            }
                        } else {
                            self.lastRawName = name
                            self.consecutiveCount = 1
                        }
                    } else {
                        self.resetStability()
                    }
                }
            }
        }
    }

    private func resetStability() {
        lastRawName = nil
        consecutiveCount = 0
        stableChord = nil
        stableConfidence = 0
    }

    private func freqToPitchClass(_ freq: Float) -> Int? {
        guard freq > 0 else { return nil }
        let midi = 12 * log2(freq / 440) + 69
        guard midi >= 36 && midi <= 96 else { return nil }
        return Int(midi.rounded()) % 12
    }
}
