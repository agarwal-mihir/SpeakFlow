import Foundation

public protocol ConfigStoreProtocol: Sendable {
    func load() throws -> AppConfig
    func save(_ config: AppConfig) throws
}

public protocol SecretStoreProtocol: Sendable {
    func getGroqAPIKey() throws -> String?
    func setGroqAPIKey(_ value: String) throws
    func deleteGroqAPIKey() throws
    func hasGroqAPIKey() -> Bool
}

public protocol HistoryStoreProtocol: Sendable {
    func add(rawText: String, finalText: String, detectedLanguage: String?, confidence: Double?, outputMode: String, sourceApp: String?) throws
    func search(query: String, limit: Int, offset: Int) throws -> [HistoryRecord]
    func delete(id: Int) throws
    func stats() throws -> HistoryStats
}

public protocol AudioCaptureServiceProtocol: Sendable {
    func startRecording() throws
    func stopRecording() throws -> [Float]
    func isRecording() -> Bool
    func currentLiveLevel() -> Float
    func resetLiveLevel()
}

public protocol SpeechTranscriptionServiceProtocol: Sendable {
    func transcribe(_ audio: [Float]) async throws -> TranscriptResult
}

public protocol CleanupServiceProtocol: Sendable {
    func clean(_ transcript: TranscriptResult) async -> CleanupResult
}

public protocol TextInsertionServiceProtocol: Sendable {
    func insert(text: String, targetPID: Int32?, restoreClipboard: Bool, keepOnFailure: Bool) -> InsertResult
    func pasteLastDictation(text: String, targetPID: Int32?) -> InsertResult
}

public protocol PermissionServiceProtocol: Sendable {
    func checkAll() -> PermissionState
    func requestMicrophone() -> Bool
    func requestAccessibilityPrompt() -> Bool
    func requestInputMonitoringPrompt() -> Bool
    func requestAutomationPrompt() -> Bool
}

public protocol HotkeyServiceProtocol: Sendable {
    func start(mode: HotkeyMode)
    func stop()
    func setHandlers(onPress: @escaping @Sendable () -> Void, onRelease: @escaping @Sendable () -> Void, onPasteLast: @escaping @Sendable () -> Bool)
}

public protocol AutoStartServiceProtocol: Sendable {
    func installLaunchAgent() throws
    func uninstallLaunchAgent() throws
}
