import Domain
import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

#if canImport(Speech)
@preconcurrency import Speech
#endif

#if canImport(WhisperKit)
import CoreML
@preconcurrency import WhisperKit
#endif

public final class WhisperKitTranscriptionService: SpeechTranscriptionServiceProtocol, @unchecked Sendable {
    private let modelName: String
    private let computeBackend: ComputeBackend
    private nonisolated(unsafe) var cachedWhisper: Any?

    public init(modelName: String = "large-v3", computeBackend: ComputeBackend = .automatic) {
        self.modelName = modelName
        self.computeBackend = computeBackend
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
                computeOptions: computeOptions(),
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

    #if canImport(WhisperKit)
    private func computeOptions() -> ModelComputeOptions {
        switch computeBackend {
        case .automatic:
            return ModelComputeOptions()
        case .cpu:
            return ModelComputeOptions(
                melCompute: .cpuOnly,
                audioEncoderCompute: .cpuOnly,
                textDecoderCompute: .cpuOnly,
                prefillCompute: .cpuOnly
            )
        case .gpu:
            return ModelComputeOptions(
                melCompute: .cpuAndGPU,
                audioEncoderCompute: .cpuAndGPU,
                textDecoderCompute: .cpuAndGPU,
                prefillCompute: .cpuAndGPU
            )
        }
    }
    #endif
}

public final class ParakeetMLXTranscriptionService: SpeechTranscriptionServiceProtocol, @unchecked Sendable {
    private let model: ParakeetModel
    private let computeBackend: ComputeBackend
    private let runner: ParakeetMLXRunner

    public init(model: ParakeetModel, computeBackend: ComputeBackend, runner: ParakeetMLXRunner = .live) {
        self.model = model
        self.computeBackend = computeBackend
        self.runner = runner
    }

    public func transcribe(_ audio: [Float]) async throws -> TranscriptResult {
        guard !audio.isEmpty else {
            return TranscriptResult(rawText: "", detectedLanguage: nil, confidence: nil, isMixedScript: false)
        }

        return try await runner.transcribe(audio: audio, model: model, computeBackend: computeBackend)
    }
}

public final class AppleSpeechTranscriptionService: SpeechTranscriptionServiceProtocol, @unchecked Sendable {
    private let languageMode: LanguageMode

    public init(languageMode: LanguageMode) {
        self.languageMode = languageMode
    }

    public func transcribe(_ audio: [Float]) async throws -> TranscriptResult {
        guard !audio.isEmpty else {
            return TranscriptResult(rawText: "", detectedLanguage: nil, confidence: nil, isMixedScript: false)
        }

        #if canImport(Speech)
        try await ensureSpeechRecognitionAuthorized()

        let recognizer = if let locale = speechLocale() {
            SFSpeechRecognizer(locale: locale)
        } else {
            SFSpeechRecognizer()
        }
        guard let recognizer, recognizer.isAvailable else {
            throw SpeakFlowError.transcriptionFailed("Apple Speech Recognition is unavailable for the selected language.")
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakFlow-AppleSpeech-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        try PCM16WAVWriter.write(samples: audio, sampleRate: 16_000, to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation

        return try await withCheckedThrowingContinuation { continuation in
            let box = SpeechRecognitionContinuationBox(continuation: continuation)
            _ = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    box.resume(throwing: SpeakFlowError.transcriptionFailed(error.localizedDescription))
                    return
                }
                guard let result, result.isFinal else { return }
                let transcription = result.bestTranscription
                let text = transcription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                let confidences = transcription.segments.map(\.confidence).filter { $0 >= 0 }
                let confidence = confidences.isEmpty
                    ? nil
                    : Double(confidences.reduce(0, +)) / Double(confidences.count)
                box.resume(returning: TranscriptResult(
                    rawText: text,
                    detectedLanguage: recognizer.locale.identifier,
                    confidence: confidence,
                    isMixedScript: Self.mixedScriptRatio(text) >= 0.07
                ))
            }
        }
        #else
        throw SpeakFlowError.transcriptionFailed("Apple Speech Recognition is not available in this build.")
        #endif
    }

    #if canImport(Speech)
    private func ensureSpeechRecognitionAuthorized() async throws {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return
        case .notDetermined:
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            guard status == .authorized else {
                throw SpeakFlowError.transcriptionFailed("Apple Speech Recognition permission was not granted.")
            }
        case .denied:
            throw SpeakFlowError.transcriptionFailed("Apple Speech Recognition permission is denied in System Settings.")
        case .restricted:
            throw SpeakFlowError.transcriptionFailed("Apple Speech Recognition is restricted on this Mac.")
        @unknown default:
            throw SpeakFlowError.transcriptionFailed("Apple Speech Recognition authorization is unavailable.")
        }
    }

    private func speechLocale() -> Locale? {
        switch languageMode {
        case .auto:
            return nil
        case .english:
            return Locale(identifier: "en_US")
        case .hinglishRoman:
            return Locale(identifier: "hi_IN")
        }
    }
    #endif

