import Foundation

public enum SpeakFlowError: LocalizedError, Equatable {
    case microphonePermissionMissing
    case accessibilityPermissionMissing
    case inputMonitoringPermissionMissing
    case automationPermissionMissing
    case recordingFailed(String)
    case transcriptionFailed(String)
    case insertionFailed(String)
    case keychainFailure(String)
    case configurationInvalid(String)
    case storageFailure(String)

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionMissing:
            return "Microphone permission is required."
        case .accessibilityPermissionMissing:
            return "Accessibility permission is required."
        case .inputMonitoringPermissionMissing:
            return "Input Monitoring permission is required."
        case .automationPermissionMissing:
            return "Automation permission is required."
        case let .recordingFailed(detail):
            return "Unable to record audio: \(detail)"
        case let .transcriptionFailed(detail):
            return "Unable to transcribe audio: \(detail)"
        case let .insertionFailed(detail):
            return "Unable to insert text: \(detail)"
        case let .keychainFailure(detail):
            return "Keychain access failed: \(detail)"
        case let .configurationInvalid(detail):
            return "Invalid configuration: \(detail)"
        case let .storageFailure(detail):
            return "Data storage failed: \(detail)"
        }
    }
}
