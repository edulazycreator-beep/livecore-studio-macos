import Foundation
import AVFAudio
import CoreAudio

public final class AudioMixerEngine: @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private let mainMixer: AVAudioMixerNode
    public private(set) var isRunning: Bool = false

    public var onMasterMeterUpdate: ((Double, Double) -> Void)?

    public init() {
        self.mainMixer = audioEngine.mainMixerNode
    }

    public func startEngine() throws {
        guard !audioEngine.isRunning else { return }
        let inputNode = audioEngine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        if format.channelCount > 0 && format.sampleRate > 0 {
            mainMixer.removeTap(onBus: 0)
            mainMixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
                guard let self = self else { return }
                let (peak, rms) = Self.computeLevels(from: buffer)
                self.onMasterMeterUpdate?(peak, rms)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRunning = true
    }

    public func stopEngine() {
        guard audioEngine.isRunning else { return }
        mainMixer.removeTap(onBus: 0)
        audioEngine.stop()
        isRunning = false
    }

    public func setMasterOutputVolume(_ linearVolume: Float) {
        mainMixer.outputVolume = min(max(linearVolume, 0.0), 1.5)
    }

    public static func computeLevels(from buffer: AVAudioPCMBuffer) -> (peakDBFS: Double, rmsDBFS: Double) {
        guard let channelData = buffer.floatChannelData else {
            return (-60.0, -60.0)
        }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return (-60.0, -60.0)
        }

        let samples = channelData[0]
        var peak: Float = 0.0
        var sumSquares: Float = 0.0

        for i in 0..<frameLength {
            let sample = abs(samples[i])
            if sample > peak {
                peak = sample
            }
            sumSquares += sample * sample
        }

        let rms = sqrt(sumSquares / Float(frameLength))
        let peakDB = peak > 0.00001 ? Double(20.0 * log10(peak)) : -60.0
        let rmsDB = rms > 0.00001 ? Double(20.0 * log10(rms)) : -60.0

        return (max(-60.0, min(0.0, peakDB)), max(-60.0, min(0.0, rmsDB)))
    }
}
