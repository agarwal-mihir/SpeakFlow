import Domain
import Foundation

public final class CleanupService: CleanupServiceProtocol, @unchecked Sendable {
    private let configProvider: @Sendable () -> AppConfig
    private let secretStore: SecretStoreProtocol
    private let session: URLSession
    private nonisolated(unsafe) var mlxProcess: Process?

    public init(
        configProvider: @escaping @Sendable () -> AppConfig,
        secretStore: SecretStoreProtocol,
        session: URLSession = .shared
    ) {
        self.configProvider = configProvider
        self.secretStore = secretStore
        self.session = session
    }

    public func clean(_ transcript: TranscriptResult) async -> CleanupResult {
        let config = configProvider()
        let mode = LanguageNormalizer.decideOutputMode(
            languageMode: config.languageMode.rawValue,
            text: transcript.rawText,
            detectedLanguage: transcript.detectedLanguage
        )
        let deterministic = mode == "hinglish_roman"
            ? LanguageNormalizer.normalizeHinglishRoman(transcript.rawText)
            : LanguageNormalizer.normalizeEnglish(transcript.rawText)

        if deterministic.isEmpty || config.cleanupProvider == .deterministic {
            AppLogger.info("Cleanup mode deterministic (direct).")
            return CleanupResult(text: deterministic, outputMode: mode, rewriteProvider: nil)
        }

        let rewritten = await rewrite(
            provider: config.cleanupProvider,
            text: deterministic,
            mode: mode,
            config: config
        )
        if let validated = validateRewrite(original: deterministic, rewritten: rewritten, outputMode: mode) {
            AppLogger.info("Cleanup rewrite provider used: \(config.cleanupProvider.rawValue).")
            return CleanupResult(text: validated, outputMode: mode, rewriteProvider: config.cleanupProvider.rawValue)
        }

        AppLogger.info("Selected cleanup provider unavailable/invalid, deterministic safety output used.")
        return CleanupResult(text: deterministic, outputMode: mode, rewriteProvider: nil)
    }

    private func rewrite(provider: CleanupProvider, text: String, mode: String, config: AppConfig) async -> String? {
        switch provider {
        case .mlxLocal:
            if config.mlxAutoStart {
                await ensureMLXServer(config: config)
            }
            return await callOpenAICompatible(
                baseURL: config.mlxBaseURL,
                model: config.mlxModel.rawValue,
                timeoutMs: config.maxCleanupTimeoutMs,
                apiKey: nil,
                text: text,
                mode: mode,
                config: config
            )
        case .groqCloud:
            guard let key = try? secretStore.getGroqAPIKey(), !key.isEmpty else {
                return nil
            }
            return await callOpenAICompatible(
                baseURL: config.groqBaseURL,
                model: config.groqModel,
                timeoutMs: config.maxCleanupTimeoutMs,
                apiKey: key,
                text: text,
                mode: mode,
                config: config
            )
        case .deterministic:
            return nil
        }
    }

    private func ensureMLXServer(config: AppConfig) async {
        if await fetchFirstModel(baseURL: config.mlxBaseURL, timeoutMs: min(config.maxCleanupTimeoutMs, 1000)) != nil {
            return
        }
        if mlxProcess?.isRunning == true {
            await waitForModelServer(
                baseURL: config.mlxBaseURL,
                timeoutMs: config.mlxStartTimeoutMs,
                probeTimeoutMs: min(config.maxCleanupTimeoutMs, 1000)
            )
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "mlx_lm.server",
            "--model", config.mlxModel.rawValue,
            "--host", mlxHost(from: config.mlxBaseURL),
            "--port", mlxPort(from: config.mlxBaseURL),
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            mlxProcess = process
            AppLogger.info("Started MLX cleanup server for \(config.mlxModel.rawValue).")
        } catch {
            AppLogger.error("Failed to start MLX cleanup server: \(error.localizedDescription)")
            return
        }

        await waitForModelServer(
            baseURL: config.mlxBaseURL,
            timeoutMs: config.mlxStartTimeoutMs,
            probeTimeoutMs: min(config.maxCleanupTimeoutMs, 1000)
        )
    }