    private static func mixedScriptRatio(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        let total = Double(text.count)
        let devCount = Double(text.unicodeScalars.filter { (0x0900...0x097F).contains(Int($0.value)) }.count)
        return devCount / total
    }
}

public final class GroqTranscriptionService: SpeechTranscriptionServiceProtocol, @unchecked Sendable {
    private let baseURL: String
    private let model: GroqTranscriptionModel
    private let languageMode: LanguageMode
    private let apiKeyProvider: @Sendable () throws -> String?
    private let session: URLSession

    public init(
        baseURL: String,
        model: GroqTranscriptionModel,
        languageMode: LanguageMode,
        apiKeyProvider: @escaping @Sendable () throws -> String?,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.model = model
        self.languageMode = languageMode
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }

    public func transcribe(_ audio: [Float]) async throws -> TranscriptResult {
        guard !audio.isEmpty else {
            return TranscriptResult(rawText: "", detectedLanguage: nil, confidence: nil, isMixedScript: false)
        }
        guard let key = try apiKeyProvider(), !key.isEmpty else {
            throw SpeakFlowError.transcriptionFailed("Add a Groq API key before using Groq transcription.")
        }
        guard let url = URL(string: "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/audio/transcriptions") else {
            throw SpeakFlowError.transcriptionFailed("Invalid Groq base URL.")
        }

        let audioData = PCM16WAVWriter.data(samples: audio, sampleRate: 16_000)
        let boundary = "SpeakFlowBoundary-\(UUID().uuidString)"
        var body = Data()
        appendMultipartField(name: "model", value: model.rawValue, boundary: boundary, to: &body)
        appendMultipartField(name: "response_format", value: "json", boundary: boundary, to: &body)
        appendMultipartField(name: "temperature", value: "0", boundary: boundary, to: &body)
        if let language = groqLanguageCode() {
            appendMultipartField(name: "language", value: language, boundary: boundary, to: &body)
        }
        appendMultipartFile(
            name: "file",
            filename: "dictation.wav",
            contentType: "audio/wav",
            data: audioData,
            boundary: boundary,
            to: &body
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 120
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "Groq transcription request failed."
            throw SpeakFlowError.transcriptionFailed(detail)
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = json["text"] as? String
        else {
            throw SpeakFlowError.transcriptionFailed("Groq transcription returned an unexpected response.")
        }
        return TranscriptResult(
            rawText: text.trimmingCharacters(in: .whitespacesAndNewlines),
            detectedLanguage: json["language"] as? String,
            confidence: nil,
            isMixedScript: Self.mixedScriptRatio(text) >= 0.07
        )
    }

    private func groqLanguageCode() -> String? {
        switch languageMode {
        case .auto:
            return nil
        case .english:
            return "en"
        case .hinglishRoman:
            return "hi"
        }
    }

    private func appendMultipartField(name: String, value: String, boundary: String, to body: inout Data) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }

    private func appendMultipartFile(name: String, filename: String, contentType: String, data: Data, boundary: String, to body: inout Data) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
    }

    private static func mixedScriptRatio(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        let total = Double(text.count)
        let devCount = Double(text.unicodeScalars.filter { (0x0900...0x097F).contains(Int($0.value)) }.count)
        return devCount / total
    }
}

#if canImport(Speech)
private final class SpeechRecognitionContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<TranscriptResult, Error>

    init(continuation: CheckedContinuation<TranscriptResult, Error>) {
        self.continuation = continuation
    }

    func resume(returning result: TranscriptResult) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: result)
    }

    func resume(throwing error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        continuation.resume(throwing: error)
    }
}
#endif

private enum PCM16WAVWriter {
    static func write(samples: [Float], sampleRate: Int, to url: URL) throws {
        try data(samples: samples, sampleRate: sampleRate).write(to: url, options: .atomic)
    }

    static func data(samples: [Float], sampleRate: Int) -> Data {
        var data = Data()
        let channelCount = 1
        let bitsPerSample = 16
        let byteRate = sampleRate * channelCount * bitsPerSample / 8
        let blockAlign = channelCount * bitsPerSample / 8
        let pcmByteCount = samples.count * 2
        let riffChunkSize = 36 + pcmByteCount

        data.appendString("RIFF")
        data.appendUInt32LE(UInt32(riffChunkSize))
        data.appendString("WAVE")
        data.appendString("fmt ")
        data.appendUInt32LE(16)
        data.appendUInt16LE(1)
        data.appendUInt16LE(UInt16(channelCount))
        data.appendUInt32LE(UInt32(sampleRate))
        data.appendUInt32LE(UInt32(byteRate))
        data.appendUInt16LE(UInt16(blockAlign))
        data.appendUInt16LE(UInt16(bitsPerSample))
        data.appendString("data")
        data.appendUInt32LE(UInt32(pcmByteCount))

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let scaled = Int16(clamped * Float(Int16.max))
            data.appendUInt16LE(UInt16(bitPattern: scaled))
        }
        return data
    }
}

private extension Data {
    mutating func appendString(_ value: String) {
        append(value.data(using: .ascii)!)
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
