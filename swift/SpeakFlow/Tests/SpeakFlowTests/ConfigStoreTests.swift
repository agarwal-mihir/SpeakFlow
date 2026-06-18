import Domain
import Foundation
import Infra
import Testing

struct ConfigStoreTests {
    @Test func configRoundtripAndUnknownKeyPreserved() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("config.json")
        let seed = """
        {
          "unknown_key": "keep",
          "hotkey_mode": "fn_space_hold",
          "transcription_provider": "parakeet_mlx",
          "whisper_model": "large-v3-turbo",
          "parakeet_model": "parakeet-unified-en-0.6b",
          "groq_transcription_model": "whisper-large-v3",
          "compute_backend": "gpu",
          "lmstudio_auto_start": false,
          "lmstudio_start_timeout_ms": 12000,
          "mlx_enabled": true,
          "mlx_base_url": "http://127.0.0.1:8080/v1",
          "mlx_model": "mlx-community/Qwen3-4B-4bit",
          "mlx_auto_start": false,
          "mlx_start_timeout_ms": 45000,
          "launch_permission_prompt_completed": true
        }
        """
        try seed.data(using: .utf8)?.write(to: path)

        let store = JSONConfigStore(path: path)
        var cfg = try store.load()
        #expect(cfg.hotkeyMode == .fnSpaceHold)
        #expect(cfg.transcriptionProvider == .parakeetMLX)
        #expect(cfg.whisperModel == .largeV3Turbo)
        #expect(cfg.parakeetModel == .unifiedEN06B)
        #expect(cfg.groqTranscriptionModel == .whisperLargeV3)
        #expect(cfg.computeBackend == .gpu)
        #expect(cfg.lmstudioAutoStart == false)
        #expect(cfg.lmstudioStartTimeoutMs == 12000)
        #expect(cfg.mlxEnabled)
        #expect(cfg.mlxBaseURL == "http://127.0.0.1:8080/v1")
        #expect(cfg.mlxModel == .qwen3_4B)
        #expect(cfg.mlxAutoStart == false)
        #expect(cfg.mlxStartTimeoutMs == 45000)
        #expect(cfg.launchPermissionPromptCompleted)
        cfg.cleanupProvider = .deterministic
        cfg.transcriptionProvider = .whisperKit
        cfg.computeBackend = .cpu
        try store.save(cfg)

        let raw = try Data(contentsOf: path)
        let obj = try JSONSerialization.jsonObject(with: raw) as? [String: Any]
        #expect(obj?["unknown_key"] as? String == "keep")
        #expect(obj?["cleanup_provider"] as? String == "deterministic")
        #expect(obj?["transcription_provider"] as? String == "whisperkit")
        #expect(obj?["whisper_model"] as? String == "large-v3-turbo")
        #expect(obj?["parakeet_model"] as? String == "parakeet-unified-en-0.6b")
        #expect(obj?["groq_transcription_model"] as? String == "whisper-large-v3")
        #expect(obj?["compute_backend"] as? String == "cpu")
        #expect(obj?["lmstudio_auto_start"] as? Bool == false)
        #expect(obj?["lmstudio_start_timeout_ms"] as? Int == 12000)
        #expect(obj?["mlx_enabled"] as? Bool == true)
        #expect(obj?["mlx_base_url"] as? String == "http://127.0.0.1:8080/v1")
        #expect(obj?["mlx_model"] as? String == "mlx-community/Qwen3-4B-4bit")
        #expect(obj?["mlx_auto_start"] as? Bool == false)
        #expect(obj?["mlx_start_timeout_ms"] as? Int == 45000)
        #expect(obj?["launch_permission_prompt_completed"] as? Bool == true)
    }
}
