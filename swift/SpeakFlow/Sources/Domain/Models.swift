import Foundation

public enum HotkeyMode: String, Codable, CaseIterable, Sendable {
    case fnHold = "fn_hold"
    case fnSpaceHold = "fn_space_hold"
}

public enum LanguageMode: String, Codable, CaseIterable, Sendable {
    case auto
    case english
    case hinglishRoman = "hinglish_roman"
}

public enum CleanupProvider: String, Codable, CaseIterable, Sendable {
    case priority
    case deterministic
}

public enum TranscriptionProvider: String, Codable, CaseIterable, Sendable {
    case whisperKit = "whisperkit"
    case parakeetMLX = "parakeet_mlx"

    public var title: String {
        switch self {
        case .whisperKit: return "WhisperKit"
        case .parakeetMLX: return "NVIDIA Parakeet"
        }
    }

    public var subtitle: String {
        switch self {
        case .whisperKit: return "Core ML Whisper models"
        case .parakeetMLX: return "MLX Parakeet ASR"
        }
    }
}

public enum ComputeBackend: String, Codable, CaseIterable, Sendable {
    case automatic
    case cpu
    case gpu

    public var title: String {
        switch self {
        case .automatic: return "Auto"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        }
    }
}

public enum WhisperModel: String, Codable, CaseIterable, Sendable {
    case tiny
    case base
    case small
    case medium
    case largeV3 = "large-v3"
    case largeV3Turbo = "large-v3-turbo"

    public var title: String {
        switch self {
        case .tiny: return "Tiny"
        case .base: return "Base"
        case .small: return "Small"
        case .medium: return "Medium"
        case .largeV3: return "Large v3"
        case .largeV3Turbo: return "Large v3 Turbo"
        }
    }

    public var sizeLabel: String {
        switch self {
        case .tiny: return "75 MB"
        case .base: return "142 MB"
        case .small: return "466 MB"
        case .medium: return "1.5 GB"
        case .largeV3: return "3 GB"
        case .largeV3Turbo: return "1.6 GB"
        }
    }

    public var qualityLabel: String {
        switch self {
        case .tiny: return "Fastest"
        case .base: return "Balanced"
        case .small: return "Better quality"
        case .medium: return "High quality"
        case .largeV3: return "Best quality"
        case .largeV3Turbo: return "Fast, high quality"
        }
    }
}

public enum ParakeetModel: String, Codable, CaseIterable, Sendable {
    case tdt06BV3 = "parakeet-tdt-0.6b-v3"
    case unifiedEN06B = "parakeet-unified-en-0.6b"

    public var title: String {
        switch self {
        case .tdt06BV3: return "Parakeet TDT 0.6B"
        case .unifiedEN06B: return "Parakeet Unified EN 0.6B"
        }
    }

    public var sizeLabel: String {
        switch self {
        case .tdt06BV3: return "680 MB"
        case .unifiedEN06B: return "631 MB"
        }
    }

    public var languageLabel: String {
        switch self {
        case .tdt06BV3: return "Multilingual"
        case .unifiedEN06B: return "English"
        }
    }
}

public enum ServiceState: String, Sendable {
    case idle = "Idle"
    case recording = "Recording"
    case transcribing = "Transcribing"
    case error = "Error"
}

public struct AppConfig: Codable, Equatable, Sendable {
    public var hotkeyMode: HotkeyMode = .fnHold
    public var languageMode: LanguageMode = .auto
    public var transcriptionProvider: TranscriptionProvider = .whisperKit
    public var whisperModel: WhisperModel = .largeV3
    public var parakeetModel: ParakeetModel = .tdt06BV3
    public var computeBackend: ComputeBackend = .automatic
    public var lmstudioEnabled: Bool = true
    public var lmstudioBaseURL: String = "http://127.0.0.1:1234/v1"
    public var lmstudioAutoStart: Bool = true
    public var lmstudioStartTimeoutMs: Int = 8000
    public var cleanupProvider: CleanupProvider = .priority
    public var groqBaseURL: String = "https://api.groq.com/openai/v1"
    public var groqModel: String = "meta-llama/llama-4-maverick-17b-128e-instruct"
    public var maxCleanupTimeoutMs: Int = 1000
    public var floatingIndicatorEnabled: Bool = true
    public var floatingIndicatorHideDelayMs: Int = 1000
    public var floatingIndicatorOriginX: Double?
    public var floatingIndicatorOriginY: Double?
    public var pasteLastShortcutEnabled: Bool = true
    public var pasteFailureKeepDictationInClipboard: Bool = true