    private func waitForModelServer(baseURL: String, timeoutMs: Int, probeTimeoutMs: Int) async {
        let start = Date()
        while Date().timeIntervalSince(start) * 1000 < Double(timeoutMs) {
            if await fetchFirstModel(baseURL: baseURL, timeoutMs: probeTimeoutMs) != nil {
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private func mlxHost(from baseURL: String) -> String {
        URL(string: baseURL)?.host ?? "127.0.0.1"
    }

    private func mlxPort(from baseURL: String) -> String {
        if let port = URL(string: baseURL)?.port {
            return String(port)
        }
        return "8080"
    }

    private func callOpenAICompatible(
        baseURL: String,
        model: String?,
        timeoutMs: Int,
        apiKey: String?,
        text: String,
        mode: String,
        config: AppConfig
    ) async -> String? {
        guard let url = URL(string: "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/chat/completions") else {
            return nil
        }

        guard let selectedModel = model, !selectedModel.isEmpty else { return nil }

        let prompt = buildSystemPrompt(mode: mode, config: config)
        let body: [String: Any] = [
            "model": selectedModel,
            "temperature": 0,
            "max_tokens": max(40, min(180, (text.split(separator: " ").count * 4) + 20)),
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": text],
            ],
        ]

        guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = TimeInterval(max(timeoutMs, 200)) / 1000.0
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choices = json["choices"] as? [[String: Any]],
                let first = choices.first,
                let message = first["message"] as? [String: Any],
                let content = message["content"] as? String
            else {
                return nil
            }
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func fetchFirstModel(baseURL: String, timeoutMs: Int) async -> String? {
        guard let url = URL(string: "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/models") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = TimeInterval(max(timeoutMs, 200)) / 1000.0
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let dataList = json["data"] as? [[String: Any]],
                let first = dataList.first,
                let id = first["id"] as? String
            else {
                return nil
            }
            return id
        } catch {
            return nil
        }
    }

    private func buildSystemPrompt(mode: String, config: AppConfig) -> String {
        var prompt = config.cleanupSystemPrompt
            .replacingOccurrences(of: "{{agentName}}", with: "Assistant")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if prompt.isEmpty {
            prompt = AppConfig.defaultCleanupSystemPrompt.replacingOccurrences(of: "{{agentName}}", with: "Assistant")
        }
        if mode == "hinglish_roman" {
            prompt += "\n\nOutput Roman Hinglish only: Hindi words written in English letters. Do not translate Hindi words to English."
        }
        return prompt
    }

    private func validateRewrite(original: String, rewritten: String?, outputMode: String) -> String? {
        guard let rewritten else { return nil }
        var candidate = rewritten.replacingOccurrences(of: "\n", with: " ")
        candidate = LanguageNormalizer.collapseSpace(candidate)
        guard !candidate.isEmpty else { return nil }

        let lowered = candidate.lowercased()
        let blockedPrefixes = [
            "certainly",
            "sure",
            "of course",
            "here",
            "cleaned",
            "the cleaned",
            "final text",
            "output:",
            "result:",
        ]
        if blockedPrefixes.contains(where: { lowered.hasPrefix($0) }) {
            return nil
        }

        let sourceTokens = tokens(in: original)
        let targetTokens = tokens(in: candidate)
        guard !targetTokens.isEmpty else { return nil }

        if !sourceTokens.isEmpty {
            let overlap = overlapRatio(source: sourceTokens, target: targetTokens)
            if overlap < 0.45 { return nil }
            if targetTokens.count > (sourceTokens.count * 2) { return nil }
        }

        if outputMode == "hinglish_roman" {
            let keepWords: Set<String> = ["bhai", "kya", "kaise", "nahi", "hai", "haan", "yaar", "aap", "tum"]
            let sourceHas = !keepWords.intersection(Set(sourceTokens)).isEmpty
            if sourceHas && keepWords.intersection(Set(targetTokens)).isEmpty {
                return nil
            }
        }

        return candidate
    }

    private func tokens(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init)
    }

    private func overlapRatio(source: [String], target: [String]) -> Double {
        guard !source.isEmpty else { return 1.0 }
        let sourceSet = Set(source)
        let kept = target.filter { sourceSet.contains($0) }.count
        return Double(kept) / Double(source.count)
    }
}
