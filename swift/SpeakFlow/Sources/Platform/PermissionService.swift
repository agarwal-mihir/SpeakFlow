import AVFoundation
import ApplicationServices
import Domain
import Foundation

public final class PermissionService: PermissionServiceProtocol, @unchecked Sendable {
    public init() {}

    public func checkAll() -> PermissionState {
        PermissionState(
            microphone: checkMicrophone(),
            accessibility: checkAccessibility(),
            inputMonitoring: checkInputMonitoring()
        )
    }

    public func requestMicrophone() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    public func requestAccessibilityPrompt() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func requestInputMonitoringPrompt() -> Bool {
        if #available(macOS 10.15, *) {
            _ = CGRequestListenEventAccess()
        }
        return checkInputMonitoring()
    }

    public func openMicrophoneSettings() {
        openPrivacy("Microphone")
    }

    public func openAccessibilitySettings() {
        openPrivacy("Accessibility")
    }

    public func openInputMonitoringSettings() {
        openPrivacy("ListenEvent")
    }

    private func checkMicrophone() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func checkAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    private func checkInputMonitoring() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightListenEventAccess()
        }
        return false
    }

    private func openPrivacy(_ section: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["x-apple.systempreferences:com.apple.preference.security?Privacy_\(section)"]
        try? process.run()
    }
}
