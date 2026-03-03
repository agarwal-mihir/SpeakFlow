import Domain
import Foundation

public final class KeychainSecretStore: SecretStoreProtocol {
    private let serviceName: String
    private let accountName: String

    public init(serviceName: String = "com.speakflow.desktop", accountName: String = "groq_api_key") {
        self.serviceName = serviceName
        self.accountName = accountName
    }

    public func getGroqAPIKey() throws -> String? {
        if let env = ProcessInfo.processInfo.environment["GROQ_API_KEY"], !env.isEmpty {
            return env
        }

        let (status, out, _) = runSecurity([
            "find-generic-password",
            "-s", serviceName,
            "-a", accountName,
            "-w"
        ])
        guard status == 0 else { return nil }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func hasGroqAPIKey() -> Bool {
        (try? getGroqAPIKey())??.isEmpty == false
    }

    public func setGroqAPIKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SpeakFlowError.keychainFailure("API key cannot be empty")
        }
        _ = try runSecurityOrThrow([
            "add-generic-password",
            "-U",
            "-s", serviceName,
            "-a", accountName,
            "-w", trimmed
        ])
    }

    public func deleteGroqAPIKey() throws {
        _ = try? runSecurityOrThrow([
            "delete-generic-password",
            "-s", serviceName,
            "-a", accountName
        ])
    }

    private func runSecurityOrThrow(_ args: [String]) throws -> (String, String) {
        let (status, out, err) = runSecurity(args)
        guard status == 0 else {
            if err.contains("Unable to obtain authorization") {
                throw SpeakFlowError.keychainFailure("Keychain authorization denied. Unlock login keychain and retry.")
            }
            throw SpeakFlowError.keychainFailure(err.isEmpty ? "security command failed" : err)
        }
        return (out, err)
    }

    private func runSecurity(_ args: [String]) -> (Int32, String, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
            let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return (process.terminationStatus, out, err)
        } catch {
            return (1, "", error.localizedDescription)
        }
    }
}
