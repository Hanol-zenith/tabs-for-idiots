import AVFoundation
import Accelerate

@MainActor
class ListeningEngine: ObservableObject {
    @Published var stableChord: String? = nil
    @Published var stableConfidence: Float = 0.0
    @Published var isRunning = false

    private var audioEngine: AVAudioEngine?
    private let fftSize = 4096
    private let recognizer = ChordRecognizer()
    private var hann: [Float] = []
    private var hardwareSampleRate: Float = 48000

    private var lastRawName: String? = nil
    private var consecutiveCount: Int = 0
    private let requiredConsecutive = 2    // frames to establish a chord from silence
    private let chordChangeConsecutive = 4 // frames to switch away from an already-stable chord
    private let minimumConfidence: Float = 0.68
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
        stableChord = nil
        stableConfidence = 0
        lastRawName = nil
        consecutiveCount = 0
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        let count = min(frameCount, fftSize)

        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(count))

        guard rms > minimumRMS else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lastRawName = nil
                self.consecutiveCount = 0
                self.stableChord = nil
                self.stableConfidence = 0
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
                let minBin = Int(150 / freqResolution)
                let maxBin = Int(5000 / freqResolution)

                var peaks: [(freq: Float, mag: Float)] = []
                for bin in minBin..<min(maxBin, magnitudes.count - 1) {
                    let m = magnitudes[bin]
                    if m > magnitudes[bin - 1] && m > magnitudes[bin + 1] && m > 0.005 {
                        peaks.append((Float(bin) * freqResolution, m))
                    }
                }

                peaks.sort { $0.mag > $1.mag }
                let topPeaks = peaks.prefix(8).compactMap { p -> (pitchClass: Int, magnitude: Float)? in
                    guard let pc = self.freqToPitchClass(p.freq) else { return nil }
                    return (pc, p.mag)
                }
                let result = self.recognizer.identify(peaks: topPeaks)

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if let name = result?.name, (result?.confidence ?? 0) >= self.minimumConfidence {
                        if name == self.lastRawName {
                            self.consecutiveCount += 1
                            // Require more frames to switch away from an established chord,
                            // so brief false detections of a similar chord don't steal it.
                            let required = (self.stableChord != nil && name != self.stableChord)
                                ? self.chordChangeConsecutive
                                : self.requiredConsecutive
                            if self.consecutiveCount >= required {
                                self.stableChord = name
                                self.stableConfidence = result?.confidence ?? 0
                            }
                        } else {
                            self.lastRawName = name
                            self.consecutiveCount = 1
                        }
                    }
                    // Ambiguous/nil frames: do nothing — just pause the counter.
                    // Silence resets everything via the RMS guard above.
                }
            }
        }
    }

    private func freqToPitchClass(_ freq: Float) -> Int? {
        guard freq > 0 else { return nil }
        let midi = 12 * log2(freq / 440) + 69
        guard midi >= 36 && midi <= 96 else { return nil }
        return Int(midi.rounded()) % 12
    }
}
