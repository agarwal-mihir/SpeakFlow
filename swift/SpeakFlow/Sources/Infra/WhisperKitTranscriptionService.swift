import Domain
import Foundation

#if canImport(WhisperKit)
@preconcurrency import WhisperKit
#endif

public final class WhisperKitTranscriptionService: SpeechTranscriptionServiceProtocol, @unchecked Sendable {
    private let modelName: String
    private nonisolated(unsafe) var cachedWhisper: Any?

    public init(modelName: String = "large-v3") {
        self.modelName = modelName
    }

    public func transcribe(_ audio: [Float]) async throws -> TranscriptResult {
        guard !audio.isEmpty else {
            return TranscriptResult(rawText: "", detectedLanguage: nil, confidence: nil, isMixedScript: false)
        }

        #if canImport(WhisperKit)
        let whisper: WhisperKit
        if let existing = cachedWhisper as? WhisperKit {
            whisper = existing
        } else {
            let whisperConfig = WhisperKitConfig(
                model: modelName,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: true,
                useBackgroundDownloadSession: false
            )
            let instance = try await WhisperKit(whisperConfig)
            cachedWhisper = instance
            whisper = instance
        }

        let decode = DecodingOptions(
            verbose: false,
            task: .transcribe,
            usePrefillPrompt: true,
            detectLanguage: true
        )
        let results: [TranscriptionResult] = try await whisper.transcribe(audioArray: audio, decodeOptions: decode)
        let text = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let detectedLanguage = results.first?.language
        let avgLogprob = results
            .flatMap(\.segments)
            .map(\.avgLogprob)
            .reduce(0.0, +) / Float(max(1, results.flatMap(\.segments).count))
        let confidence = max(0.0, min(1.0, exp(Double(avgLogprob))))
        return TranscriptResult(
            rawText: text,
            detectedLanguage: detectedLanguage,
            confidence: confidence,
            isMixedScript: mixedScriptRatio(text) >= 0.07
        )
        #else
        throw SpeakFlowError.transcriptionFailed(
            "WhisperKit is not linked yet. Add WhisperKit dependency in Package.swift and rebuild."
        )
        #endif
    }

    private func mixedScriptRatio(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        let total = Double(text.count)
        let devCount = Double(text.unicodeScalars.filter { (0x0900...0x097F).contains(Int($0.value)) }.count)
        return devCount / total
    }
}
