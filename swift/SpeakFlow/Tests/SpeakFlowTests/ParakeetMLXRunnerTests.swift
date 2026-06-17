import Domain
import Foundation
import Infra
import Testing

struct ParakeetMLXRunnerTests {
    @Test func parsesJSONRunnerOutput() throws {
        let response = ParakeetMLXRunner.Response(
            stdout: #"{"text":"hello there","language":"en","confidence":0.84}"#,
            stderr: "",
            exitCode: 0
        )

        let result = try ParakeetMLXRunner.parse(response: response)

        #expect(result.rawText == "hello there")
        #expect(result.detectedLanguage == "en")
        #expect(result.confidence == 0.84)
        #expect(result.isMixedScript == false)
    }

    @Test func fallsBackToPlainTextRunnerOutput() throws {
        let response = ParakeetMLXRunner.Response(
            stdout: "plain transcript\n",
            stderr: "",
            exitCode: 0
        )

        let result = try ParakeetMLXRunner.parse(response: response)

        #expect(result.rawText == "plain transcript")
        #expect(result.detectedLanguage == nil)
        #expect(result.confidence == nil)
    }

    @Test func invokesRunnerWithWAVModelAndDevice() async throws {
        let runner = ParakeetMLXRunner(
            executableProvider: { URL(fileURLWithPath: "/usr/bin/true") },
            processRunner: { invocation in
                #expect(invocation.executableURL.path == "/usr/bin/true")
                #expect(invocation.arguments.contains("--audio"))
                #expect(invocation.arguments.contains("parakeet-unified-en-0.6b"))
                #expect(invocation.arguments.contains("gpu"))
                #expect(invocation.environment["MLX_DEVICE"] == "gpu")

                let audioIndex = try #require(invocation.arguments.firstIndex(of: "--audio"))
                let audioPath = invocation.arguments[audioIndex + 1]
                let data = try Data(contentsOf: URL(fileURLWithPath: audioPath))
                #expect(String(data: data.prefix(4), encoding: .ascii) == "RIFF")
                #expect(String(data: data.dropFirst(8).prefix(4), encoding: .ascii) == "WAVE")

                return ParakeetMLXRunner.Response(
                    stdout: #"{"text":"runner transcript","detectedLanguage":"en","confidence":0.91}"#,
                    stderr: "",
                    exitCode: 0
                )
            }
        )
        let service = ParakeetMLXTranscriptionService(
            model: .unifiedEN06B,
            computeBackend: .gpu,
            runner: runner
        )

        let result = try await service.transcribe([0, 0.25, -0.25])

        #expect(result.rawText == "runner transcript")
        #expect(result.detectedLanguage == "en")
        #expect(result.confidence == 0.91)
    }

    @Test func missingRunnerReturnsInstallGuidance() async throws {
        let runner = ParakeetMLXRunner(
            executableProvider: { nil },
            processRunner: { _ in
                ParakeetMLXRunner.Response(stdout: "", stderr: "", exitCode: 0)
            }
        )
        let service = ParakeetMLXTranscriptionService(
            model: .tdt06BV3,
            computeBackend: .automatic,
            runner: runner
        )

        do {
            _ = try await service.transcribe([0.1])
            #expect(Bool(false))
        } catch let error as SpeakFlowError {
            #expect(error.errorDescription?.contains("local MLX runner") == true)
            #expect(error.errorDescription?.contains("SPEAKFLOW_PARAKEET_MLX_RUNNER") == true)
        }
    }
}
