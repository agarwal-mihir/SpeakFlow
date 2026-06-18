import Domain
import Foundation

public final class JSONConfigStore: ConfigStoreProtocol {
    private let path: URL
    private let lock = NSLock()

    public init(path: URL = SpeakFlowPaths.configJSON) {
        self.path = path
    }

    public func load() throws -> AppConfig {
        lock.lock()
        defer { lock.unlock() }

        try ensureAppSupportDirectories()
        guard FileManager.default.fileExists(atPath: path.path) else {
            let cfg = AppConfig()
            try saveUnlocked(cfg, preserve: [:])
            return cfg
        }

        let data = try Data(contentsOf: path)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SpeakFlowError.configurationInvalid("config.json is not a JSON object")
        }

        var cfg = AppConfig()
        if let raw = obj["hotkey_mode"] as? String, let mode = HotkeyMode(rawValue: raw) { cfg.hotkeyMode = mode }
        if let raw = obj["language_mode"] as? String, let mode = LanguageMode(rawValue: raw) { cfg.languageMode = mode }
        if let raw = obj["transcription_provider"] as? String, let provider = TranscriptionProvider(rawValue: raw) { cfg.transcriptionProvider = provider }
        if let raw = obj["whisper_model"] as? String, let model = WhisperModel(rawValue: raw) { cfg.whisperModel = model }
        if let raw = obj["parakeet_model"] as? String, let model = ParakeetModel(rawValue: raw) { cfg.parakeetModel = model }
        if let raw = obj["groq_transcription_model"] as? String, let model = GroqTranscriptionModel(rawValue: raw) { cfg.groqTranscriptionModel = model }
        if let raw = obj["compute_backend"] as? String, let backend = ComputeBackend(rawValue: raw) { cfg.computeBackend = backend }
        if let value = obj["lmstudio_enabled"] as? Bool { cfg.lmstudioEnabled = value }
        if let value = obj["lmstudio_base_url"] as? String { cfg.lmstudioBaseURL = value }
        if let value = obj["lmstudio_auto_start"] as? Bool { cfg.lmstudioAutoStart = value }
        if let value = obj["lmstudio_start_timeout_ms"] as? Int { cfg.lmstudioStartTimeoutMs = min(max(1000, value), 60000) }
        if let value = obj["mlx_enabled"] as? Bool { cfg.mlxEnabled = value }
        if let value = obj["mlx_base_url"] as? String { cfg.mlxBaseURL = value }
        if let raw = obj["mlx_model"] as? String, let model = MLXTextModel(rawValue: raw) { cfg.mlxModel = model }
        if let value = obj["mlx_auto_start"] as? Bool { cfg.mlxAutoStart = value }
        if let value = obj["mlx_start_timeout_ms"] as? Int { cfg.mlxStartTimeoutMs = min(max(1000, value), 120000) }
        if let raw = obj["cleanup_provider"] as? String {
            if raw == "priority" {
                cfg.cleanupProvider = cfg.mlxEnabled ? .mlxLocal : .groqCloud
            } else if let mode = CleanupProvider(rawValue: raw) {
                cfg.cleanupProvider = mode
            }
        }
        if let value = obj["cleanup_system_prompt"] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cfg.cleanupSystemPrompt = value
        }
        if let value = obj["groq_base_url"] as? String { cfg.groqBaseURL = value }
        if let value = obj["groq_model"] as? String { cfg.groqModel = value }
        if let value = obj["max_cleanup_timeout_ms"] as? Int { cfg.maxCleanupTimeoutMs = max(200, value) }
        if let value = obj["floating_indicator_enabled"] as? Bool { cfg.floatingIndicatorEnabled = value }
        if let value = obj["floating_indicator_hide_delay_ms"] as? Int { cfg.floatingIndicatorHideDelayMs = min(max(200, value), 10000) }
        if let value = obj["floating_indicator_origin_x"] as? Double { cfg.floatingIndicatorOriginX = value }
        if let value = obj["floating_indicator_origin_y"] as? Double { cfg.floatingIndicatorOriginY = value }
        if let value = obj["paste_last_shortcut_enabled"] as? Bool { cfg.pasteLastShortcutEnabled = value }
        if let value = obj["paste_failure_keep_dictation_in_clipboard"] as? Bool { cfg.pasteFailureKeepDictationInClipboard = value }
        if let value = obj["launch_permission_prompt_completed"] as? Bool { cfg.launchPermissionPromptCompleted = value }

        return cfg
    }

    public func save(_ config: AppConfig) throws {
        lock.lock()
        defer { lock.unlock() }

        var preserve: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: path.path) {
            let data = try Data(contentsOf: path)
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                preserve = obj
            }
        }
        try saveUnlocked(config, preserve: preserve)
    }

    private func saveUnlocked(_ config: AppConfig, preserve: [String: Any]) throws {
        try ensureAppSupportDirectories()

        var merged = preserve
        merged["hotkey_mode"] = config.hotkeyMode.rawValue
        merged["language_mode"] = config.languageMode.rawValue
        merged["transcription_provider"] = config.transcriptionProvider.rawValue
        merged["whisper_model"] = config.whisperModel.rawValue
        merged["parakeet_model"] = config.parakeetModel.rawValue
        merged["groq_transcription_model"] = config.groqTranscriptionModel.rawValue
        merged["compute_backend"] = config.computeBackend.rawValue
        merged["lmstudio_enabled"] = config.lmstudioEnabled
        merged["lmstudio_base_url"] = config.lmstudioBaseURL
        merged["lmstudio_auto_start"] = config.lmstudioAutoStart
        merged["lmstudio_start_timeout_ms"] = config.lmstudioStartTimeoutMs
        merged["cleanup_provider"] = config.cleanupProvider.rawValue
        merged["cleanup_system_prompt"] = config.cleanupSystemPrompt
        merged["mlx_enabled"] = config.mlxEnabled
        merged["mlx_base_url"] = config.mlxBaseURL
        merged["mlx_model"] = config.mlxModel.rawValue
        merged["mlx_auto_start"] = config.mlxAutoStart
        merged["mlx_start_timeout_ms"] = config.mlxStartTimeoutMs
        merged["groq_base_url"] = config.groqBaseURL
        merged["groq_model"] = config.groqModel
        merged["max_cleanup_timeout_ms"] = config.maxCleanupTimeoutMs
        merged["floating_indicator_enabled"] = config.floatingIndicatorEnabled
        merged["floating_indicator_hide_delay_ms"] = config.floatingIndicatorHideDelayMs
        merged["floating_indicator_origin_x"] = config.floatingIndicatorOriginX
        merged["floating_indicator_origin_y"] = config.floatingIndicatorOriginY
        merged["paste_last_shortcut_enabled"] = config.pasteLastShortcutEnabled
        merged["paste_failure_keep_dictation_in_clipboard"] = config.pasteFailureKeepDictationInClipboard
        merged["launch_permission_prompt_completed"] = config.launchPermissionPromptCompleted

        let data = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
        let tmp = path.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(path, withItemAt: tmp)
    }
}
