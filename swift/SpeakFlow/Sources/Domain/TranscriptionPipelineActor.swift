import Foundation

public struct PipelineOutput: Sendable {
    public var transcript: TranscriptResult
    public var cleanup: CleanupResult
    public var insert: InsertResult

    public init(transcript: TranscriptResult, cleanup: CleanupResult, insert: InsertResult) {
        self.transcript = transcript
        self.cleanup = cleanup
        self.insert = insert
    }
}

public actor TranscriptionPipelineActor {
    private let stt: SpeechTranscriptionServiceProtocol
    private let cleanup: CleanupServiceProtocol
    private let inserter: TextInsertionServiceProtocol
    private let history: HistoryStoreProtocol
    private var lastDictationText: String = ""

    public init(
        stt: SpeechTranscriptionServiceProtocol,
        cleanup: CleanupServiceProtocol,
        inserter: TextInsertionServiceProtocol,
        history: HistoryStoreProtocol
    ) {
        self.stt = stt
        self.cleanup = cleanup
        self.inserter = inserter
        self.history = history
    }

    public func process(_ utterance: DictationUtterance, keepOnFailure: Bool) async throws -> PipelineOutput {
        let transcript = try await stt.transcribe(utterance.audioSamples)
        let cleanupResult = await cleanup.clean(transcript)
        let finalText = cleanupResult.text.trimmingCharacters(in: .whitespacesAndNewlines)

        var insertResult = InsertResult(inserted: false, usedClipboardFallback: false, errorMessage: nil)
        if !finalText.isEmpty {
            lastDictationText = finalText
            insertResult = inserter.insert(
                text: finalText,
                targetPID: utterance.sourcePID,
                restoreClipboard: true,
                keepOnFailure: keepOnFailure
            )
            try history.add(
                rawText: transcript.rawText,
                finalText: finalText,
                detectedLanguage: transcript.detectedLanguage,
                confidence: transcript.confidence,
                outputMode: cleanupResult.outputMode,
                sourceApp: utterance.sourceApp
            )
        }

        return PipelineOutput(transcript: transcript, cleanup: cleanupResult, insert: insertResult)
    }

    public func pasteLast(targetPID: Int32?) -> InsertResult {
        let text = lastDictationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return InsertResult(inserted: false, usedClipboardFallback: false, errorMessage: "No recent dictation available to paste.")
        }
        return inserter.pasteLastDictation(text: text, targetPID: targetPID)
    }

    public func lastText() -> String {
        lastDictationText
    }
}