    public init() {}
}

public struct PermissionState: Equatable, Sendable {
    public var microphone: Bool
    public var accessibility: Bool
    public var inputMonitoring: Bool

    public var dictationReady: Bool {
        microphone && inputMonitoring
    }

    public var allGranted: Bool {
        microphone && accessibility && inputMonitoring
    }

    public init(
        microphone: Bool = false,
        accessibility: Bool = false,
        inputMonitoring: Bool = false
    ) {
        self.microphone = microphone
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
    }
}

public struct TranscriptResult: Equatable, Sendable {
    public var rawText: String
    public var detectedLanguage: String?
    public var confidence: Double?
    public var isMixedScript: Bool

    public init(rawText: String, detectedLanguage: String?, confidence: Double?, isMixedScript: Bool) {
        self.rawText = rawText
        self.detectedLanguage = detectedLanguage
        self.confidence = confidence
        self.isMixedScript = isMixedScript
    }
}

public struct CleanupResult: Equatable, Sendable {
    public var text: String
    public var outputMode: String
    public var rewriteProvider: String?

    public init(text: String, outputMode: String, rewriteProvider: String?) {
        self.text = text
        self.outputMode = outputMode
        self.rewriteProvider = rewriteProvider
    }
}

public struct InsertResult: Equatable, Sendable {
    public var inserted: Bool
    public var usedClipboardFallback: Bool
    public var errorMessage: String?

    public init(inserted: Bool, usedClipboardFallback: Bool, errorMessage: String?) {
        self.inserted = inserted
        self.usedClipboardFallback = usedClipboardFallback
        self.errorMessage = errorMessage
    }
}

public struct HistoryRecord: Identifiable, Equatable, Sendable {
    public var id: Int
    public var createdAt: String
    public var rawText: String
    public var finalText: String
    public var detectedLanguage: String?
    public var confidence: Double?
    public var outputMode: String
    public var sourceApp: String?

    public init(
        id: Int,
        createdAt: String,
        rawText: String,
        finalText: String,
        detectedLanguage: String?,
        confidence: Double?,
        outputMode: String,
        sourceApp: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.rawText = rawText
        self.finalText = finalText
        self.detectedLanguage = detectedLanguage
        self.confidence = confidence
        self.outputMode = outputMode
        self.sourceApp = sourceApp
    }
}

public struct HistoryStats: Equatable, Sendable {
    public var totalCount: Int
    public var latestCreatedAt: String
    public var latestSourceApp: String
    public var topSourceApp: String
    public var topSourceAppCount: Int

    public init(totalCount: Int, latestCreatedAt: String, latestSourceApp: String, topSourceApp: String, topSourceAppCount: Int) {
        self.totalCount = totalCount
        self.latestCreatedAt = latestCreatedAt
        self.latestSourceApp = latestSourceApp
        self.topSourceApp = topSourceApp
        self.topSourceAppCount = topSourceAppCount
    }
}

public struct DictationUtterance: Sendable {
    public var audioSamples: [Float]
    public var sourceApp: String?
    public var sourcePID: Int32?

    public init(audioSamples: [Float], sourceApp: String?, sourcePID: Int32?) {
        self.audioSamples = audioSamples
        self.sourceApp = sourceApp
        self.sourcePID = sourcePID
    }
}
