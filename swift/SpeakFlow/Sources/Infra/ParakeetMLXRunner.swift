import Domain
import Foundation

public struct ParakeetMLXRunnerStatus: Equatable, Sendable {
    public let isAvailable: Bool
    public let path: String?
    public let message: String

    public init(isAvailable: Bool, path: String?, message: String) {
        self.isAvailable = isAvailable
        self.path = path
        self.message = message
    }
}

public struct ParakeetMLXRunner: Sendable {
    public struct Invocation: Sendable {
        public let executableURL: URL
        public let arguments: [String]
        public let environment: [String: String]

        public init(executableURL: URL, arguments: [String], environment: [String: String]) {
            self.executableURL = executableURL
            self.arguments = arguments
            self.environment = environment
        }
    }

    public struct Response: Sendable {
        public let stdout: String
        public let stderr: String
        public let exitCode: Int32

        public init(stdout: String, stderr: String, exitCode: Int32) {
            self.stdout = stdout
            self.stderr = stderr
            self.exitCode = exitCode
        }
    }

    private let executableProvider: @Sendable () -> URL?
    private let processRunner: @Sendable (Invocation) async throws -> Response

    public init(
        executableProvider: @escaping @Sendable () -> URL?,
        processRunner: @escaping @Sendable (Invocation) async throws -> Response
    ) {
        self.executableProvider = executableProvider
        self.processRunner = processRunner
    }

    public static let live = ParakeetMLXRunner(
        executableProvider: Self.resolvedExecutableURL,
        processRunner: Self.runProcess
    )

    public static func status() -> ParakeetMLXRunnerStatus {
        guard let url = resolvedExecutableURL() else {
            return ParakeetMLXRunnerStatus(
                isAvailable: false,
                path: nil,
                message: "Install speakflow-parakeet-mlx or set SPEAKFLOW_PARAKEET_MLX_RUNNER to its executable path."
            )
        }
        return ParakeetMLXRunnerStatus(
            isAvailable: true,
            path: url.path,
            message: "Using \(url.path)"
        )
    }

    public static func resolvedExecutableURL() -> URL? {
        let fileManager = FileManager.default
        let environmentPath = ProcessInfo.processInfo.environment["SPEAKFLOW_PARAKEET_MLX_RUNNER"]
        let candidates = [
            environmentPath,
            "/opt/homebrew/bin/speakflow-parakeet-mlx",
            "/usr/local/bin/speakflow-parakeet-mlx",
            "~/.local/bin/speakflow-parakeet-mlx"
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        for candidate in candidates {
            let path = expandTilde(candidate)
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }

    public func transcribe(audio: [Float], model: ParakeetModel, computeBackend: ComputeBackend) async throws -> TranscriptResult {
        guard let executableURL = executableProvider() else {
            throw SpeakFlowError.transcriptionFailed(
                "NVIDIA Parakeet requires a local MLX runner. Install speakflow-parakeet-mlx or set SPEAKFLOW_PARAKEET_MLX_RUNNER to its executable path."
            )
        }

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakFlow-Parakeet-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        let audioURL = workDirectory.appendingPathComponent("audio.wav")
        try Self.writeMonoPCM16WAV(samples: audio, sampleRate: 16_000, to: audioURL)

        let invocation = Invocation(
            executableURL: executableURL,
            arguments: [
                "--audio", audioURL.path,
                "--model", model.rawValue,
                "--device", computeBackend.runnerDeviceValue,
                "--format", "json"
            ],
            environment: Self.runnerEnvironment(for: computeBackend)
        )

        let response = try await processRunner(invocation)
        guard response.exitCode == 0 else {
            let detail = response.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SpeakFlowError.transcriptionFailed(
                detail.isEmpty ? "Parakeet MLX runner exited with status \(response.exitCode)." : detail
            )
        }

        return try Self.parse(response: response)
    }

    public static func parse(response: Response) throws -> TranscriptResult {
        let stdout = response.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = stdout.data(using: .utf8),
           let payload = try? JSONDecoder().decode(RunnerJSONResponse.self, from: data),
           let text = payload.text?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return TranscriptResult(
                rawText: text,
                detectedLanguage: payload.language ?? payload.detectedLanguage,
                confidence: payload.confidence.map { max(0, min(1, $0)) },
                isMixedScript: payload.isMixedScript ?? (mixedScriptRatio(text) >= 0.07)
            )
        }

        guard !stdout.isEmpty else {
            let stderr = response.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SpeakFlowError.transcriptionFailed(stderr.isEmpty ? "Parakeet MLX runner returned no transcript." : stderr)
        }

        return TranscriptResult(
            rawText: stdout,
            detectedLanguage: nil,
            confidence: nil,
            isMixedScript: mixedScriptRatio(stdout) >= 0.07
        )
    }

    private static func runProcess(_ invocation: Invocation) async throws -> Response {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = invocation.executableURL
            process.arguments = invocation.arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.environment = ProcessInfo.processInfo.environment.merging(invocation.environment) { _, new in new }

            try process.run()
            process.waitUntilExit()

            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return Response(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
        }.value
    }

    private static func writeMonoPCM16WAV(samples: [Float], sampleRate: UInt32, to url: URL) throws {
        let bytesPerSample = UInt16(2)
        let channelCount = UInt16(1)
        let byteRate = sampleRate * UInt32(channelCount) * UInt32(bytesPerSample)
        let blockAlign = channelCount * bytesPerSample
        let audioByteCount = UInt32(samples.count) * UInt32(bytesPerSample)

        var data = Data()
        data.appendASCII("RIFF")
        data.appendLittleEndian(36 + audioByteCount)
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(channelCount)
        data.appendLittleEndian(sampleRate)
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(UInt16(16))
        data.appendASCII("data")
        data.appendLittleEndian(audioByteCount)

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let intSample = Int16(clamped * Float(Int16.max))
            data.appendLittleEndian(UInt16(bitPattern: intSample))
        }

        try data.write(to: url, options: .atomic)
    }

    private static func runnerEnvironment(for computeBackend: ComputeBackend) -> [String: String] {
        var environment = ["SPEAKFLOW_COMPUTE_BACKEND": computeBackend.rawValue]
        switch computeBackend {
        case .automatic:
            break
        case .cpu:
            environment["MLX_DEVICE"] = "cpu"
        case .gpu:
            environment["MLX_DEVICE"] = "gpu"
        }
        return environment
    }

    private static func expandTilde(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(String(path.dropFirst(2)))
            .path
    }

    private static func mixedScriptRatio(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        let total = Double(text.count)
        let devCount = Double(text.unicodeScalars.filter { (0x0900...0x097F).contains(Int($0.value)) }.count)
        return devCount / total
    }
}

private struct RunnerJSONResponse: Decodable {
    let text: String?
    let language: String?
    let detectedLanguage: String?
    let confidence: Double?
    let isMixedScript: Bool?
}

private extension ComputeBackend {
    var runnerDeviceValue: String {
        switch self {
        case .automatic: return "auto"
        case .cpu: return "cpu"
        case .gpu: return "gpu"
        }
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLittleEndian(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
