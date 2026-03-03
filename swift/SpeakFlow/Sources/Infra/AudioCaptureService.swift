import AVFoundation
import Domain
import Foundation

public final class AudioCaptureService: AudioCaptureServiceProtocol, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var bufferedSamples: [Float] = []
    private var liveLevel: Float = 0
    private var recording = false

    private let targetSampleRate: Double = 16_000
    private let silenceThreshold: Float = 0.0137 // ~450/32768
    private let silencePaddingSeconds: Double = 0.12

    public init() {}

    public func startRecording() throws {
        lock.lock()
        if recording {
            lock.unlock()
            return
        }
        bufferedSamples.removeAll(keepingCapacity: true)
        liveLevel = 0
        recording = true
        lock.unlock()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            lock.lock()
            recording = false
            lock.unlock()
            throw SpeakFlowError.recordingFailed(error.localizedDescription)
        }
    }

    public func stopRecording() throws -> [Float] {
        lock.lock()
        let wasRecording = recording
        recording = false
        lock.unlock()

        guard wasRecording else { return [] }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        lock.lock()
        let samples = bufferedSamples
        bufferedSamples.removeAll(keepingCapacity: false)
        liveLevel = 0
        lock.unlock()

        return trimSilence(samples)
    }

    public func isRecording() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return recording
    }

    public func currentLiveLevel() -> Float {
        lock.lock()
        defer { lock.unlock() }
        return liveLevel
    }

    public func resetLiveLevel() {
        lock.lock()
        liveLevel = 0
        lock.unlock()
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        if frameCount == 0 { return }

        let source = UnsafeBufferPointer(start: channelData[0], count: frameCount)
        var chunk = Array(source)

        let sampleRate = buffer.format.sampleRate
        if abs(sampleRate - targetSampleRate) > 0.5 {
            chunk = downsampleLinear(chunk, from: sampleRate, to: targetSampleRate)
        }

        let rms = sqrt(chunk.reduce(0) { $0 + ($1 * $1) } / Float(max(chunk.count, 1)))

        lock.lock()
        bufferedSamples.append(contentsOf: chunk)
        liveLevel = min(1.0, max(0.0, (liveLevel * 0.6) + (rms * 6.0 * 0.4)))
        lock.unlock()
    }

    private func downsampleLinear(_ input: [Float], from: Double, to: Double) -> [Float] {
        guard !input.isEmpty, from > to else { return input }
        let ratio = from / to
        let outCount = Int(Double(input.count) / ratio)
        guard outCount > 1 else { return input }
        var output: [Float] = []
        output.reserveCapacity(outCount)
        for i in 0..<outCount {
            let src = Double(i) * ratio
            let low = Int(src)
            let high = min(low + 1, input.count - 1)
            let frac = Float(src - Double(low))
            output.append(input[low] + ((input[high] - input[low]) * frac))
        }
        return output
    }

    private func trimSilence(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let voiced = samples.enumerated().compactMap { abs($0.element) > silenceThreshold ? $0.offset : nil }
        guard let first = voiced.first, let last = voiced.last else { return [] }

        let pad = Int(silencePaddingSeconds * targetSampleRate)
        let start = max(0, first - pad)
        let end = min(samples.count - 1, last + pad)
        guard start <= end else { return [] }
        return Array(samples[start...end])
    }
}
