import AVFoundation
import ApplicationServices
import Domain
import Foundation

public final class PermissionService: PermissionServiceProtocol, @unchecked Sendable {
    private let inserter: TextInsertionService

    public init(inserter: TextInsertionService) {
        self.inserter = inserter
    }

    public func checkAll() -> PermissionState {
        PermissionState(
            microphone: checkMicrophone(),
            accessibility: checkAccessibility(),
            inputMonitoring: checkInputMonitoring(),
            automation: checkAutomation()
        )
    }

    public func requestMicrophone() -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .authorized { return true }
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
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

    public func requestAutomationPrompt() -> Bool {
        inserter.preflightAutomationPermission()
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

    public func openAutomationSettings() {
        openPrivacy("Automation")
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

    private func checkAutomation() -> Bool {
        inserter.preflightAutomationPermission()
    }

    private func openPrivacy(_ section: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["x-apple.systempreferences:com.apple.preference.security?Privacy_\(section)"]
        try? process.run()
    }
}
