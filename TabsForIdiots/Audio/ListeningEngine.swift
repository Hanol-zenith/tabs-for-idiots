import AVFoundation
import Accelerate
import Combine

@MainActor
class ListeningEngine: ObservableObject {
    @Published var detectedChord: String? = nil
    @Published var confidence: Float = 0.0
    @Published var isRunning = false

    private var audioEngine: AVAudioEngine?
    private let fftSize = 4096
    private let recognizer = ChordRecognizer()
    private var hann: [Float] = []

    init() {
        hann = (0..<4096).map { i in
            0.5 * (1 - cos(2 * .pi * Float(i) / Float(4095)))
        }
    }

    func start() {
        guard !isRunning else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

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
        detectedChord = nil
        confidence = 0
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        let count = min(frameCount, fftSize)

        var windowed = [Float](repeating: 0, count: fftSize)
        for i in 0..<count {
            windowed[i] = channelData[i] * hann[i]
        }

        var real = windowed
        var imag = [Float](repeating: 0, count: fftSize)
        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return }
        defer { vDSP_destroy_fftsetup(setup) }

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

                let sampleRate: Float = 44100
                let freqResolution = sampleRate / Float(fftSize)
                let minBin = Int(100 / freqResolution)
                let maxBin = Int(5000 / freqResolution)

                var peaks: [(freq: Float, mag: Float)] = []
                for bin in minBin..<min(maxBin, magnitudes.count - 1) {
                    let m = magnitudes[bin]
                    if m > magnitudes[bin - 1] && m > magnitudes[bin + 1] && m > 0.01 {
                        peaks.append((Float(bin) * freqResolution, m))
                    }
                }

                peaks.sort { $0.mag > $1.mag }
                let topPeaks = Array(peaks.prefix(8))
                let pitchClasses = Set(topPeaks.compactMap { self.freqToPitchClass($0.freq) })

                let result = self.recognizer.identify(pitchClasses: pitchClasses)

                DispatchQueue.main.async { [weak self] in
                    self?.detectedChord = result?.name
                    self?.confidence = result?.confidence ?? 0
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
