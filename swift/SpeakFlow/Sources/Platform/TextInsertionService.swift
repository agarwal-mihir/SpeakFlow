import AppKit
import Domain
import Foundation
import Infra
import Quartz

public final class TextInsertionService: TextInsertionServiceProtocol, @unchecked Sendable {
    private let pasteRetry: Int
    private let getClipboardOverride: (() -> String)?
    private let setClipboardOverride: ((String) -> Void)?
    private let pasteSystemOverride: ((Int32?) -> Bool)?
    private let pasteQuartzOverride: (() -> Bool)?
    private let focusTargetOverride: ((Int32?) -> Bool)?
    private let accessibilityTrustedOverride: (() -> Bool)?

    public init(pasteRetry: Int = 1) {
        self.pasteRetry = max(0, pasteRetry)
        self.getClipboardOverride = nil
        self.setClipboardOverride = nil
        self.pasteSystemOverride = nil
        self.pasteQuartzOverride = nil
        self.focusTargetOverride = nil
        self.accessibilityTrustedOverride = nil
    }

    init(
        pasteRetry: Int,
        getClipboard: @escaping () -> String,
        setClipboard: @escaping (String) -> Void,
        pasteSystem: @escaping (Int32?) -> Bool,
        pasteQuartz: @escaping () -> Bool,
        focusTarget: ((Int32?) -> Bool)? = nil,
        accessibilityTrusted: (() -> Bool)? = { true }
    ) {
        self.pasteRetry = max(0, pasteRetry)
        self.getClipboardOverride = getClipboard
        self.setClipboardOverride = setClipboard
        self.pasteSystemOverride = pasteSystem
        self.pasteQuartzOverride = pasteQuartz
        self.focusTargetOverride = focusTarget
        self.accessibilityTrustedOverride = accessibilityTrusted
    }

    public func insert(text: String, targetPID: Int32?, restoreClipboard: Bool, keepOnFailure: Bool) -> InsertResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return InsertResult(inserted: false, usedClipboardFallback: false, errorMessage: nil)
        }

        let original = getClipboardText()
        setClipboardText(trimmed)
        Thread.sleep(forTimeInterval: 0.05)

        let accessibilityTrusted = ensureAccessibilityTrusted()
        let pasted = accessibilityTrusted && pasteWithRetry(targetPID: targetPID)
        if pasted {
            if restoreClipboard {
                Thread.sleep(forTimeInterval: 0.45)
                setClipboardText(original)
            }
            return InsertResult(inserted: true, usedClipboardFallback: false, errorMessage: nil)
        }

        if restoreClipboard && !keepOnFailure {
            setClipboardText(original)
        }

        if keepOnFailure {
            let message = accessibilityTrusted
                ? "Auto-paste failed. Clipboard now contains last dictation."
                : "Accessibility permission is required for auto-paste. Clipboard now contains last dictation."
            return InsertResult(
                inserted: false,
                usedClipboardFallback: true,
                errorMessage: message
            )
        }
        let message = accessibilityTrusted ? "Failed to paste text" : "Accessibility permission is required for auto-paste."
        return InsertResult(inserted: false, usedClipboardFallback: false, errorMessage: message)
    }

    public func pasteLastDictation(text: String, targetPID: Int32?) -> InsertResult {
        insert(text: text, targetPID: targetPID, restoreClipboard: false, keepOnFailure: true)
    }

    private func getClipboardText() -> String {
        if let getClipboardOverride {
            return getClipboardOverride()
        }
        let board = NSPasteboard.general
        return board.string(forType: .string) ?? ""
    }

    private func setClipboardText(_ text: String) {
        if let setClipboardOverride {
            setClipboardOverride(text)
            return
        }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }

    private func pasteWithRetry(targetPID: Int32?) -> Bool {
        for attempt in 0...pasteRetry {
            _ = focusTargetApplication(targetPID)
            if pasteWithQuartz() || pasteWithSystemEvents(targetPID: targetPID) {
                Thread.sleep(forTimeInterval: 0.12)
                return true
            }
            if attempt < pasteRetry {
                Thread.sleep(forTimeInterval: 0.15)
            }
        }
        AppLogger.error("Auto-paste failed after \(pasteRetry + 1) attempt(s). targetPID=\(targetPID.map(String.init) ?? "nil") axTrusted=\(AXIsProcessTrusted())")
        return false
    }

    private func ensureAccessibilityTrusted() -> Bool {
        if let accessibilityTrustedOverride {
            return accessibilityTrustedOverride()
        }
        if AXIsProcessTrusted() {
            return true
        }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        AppLogger.error("Auto-paste blocked because Accessibility permission is missing for /Applications/SpeakFlow.app.")
        return false
    }

    private func pasteWithSystemEvents(targetPID: Int32?) -> Bool {
        if let pasteSystemOverride {
            return pasteSystemOverride(targetPID)
        }
        guard AXIsProcessTrusted() else {
            return false
        }

        let source = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            AppLogger.error("System Events paste fallback failed: \(error.localizedDescription)")
            return false
        }
    }

    private func pasteWithQuartz() -> Bool {
        if let pasteQuartzOverride {
            return pasteQuartzOverride()
        }
        guard AXIsProcessTrusted() else {
            return false
        }
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        Thread.sleep(forTimeInterval: 0.008)
        up.post(tap: .cgSessionEventTap)
        Thread.sleep(forTimeInterval: 0.020)
        return true
    }

    private func focusTargetApplication(_ targetPID: Int32?) -> Bool {
        if let focusTargetOverride {
            return focusTargetOverride(targetPID)
        }
        guard
            let targetPID,
            let app = NSRunningApplication(processIdentifier: targetPID),
            app.bundleIdentifier != Bundle.main.bundleIdentifier,
            !app.isTerminated
        else {
            return false
        }
        if app.isActive {
            return true
        }

        let activated = app.activate(options: [])
        let deadline = Date().addingTimeInterval(0.6)
        while Date() < deadline {
            if app.isActive {
                return true
            }
            Thread.sleep(forTimeInterval: 0.03)
        }
        if !activated || !app.isActive {
            AppLogger.error("Failed to activate paste target. pid=\(targetPID) app=\(app.localizedName ?? "unknown") activated=\(activated)")
        }
        return app.isActive
    }

}
