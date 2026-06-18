import AppKit
import Domain
import Foundation
import Infra
import Platform
import SwiftUI

@MainActor
public final class AppRuntime: ObservableObject {
    @Published public var serviceEnabled = true
    @Published public var state: ServiceState = .idle
    @Published public var lastError = ""
    @Published public var permissionState = PermissionState()
    @Published public var requiresPermissionOnboarding = false
    @Published public var history: [HistoryRecord] = []
    @Published public var historyQuery = ""
    @Published public var historyStats = HistoryStats(totalCount: 0, latestCreatedAt: "", latestSourceApp: "Unknown", topSourceApp: "Unknown", topSourceAppCount: 0)
    @Published public var config: AppConfig
    @Published public var audioLevel: Float = 0
    @Published public var parakeetRunnerStatus: ParakeetMLXRunnerStatus = ParakeetMLXRunner.status()
    @Published public var groqModels: [RemoteModelOption] = AppRuntime.defaultGroqModels
    @Published public var groqModelStatus = "Using built-in Groq model list"
    @Published public var isLoadingGroqModels = false

    private let configStore: JSONConfigStore
    private let historyStore: SQLiteHistoryStore
    private let secretStore: KeychainSecretStore
    private let inserter: TextInsertionService
    private let permissionService: PermissionService
    private let hotkeyService: HotkeyService
    private let audioService: AudioCaptureService
    private let cleanupService: CleanupService
    private var sttService: SpeechTranscriptionServiceProtocol
    private let autoStartService: AutoStartService
    private let pipeline: TranscriptionPipelineActor
    private let indicator: FloatingIndicatorController
    private let singleInstanceLock = SingleInstanceLock()

    private var statusBarController: StatusBarController?
    private var meterTimer: Timer?
    private var didRunLaunchPermissionPrompt = false

    public init() {
        configStore = JSONConfigStore()
        let loadedConfig = (try? configStore.load()) ?? AppConfig()
        config = loadedConfig
        do {
            historyStore = try SQLiteHistoryStore()
        } catch {
            AppLogger.error("Failed to initialize default history store, using temporary store: \(error.localizedDescription)")
            let fallbackURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("SpeakFlow-\(UUID().uuidString)")
                .appendingPathComponent("history.sqlite3")
            do {
                historyStore = try SQLiteHistoryStore(dbURL: fallbackURL)
            } catch {
                fatalError("Failed to initialize fallback history store: \(error.localizedDescription)")
            }
        }
        secretStore = KeychainSecretStore()
        inserter = TextInsertionService(pasteRetry: 1)
        permissionService = PermissionService()
        hotkeyService = HotkeyService()
        audioService = AudioCaptureService()
        sttService = Self.makeTranscriptionService(for: loadedConfig, secretStore: secretStore)
        cleanupService = CleanupService(configProvider: { [weak configStore] in
            (try? configStore?.load()) ?? AppConfig()
        }, secretStore: secretStore)
        autoStartService = AutoStartService()
        pipeline = TranscriptionPipelineActor(stt: sttService, cleanup: cleanupService, inserter: inserter, history: historyStore)
        indicator = FloatingIndicatorController(hideDelayMs: loadedConfig.floatingIndicatorHideDelayMs)
        indicator.setPosition(x: loadedConfig.floatingIndicatorOriginX, y: loadedConfig.floatingIndicatorOriginY)
        indicator.onMoved = { [weak self] point in
            self?.setIndicatorPosition(x: point.x, y: point.y)
        }

        if !singleInstanceLock.acquire() {
            AppLogger.info("Second instance detected; focusing existing app and terminating.")
            let script = "tell application id \"com.speakflow.desktop\" to activate"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            try? process.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.terminate(nil)
            }
            return
        }

