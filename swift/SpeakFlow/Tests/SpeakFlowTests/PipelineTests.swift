import Domain
import Foundation
import Testing

struct PipelineTests {
    final class MockHistory: HistoryStoreProtocol, @unchecked Sendable {
        var added: [String] = []

        func add(rawText: String, finalText: String, detectedLanguage: String?, confidence: Double?, outputMode: String, sourceApp: String?) throws {
            added.append(finalText)
        }

        func search(query: String, limit: Int, offset: Int) throws -> [HistoryRecord] { [] }
        func delete(id: Int) throws {}
        func stats() throws -> HistoryStats {
            HistoryStats(totalCount: 0, latestCreatedAt: "", latestSourceApp: "Unknown", topSourceApp: "Unknown", topSourceAppCount: 0)
        }
    }

    struct MockSTT: SpeechTranscriptionServiceProtocol {
        func transcribe(_ audio: [Float]) async throws -> TranscriptResult {
            TranscriptResult(rawText: "hello there", detectedLanguage: "en", confidence: 0.9, isMixedScript: false)
        }
    }

    struct MockCleanup: CleanupServiceProtocol {
        func clean(_ transcript: TranscriptResult) async -> CleanupResult {
            CleanupResult(text: "Hello there.", outputMode: "english", rewriteProvider: "groq")
        }
    }

    final class MockInserter: TextInsertionServiceProtocol, @unchecked Sendable {
        var inserted: [String] = []

        func insert(text: String, targetPID: Int32?, restoreClipboard: Bool, keepOnFailure: Bool) -> InsertResult {
            inserted.append(text)
            return InsertResult(inserted: true, usedClipboardFallback: false, errorMessage: nil)
        }

        func pasteLastDictation(text: String, targetPID: Int32?) -> InsertResult {
            inserted.append(text)
            return InsertResult(inserted: true, usedClipboardFallback: false, errorMessage: nil)
        }
    }

    @Test func pipelineStoresAndInserts() async throws {
        let history = MockHistory()
        let inserter = MockInserter()
        let pipeline = TranscriptionPipelineActor(stt: MockSTT(), cleanup: MockCleanup(), inserter: inserter, history: history)

        let result = try await pipeline.process(
            DictationUtterance(audioSamples: [0.1, 0.2], sourceApp: "Notes", sourcePID: 12),
            keepOnFailure: true
        )

        #expect(result.cleanup.text == "Hello there.")
        #expect(result.insert.inserted)
    }

    @Test func pasteLastReturnsErrorWhenEmpty() async throws {
        let history = MockHistory()
        let inserter = MockInserter()
        let pipeline = TranscriptionPipelineActor(stt: MockSTT(), cleanup: MockCleanup(), inserter: inserter, history: history)

        let result = await pipeline.pasteLast(targetPID: nil)
        #expect(result.inserted == false)
        #expect(result.errorMessage != nil)
    }
}
