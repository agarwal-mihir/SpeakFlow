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
        if let value = obj["lmstudio_enabled"] as? Bool { cfg.lmstudioEnabled = value }
        if let value = obj["lmstudio_base_url"] as? String { cfg.lmstudioBaseURL = value }
        if let value = obj["lmstudio_auto_start"] as? Bool { cfg.lmstudioAutoStart = value }
        if let value = obj["lmstudio_start_timeout_ms"] as? Int { cfg.lmstudioStartTimeoutMs = min(max(1000, value), 60000) }
        if let raw = obj["cleanup_provider"] as? String, let mode = CleanupProvider(rawValue: raw) { cfg.cleanupProvider = mode }
        if let value = obj["groq_base_url"] as? String { cfg.groqBaseURL = value }
        if let value = obj["groq_model"] as? String { cfg.groqModel = value }
        if let value = obj["max_cleanup_timeout_ms"] as? Int { cfg.maxCleanupTimeoutMs = max(200, value) }
        if let value = obj["floating_indicator_enabled"] as? Bool { cfg.floatingIndicatorEnabled = value }
        if let value = obj["floating_indicator_hide_delay_ms"] as? Int { cfg.floatingIndicatorHideDelayMs = min(max(200, value), 10000) }
        if let value = obj["floating_indicator_origin_x"] as? Double { cfg.floatingIndicatorOriginX = value }
        if let value = obj["floating_indicator_origin_y"] as? Double { cfg.floatingIndicatorOriginY = value }
        if let value = obj["paste_last_shortcut_enabled"] as? Bool { cfg.pasteLastShortcutEnabled = value }
        if let value = obj["paste_failure_keep_dictation_in_clipboard"] as? Bool { cfg.pasteFailureKeepDictationInClipboard = value }

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
        merged["lmstudio_enabled"] = config.lmstudioEnabled
        merged["lmstudio_base_url"] = config.lmstudioBaseURL
        merged["lmstudio_auto_start"] = config.lmstudioAutoStart
        merged["lmstudio_start_timeout_ms"] = config.lmstudioStartTimeoutMs
        merged["cleanup_provider"] = config.cleanupProvider.rawValue
        merged["groq_base_url"] = config.groqBaseURL
        merged["groq_model"] = config.groqModel
        merged["max_cleanup_timeout_ms"] = config.maxCleanupTimeoutMs
        merged["floating_indicator_enabled"] = config.floatingIndicatorEnabled
        merged["floating_indicator_hide_delay_ms"] = config.floatingIndicatorHideDelayMs
        merged["floating_indicator_origin_x"] = config.floatingIndicatorOriginX
        merged["floating_indicator_origin_y"] = config.floatingIndicatorOriginY
        merged["paste_last_shortcut_enabled"] = config.pasteLastShortcutEnabled
        merged["paste_failure_keep_dictation_in_clipboard"] = config.pasteFailureKeepDictationInClipboard

        let data = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
        let tmp = path.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(path, withItemAt: tmp)
    }
}
