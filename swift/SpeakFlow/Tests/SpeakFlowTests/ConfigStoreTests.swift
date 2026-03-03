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
          "lmstudio_auto_start": false,
          "lmstudio_start_timeout_ms": 12000
        }
        """
        try seed.data(using: .utf8)?.write(to: path)

        let store = JSONConfigStore(path: path)
        var cfg = try store.load()
        #expect(cfg.hotkeyMode == .fnSpaceHold)
        #expect(cfg.lmstudioAutoStart == false)
        #expect(cfg.lmstudioStartTimeoutMs == 12000)
        cfg.cleanupProvider = .deterministic
        try store.save(cfg)

        let raw = try Data(contentsOf: path)
        let obj = try JSONSerialization.jsonObject(with: raw) as? [String: Any]
        #expect(obj?["unknown_key"] as? String == "keep")
        #expect(obj?["cleanup_provider"] as? String == "deterministic")
        #expect(obj?["lmstudio_auto_start"] as? Bool == false)
        #expect(obj?["lmstudio_start_timeout_ms"] as? Int == 12000)
    }
}
