import Domain
import Foundation

public final class CleanupService: CleanupServiceProtocol, @unchecked Sendable {
    private let configProvider: @Sendable () -> AppConfig
    private let secretStore: SecretStoreProtocol
    private let session: URLSession

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

        var providers = ["groq"]
        if config.lmstudioEnabled {
            providers.append("lmstudio")
        }

        for provider in providers {
            let rewritten = await rewrite(
                provider: provider,
                text: deterministic,
                mode: mode,
                config: config
            )
            let validated = validateRewrite(original: deterministic, rewritten: rewritten, outputMode: mode)
            if let validated {
                AppLogger.info("Cleanup rewrite provider used: \(provider).")
                return CleanupResult(text: validated, outputMode: mode, rewriteProvider: provider)
            }
        }

        AppLogger.info("Cleanup rewrite unavailable/invalid, deterministic fallback used.")
        return CleanupResult(text: deterministic, outputMode: mode, rewriteProvider: nil)
    }

    private func rewrite(provider: String, text: String, mode: String, config: AppConfig) async -> String? {
        switch provider {
        case "groq":
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
                autoStartLMStudio: false
            )
        case "lmstudio":
            return await callOpenAICompatible(
                baseURL: config.lmstudioBaseURL,
                model: nil,
                timeoutMs: config.maxCleanupTimeoutMs,
                apiKey: nil,
                text: text,
                mode: mode,
                autoStartLMStudio: config.lmstudioAutoStart,
                lmStudioStartTimeoutMs: config.lmstudioStartTimeoutMs
            )
        default:
            return nil
        }
    }

    private func callOpenAICompatible(
        baseURL: String,
        model: String?,
        timeoutMs: Int,
        apiKey: String?,
        text: String,
        mode: String,
        autoStartLMStudio: Bool,
        lmStudioStartTimeoutMs: Int = 8000
    ) async -> String? {
        guard let url = URL(string: "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/chat/completions") else {
            return nil
        }

        var selectedModel = model
        if selectedModel == nil {
            selectedModel = await resolveLMStudioModel(
                baseURL: baseURL,
                timeoutMs: timeoutMs,
                autoStart: autoStartLMStudio,
                startTimeoutMs: lmStudioStartTimeoutMs
            )
        }
        guard let selectedModel, !selectedModel.isEmpty else { return nil }

        let prompt = buildSystemPrompt(mode: mode)
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

    private func resolveLMStudioModel(baseURL: String, timeoutMs: Int, autoStart: Bool, startTimeoutMs: Int) async -> String? {
        if let model = await fetchFirstModel(baseURL: baseURL, timeoutMs: timeoutMs) {
            return model
        }
        if autoStart {
            _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/open"), arguments: ["-a", "LM Studio"])
            let start = Date()
            while Date().timeIntervalSince(start) * 1000 < Double(startTimeoutMs) {
                if let model = await fetchFirstModel(baseURL: baseURL, timeoutMs: timeoutMs) {
                    return model
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        return nil
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

    private func buildSystemPrompt(mode: String) -> String {
        if mode == "hinglish_roman" {
            return """
            You are a strict dictation text normalizer.
            Output Roman Hinglish only. Do not translate Hindi words to English.
            Only fix spacing, punctuation, casing, and stretched letters.
            Return one plain line only.
            """
        }
        return """
        You are a strict dictation text normalizer.
        Keep same wording; do not paraphrase.
        Only fix spacing, punctuation, and casing.
        Return one plain line only.
        """
    }

    private func validateRewrite(original: String, rewritten: String?, outputMode: String) -> String? {
        guard let rewritten else { return nil }
        var candidate = rewritten.replacingOccurrences(of: "\n", with: " ")
        candidate = LanguageNormalizer.collapseSpace(candidate)
        guard !candidate.isEmpty else { return nil }

        let lowered = candidate.lowercased()
        if lowered.hasPrefix("certainly") || lowered.hasPrefix("here") || lowered.hasPrefix("cleaned") {
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