        setupHotkeys()
        refreshPermissions()
        reloadHistory()
        refreshRuntimeUIState()
        runLaunchPermissionPromptIfNeeded()
    }

    public func configureStatusBar(openAction: @escaping () -> Void) {
        if statusBarController != nil {
            return
        }
        statusBarController = StatusBarController(runtime: self, onOpen: openAction)
        statusBarController?.rebuildMenu()
    }

    public func setIndicatorPosition(x: Double, y: Double) {
        config.floatingIndicatorOriginX = x
        config.floatingIndicatorOriginY = y
        saveConfig()
    }

    public func refreshPermissions() {
        permissionState = permissionService.checkAll()
        refreshRuntimeUIState()
        AppLogger.info("Permissions refreshed: mic=\(permissionState.microphone) ax=\(permissionState.accessibility) im=\(permissionState.inputMonitoring)")
    }

    public func requestPermission(_ kind: PermissionKind) {
        if !config.launchPermissionPromptCompleted {
            config.launchPermissionPromptCompleted = true
            saveConfig()
        }
        switch kind {
        case .microphone:
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !(await self.permissionService.requestMicrophone()) {
                    self.permissionService.openMicrophoneSettings()
                }
                self.refreshPermissions()
            }
            return
        case .accessibility:
            if !permissionService.requestAccessibilityPrompt() {
                permissionService.openAccessibilitySettings()
            }
        case .inputMonitoring:
            if !permissionService.requestInputMonitoringPrompt() {
                permissionService.openInputMonitoringSettings()
            }
        }
        refreshPermissions()
    }

    public func setServiceEnabled(_ enabled: Bool) {
        serviceEnabled = enabled
        if !enabled {
            hotkeyService.stop()
            stopMeterUpdates()
            stopRecordingIfNeeded(discardAudio: true)
            state = .idle
            updateIndicator(.hidden)
        } else {
            setupHotkeys()
        }
        refreshRuntimeUIState()
        AppLogger.info("Service toggled: \(enabled ? "on" : "off")")
    }

    public func reloadHistory() {
        history = (try? historyStore.search(query: historyQuery, limit: 250, offset: 0)) ?? []
        historyStats = (try? historyStore.stats()) ?? historyStats
    }

    public func deleteHistory(_ record: HistoryRecord) {
        try? historyStore.delete(id: record.id)
        reloadHistory()
    }

    public func copyHistory(_ record: HistoryRecord) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(record.finalText, forType: .string)
    }

    public func updateHistoryQuery(_ query: String) {
        historyQuery = query
        reloadHistory()
    }

    public func setHotkeyMode(_ mode: HotkeyMode) {
        config.hotkeyMode = mode
        saveConfig()
        setupHotkeys()
    }

    public func setLanguageMode(_ mode: LanguageMode) {
        config.languageMode = mode
        saveConfig()
    }

    public func setTranscriptionProvider(_ provider: TranscriptionProvider) {
        config.transcriptionProvider = provider
        applyTranscriptionConfig()
    }

    public func setWhisperModel(_ model: WhisperModel) {
        config.whisperModel = model
        config.transcriptionProvider = .whisperKit
        applyTranscriptionConfig()
    }

    public func setParakeetModel(_ model: ParakeetModel) {
        config.parakeetModel = model
        config.transcriptionProvider = .parakeetMLX
        applyTranscriptionConfig()
    }

    public func setGroqTranscriptionModel(_ model: GroqTranscriptionModel) {
        config.groqTranscriptionModel = model
        config.transcriptionProvider = .groqCloud
        applyTranscriptionConfig()
    }

    public func setComputeBackend(_ backend: ComputeBackend) {
        config.computeBackend = backend
        applyTranscriptionConfig()
    }

    public func setCleanupProvider(_ provider: CleanupProvider) {
        config.cleanupProvider = provider
        if provider == .mlxLocal {
            config.mlxEnabled = true
        }
        saveConfig()
    }

    public func setCleanupSystemPrompt(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        config.cleanupSystemPrompt = trimmed.isEmpty ? AppConfig.defaultCleanupSystemPrompt : value
        saveConfig()
    }

    public func resetCleanupSystemPrompt() {
        config.cleanupSystemPrompt = AppConfig.defaultCleanupSystemPrompt
        saveConfig()
    }

    public func setLMStudioEnabled(_ enabled: Bool) {
        config.lmstudioEnabled = enabled
        saveConfig()
    }

    public func setLMStudioBaseURL(_ value: String) {
        config.lmstudioBaseURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
        saveConfig()
    }

    public func setLMStudioAutoStart(_ enabled: Bool) {
        config.lmstudioAutoStart = enabled
        saveConfig()
    }

    public func setLMStudioStartTimeoutMs(_ value: Int) {
        config.lmstudioStartTimeoutMs = min(max(value, 1000), 60000)
        saveConfig()
    }

    public func setMLXEnabled(_ enabled: Bool) {
        config.mlxEnabled = enabled
        saveConfig()
    }

    public func setMLXBaseURL(_ value: String) {
        config.mlxBaseURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
        saveConfig()
    }

    public func setMLXModel(_ model: MLXTextModel) {
        config.mlxModel = model
        saveConfig()
    }

    public func setMLXAutoStart(_ enabled: Bool) {
        config.mlxAutoStart = enabled
        saveConfig()
    }

    public func setMLXStartTimeoutMs(_ value: Int) {
        config.mlxStartTimeoutMs = min(max(value, 1000), 120000)
        saveConfig()
    }

    public func setGroqModel(_ value: String) {
        config.groqModel = value.trimmingCharacters(in: .whitespacesAndNewlines)
        saveConfig()
    }

    public func setGroqBaseURL(_ value: String) {
        config.groqBaseURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
        saveConfig()
    }

    public func setFloatingIndicatorEnabled(_ enabled: Bool) {
        config.floatingIndicatorEnabled = enabled
        if !enabled {
            updateIndicator(.hidden)
        }
        saveConfig()
    }

    public func setFloatingIndicatorHideDelayMs(_ value: Int) {
        config.floatingIndicatorHideDelayMs = min(max(value, 200), 10000)
        indicator.setHideDelayMs(config.floatingIndicatorHideDelayMs)
        saveConfig()
    }

    public func setPasteLastShortcutEnabled(_ enabled: Bool) {
        config.pasteLastShortcutEnabled = enabled
        saveConfig()
    }

    public func setPasteFailureKeepDictationInClipboard(_ enabled: Bool) {
        config.pasteFailureKeepDictationInClipboard = enabled
        saveConfig()
    }

    public func hasGroqAPIKey() -> Bool {
        secretStore.hasGroqAPIKey()
    }

    public func setGroqKey(_ key: String) {
        do {
            try secretStore.setGroqAPIKey(key)
            lastError = ""
            AppLogger.info("Groq API key saved to keychain.")
        } catch {
            lastError = error.localizedDescription
            AppLogger.error("Failed to save Groq key: \(error.localizedDescription)")
        }
    }

    public func clearGroqKey() {
        do {
            try secretStore.deleteGroqAPIKey()
            lastError = ""
            AppLogger.info("Groq API key removed from keychain.")
        } catch {
            lastError = error.localizedDescription
            AppLogger.error("Failed to clear Groq key: \(error.localizedDescription)")
        }
    }

    public func refreshModelStatus() {
        parakeetRunnerStatus = ParakeetMLXRunner.status()
        Task { await refreshGroqModels() }
    }

    public func refreshGroqModels() async {
        guard !isLoadingGroqModels else { return }
        isLoadingGroqModels = true
        defer { isLoadingGroqModels = false }

        guard let key = try? secretStore.getGroqAPIKey(), !key.isEmpty else {
            groqModels = Self.defaultGroqModels
            groqModelStatus = "Add a Groq API key to load account models"
            return
        }
        guard let url = URL(string: "\(config.groqBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/models") else {
            groqModels = Self.defaultGroqModels
            groqModelStatus = "Invalid Groq URL"
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                groqModels = Self.defaultGroqModels
                groqModelStatus = "Could not load Groq models; using built-in list"
                return
            }
            let models = Self.parseGroqModels(data: data)
            groqModels = models.isEmpty ? Self.defaultGroqModels : models
            groqModelStatus = models.isEmpty ? "Groq returned no models; using built-in list" : "Loaded \(models.count) Groq models"
        } catch {
            groqModels = Self.defaultGroqModels
            groqModelStatus = "Could not load Groq models; using built-in list"
        }
    }

    public func installAutostart() {
        do {
            try autoStartService.installLaunchAgent()
            lastError = ""
            AppLogger.info("Autostart installed.")
        } catch {
            lastError = error.localizedDescription
            AppLogger.error("Failed to install autostart: \(error.localizedDescription)")
        }
    }

    public func uninstallAutostart() {
        do {
            try autoStartService.uninstallLaunchAgent()
            lastError = ""
            AppLogger.info("Autostart removed.")
        } catch {
            lastError = error.localizedDescription
            AppLogger.error("Failed to remove autostart: \(error.localizedDescription)")
        }
    }

    private func saveConfig() {
        try? configStore.save(config)
        refreshRuntimeUIState()
    }

    private func applyTranscriptionConfig() {
        sttService = Self.makeTranscriptionService(for: config, secretStore: secretStore)
        let service = sttService
        Task {
            await pipeline.setTranscriptionService(service)
        }
        saveConfig()
        AppLogger.info("Transcription config updated: provider=\(config.transcriptionProvider.rawValue) whisper=\(config.whisperModel.rawValue) parakeet=\(config.parakeetModel.rawValue) groq=\(config.groqTranscriptionModel.rawValue) compute=\(config.computeBackend.rawValue)")
    }

    private static func makeTranscriptionService(for config: AppConfig, secretStore: KeychainSecretStore) -> SpeechTranscriptionServiceProtocol {
        switch config.transcriptionProvider {
        case .whisperKit:
            return WhisperKitTranscriptionService(
                modelName: config.whisperModel.rawValue,
                computeBackend: config.computeBackend
            )
        case .parakeetMLX:
            return ParakeetMLXTranscriptionService(
                model: config.parakeetModel,
                computeBackend: config.computeBackend
            )
        case .appleSpeech:
            return AppleSpeechTranscriptionService(languageMode: config.languageMode)
        case .groqCloud:
            return GroqTranscriptionService(
                baseURL: config.groqBaseURL,
                model: config.groqTranscriptionModel,
                languageMode: config.languageMode,
                apiKeyProvider: { try secretStore.getGroqAPIKey() }
            )
        }
    }

    private static let defaultGroqModels: [RemoteModelOption] = [
        RemoteModelOption(id: "meta-llama/llama-4-maverick-17b-128e-instruct", title: "Llama 4 Maverick", detail: "General cleanup"),
        RemoteModelOption(id: "meta-llama/llama-4-scout-17b-16e-instruct", title: "Llama 4 Scout", detail: "Fast multimodal"),
        RemoteModelOption(id: "llama-3.3-70b-versatile", title: "Llama 3.3 70B", detail: "Versatile text"),
        RemoteModelOption(id: "llama-3.1-8b-instant", title: "Llama 3.1 8B Instant", detail: "Low latency"),
        RemoteModelOption(id: "qwen/qwen3-32b", title: "Qwen3 32B", detail: "Reasoning capable"),
        RemoteModelOption(id: "openai/gpt-oss-120b", title: "GPT-OSS 120B", detail: "Open model"),
        RemoteModelOption(id: "openai/gpt-oss-20b", title: "GPT-OSS 20B", detail: "Fast open model"),
        RemoteModelOption(id: "groq/compound", title: "Compound", detail: "Groq compound system"),
        RemoteModelOption(id: "groq/compound-mini", title: "Compound Mini", detail: "Lower latency compound"),
    ]

    private static func parseGroqModels(data: Data) -> [RemoteModelOption] {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataList = json["data"] as? [[String: Any]]
        else {
            return []
        }
        return dataList.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            return RemoteModelOption(
                id: id,
                title: modelTitle(from: id),
                detail: modelDetail(from: item)
            )
        }
        .filter { !$0.id.hasPrefix("whisper-") }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private static func modelTitle(from id: String) -> String {
        id.split(separator: "/").last.map(String.init)?
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.uppercased().hasPrefix("GPT") ? String($0).uppercased() : $0.capitalized }
            .joined(separator: " ") ?? id
    }

    private static func modelDetail(from item: [String: Any]) -> String {
        if let ownedBy = item["owned_by"] as? String, !ownedBy.isEmpty {
            return ownedBy
        }
        return "Groq model"
    }

    private func stopRecordingIfNeeded(discardAudio: Bool) {
        guard audioService.isRecording() else { return }
        do {
            let samples = try audioService.stopRecording()
            AppLogger.info("Recording stopped after service disable. discarded_samples=\(discardAudio ? samples.count : 0)")
        } catch {
            AppLogger.error("Failed to stop recording while disabling service: \(error.localizedDescription)")
        }
    }

    private func setupHotkeys() {
        hotkeyService.stop()
        hotkeyService.setHandlers(
            onPress: { [weak self] in
                Task { @MainActor in self?.onHotkeyPress() }
            },
            onRelease: { [weak self] in
                Task { @MainActor in self?.onHotkeyRelease() }
            },
            onPasteLast: { [weak self] in
                self?.handlePasteLastHotkey() ?? false
            }
        )
        guard serviceEnabled else { return }
        hotkeyService.start(mode: config.hotkeyMode)
    }

    nonisolated private func handlePasteLastHotkey() -> Bool {
        final class FlagBox: @unchecked Sendable { var value = false }

        let flag = FlagBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task { @MainActor [weak self] in
            defer { semaphore.signal() }
            guard let self else { return }
            guard self.serviceEnabled, self.permissionState.dictationReady, self.config.pasteLastShortcutEnabled else {
                return
            }
            flag.value = true
            let pid = self.frontmostPID()
            Task {
                let result = await self.pipeline.pasteLast(targetPID: pid)
                await MainActor.run {
                    self.lastError = result.errorMessage ?? ""
                }
            }
        }
        _ = semaphore.wait(timeout: .now() + 0.5)
        return flag.value
    }

    private func refreshRuntimeUIState() {
        requiresPermissionOnboarding = !permissionState.dictationReady
        statusBarController?.rebuildMenu()
    }

    private func runLaunchPermissionPromptIfNeeded() {
        guard !permissionState.dictationReady else { return }
        guard !didRunLaunchPermissionPrompt else { return }
        guard !config.launchPermissionPromptCompleted else { return }
        didRunLaunchPermissionPrompt = true
        config.launchPermissionPromptCompleted = true
        saveConfig()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.permissionState.microphone {
                    _ = await self.permissionService.requestMicrophone()
                }
                if !self.permissionState.inputMonitoring {
                    _ = self.permissionService.requestInputMonitoringPrompt()
                }
                self.refreshPermissions()
            }
        }
    }

    private func updateIndicator(_ state: FloatingIndicatorController.State) {
        guard config.floatingIndicatorEnabled else {
            indicator.update(state: .hidden)
            return
        }
        indicator.update(state: state)
    }

    private func startMeterUpdates() {
        stopMeterUpdates()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.state == .recording else { return }
                let level = self.audioService.currentLiveLevel()
                self.audioLevel = level
                self.updateIndicator(.recording(level: level))
            }
        }
    }

    private func stopMeterUpdates() {
        meterTimer?.invalidate()
        meterTimer = nil
        audioLevel = 0
    }

    private func onHotkeyPress() {
        guard serviceEnabled else { return }
        guard permissionState.dictationReady else {
            lastError = "Microphone and Input Monitoring permissions are required before dictation"
            refreshRuntimeUIState()
            AppLogger.error("Dictation start blocked due to missing permissions.")
            return
        }

        do {
            try audioService.startRecording()
            state = .recording
            updateIndicator(.recording(level: audioService.currentLiveLevel()))
            startMeterUpdates()
            refreshRuntimeUIState()
            AppLogger.info("Dictation recording started.")
        } catch {
            state = .error
            lastError = error.localizedDescription
            stopMeterUpdates()
            updateIndicator(.error(lastError))
            refreshRuntimeUIState()
            AppLogger.error("Failed to start recording: \(error.localizedDescription)")
        }
    }

    private func onHotkeyRelease() {
        guard serviceEnabled else { return }
        guard audioService.isRecording() else { return }
        stopMeterUpdates()

        do {
            let audio = try audioService.stopRecording()
            if audio.isEmpty {
                state = .idle
                updateIndicator(.hidden)
                refreshRuntimeUIState()
                AppLogger.info("Dictation stopped with empty audio.")
                return
            }
            state = .transcribing
            updateIndicator(.transcribing)
            refreshRuntimeUIState()
            AppLogger.info("Dictation recording stopped; transcribing started.")

            let utterance = DictationUtterance(
                audioSamples: audio,
                sourceApp: frontmostAppName(),
                sourcePID: frontmostPID()
            )
            Task {
                do {
                    let output = try await pipeline.process(
                        utterance,
                        keepOnFailure: config.pasteFailureKeepDictationInClipboard
                    )
                    await MainActor.run {
                        self.state = .idle
                        self.lastError = output.insert.errorMessage ?? ""
                        self.reloadHistory()
                        self.updateIndicator(output.insert.inserted ? .done("Done") : .error(output.insert.errorMessage ?? "Paste failed"))
                        self.refreshRuntimeUIState()
                        AppLogger.info("Transcription completed. inserted=\(output.insert.inserted) provider=\(output.cleanup.rewriteProvider ?? "deterministic")")
                    }
                } catch {
                    await MainActor.run {
                        self.state = .error
                        self.lastError = error.localizedDescription
                        self.updateIndicator(.error(self.lastError))
                        self.refreshRuntimeUIState()
                        AppLogger.error("Transcription failed: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            state = .error
            lastError = error.localizedDescription
            updateIndicator(.error(lastError))
            refreshRuntimeUIState()
            AppLogger.error("Failed to stop recording: \(error.localizedDescription)")
        }
    }

    private func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    private func frontmostPID() -> Int32? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }
        return pid
    }

    deinit {
        hotkeyService.stop()
    }
}

public enum PermissionKind: String, CaseIterable, Identifiable {
    case microphone
    case accessibility
    case inputMonitoring

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .accessibility: return "Accessibility"
        case .inputMonitoring: return "Input Monitoring"
        }
    }
}
