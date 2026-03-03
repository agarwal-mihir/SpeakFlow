import Domain
import Foundation
import Infra
import Testing

@Suite(.serialized)
struct CleanupServiceTests {
    final class FakeSecretStore: SecretStoreProtocol, @unchecked Sendable {
        var key: String?
        init(key: String?) { self.key = key }
        func getGroqAPIKey() throws -> String? { key }
        func setGroqAPIKey(_ value: String) throws { key = value }
        func deleteGroqAPIKey() throws { key = nil }
        func hasGroqAPIKey() -> Bool { key != nil }
    }

    final class StubURLProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            do {
                let (code, data) = try handler(request)
                let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    @Test func deterministicModeSkipsRemoteRewrite() async throws {
        let config: AppConfig = {
            var c = AppConfig()
            c.cleanupProvider = .deterministic
            return c
        }()

        let cleanup = CleanupService(configProvider: { config }, secretStore: FakeSecretStore(key: nil))
        let result = await cleanup.clean(
            TranscriptResult(rawText: "hello there", detectedLanguage: "en", confidence: 0.9, isMixedScript: false)
        )

        #expect(result.rewriteProvider == nil)
        #expect(result.text == "Hello there.")
    }

    @Test func priorityFallsBackFromGroqToLMStudio() async throws {
        let config: AppConfig = {
            var c = AppConfig()
            c.cleanupProvider = .priority
            c.lmstudioEnabled = true
            c.groqBaseURL = "https://groq.test/v1"
            c.lmstudioBaseURL = "http://lmstudio.test/v1"
            return c
        }()

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)

        StubURLProtocol.handler = { request in
            guard let url = request.url?.absoluteString else {
                return (500, Data())
            }
            if url.contains("groq.test") {
                return (500, Data("{}".utf8))
            }
            if url.contains("/models") {
                return (200, Data("{\"data\":[{\"id\":\"local-model\"}]}".utf8))
            }
            if url.contains("/chat/completions") {
                return (200, Data("{\"choices\":[{\"message\":{\"content\":\"Hello there!\"}}]}".utf8))
            }
            return (404, Data())
        }

        let cleanup = CleanupService(
            configProvider: { config },
            secretStore: FakeSecretStore(key: "gsk_test"),
            session: session
        )

        let result = await cleanup.clean(
            TranscriptResult(rawText: "hello there", detectedLanguage: "en", confidence: 0.9, isMixedScript: false)
        )

        #expect(result.rewriteProvider == "lmstudio")
        #expect(result.text == "Hello there!")
    }

    @Test func priorityUsesGroqEvenWhenLMStudioDisabled() async throws {
        let config: AppConfig = {
            var c = AppConfig()
            c.cleanupProvider = .priority
            c.lmstudioEnabled = false
            c.groqBaseURL = "https://groq.test/v1"
            c.groqModel = "meta-llama/llama-4-maverick-17b-128e-instruct"
            return c
        }()

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)

        StubURLProtocol.handler = { request in
            guard let url = request.url?.absoluteString else {
                return (500, Data())
            }
            if url.contains("groq.test"), url.contains("/chat/completions") {
                return (200, Data("{\"choices\":[{\"message\":{\"content\":\"Hello from groq.\"}}]}".utf8))
            }
            return (404, Data())
        }

        let cleanup = CleanupService(
            configProvider: { config },
            secretStore: FakeSecretStore(key: "gsk_test"),
            session: session
        )

        let result = await cleanup.clean(
            TranscriptResult(rawText: "hello from groq", detectedLanguage: "en", confidence: 0.9, isMixedScript: false)
        )

        #expect(result.rewriteProvider == "groq")
        #expect(result.text == "Hello from groq.")
    }
}
