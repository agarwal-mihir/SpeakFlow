import AppKit
import Domain
import Foundation
import Quartz

public final class TextInsertionService: TextInsertionServiceProtocol, @unchecked Sendable {
    private let pasteRetry: Int
    private let getClipboardOverride: (() -> String)?
    private let setClipboardOverride: ((String) -> Void)?
    private let pasteSystemOverride: ((Int32?) -> Bool)?
    private let pasteQuartzOverride: (() -> Bool)?

    public init(pasteRetry: Int = 1) {
        self.pasteRetry = max(0, pasteRetry)
        self.getClipboardOverride = nil
        self.setClipboardOverride = nil
        self.pasteSystemOverride = nil
        self.pasteQuartzOverride = nil
    }

    init(
        pasteRetry: Int,
        getClipboard: @escaping () -> String,
        setClipboard: @escaping (String) -> Void,
        pasteSystem: @escaping (Int32?) -> Bool,
        pasteQuartz: @escaping () -> Bool
    ) {
        self.pasteRetry = max(0, pasteRetry)
        self.getClipboardOverride = getClipboard
        self.setClipboardOverride = setClipboard
        self.pasteSystemOverride = pasteSystem
        self.pasteQuartzOverride = pasteQuartz
    }

    public func insert(text: String, targetPID: Int32?, restoreClipboard: Bool, keepOnFailure: Bool) -> InsertResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return InsertResult(inserted: false, usedClipboardFallback: false, errorMessage: nil)
        }

        let original = getClipboardText()
        setClipboardText(trimmed)
        Thread.sleep(forTimeInterval: 0.05)

        let pasted = pasteWithRetry(targetPID: targetPID)
        if pasted {
            if restoreClipboard {
                Thread.sleep(forTimeInterval: 0.2)
                setClipboardText(original)
            }
            return InsertResult(inserted: true, usedClipboardFallback: false, errorMessage: nil)
        }

        if restoreClipboard && !keepOnFailure {
            setClipboardText(original)
        }

        if keepOnFailure {
            return InsertResult(
                inserted: false,
                usedClipboardFallback: true,
                errorMessage: "Auto-paste failed. Clipboard now contains last dictation."
            )
        }
        return InsertResult(inserted: false, usedClipboardFallback: false, errorMessage: "Failed to paste text")
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
            if pasteWithSystemEvents(targetPID: targetPID) || pasteWithQuartz() {
                Thread.sleep(forTimeInterval: 0.06)
                return true
            }
            if attempt < pasteRetry {
                Thread.sleep(forTimeInterval: 0.08)
            }
        }
        return false
    }

    private func pasteWithSystemEvents(targetPID: Int32?) -> Bool {
        if let pasteSystemOverride {
            return pasteSystemOverride(targetPID)
        }
        var script = "tell application \"System Events\" to keystroke \"v\" using command down"
        if let targetPID {
            script = """
            tell application "System Events"
              try
                set targetProc to first process whose unix id is \(targetPID)
                if frontmost of targetProc then
                  tell targetProc to keystroke "v" using command down
                else
                  keystroke "v" using command down
                end if
              on error
                keystroke "v" using command down
              end try
            end tell
            """
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func pasteWithQuartz() -> Bool {
        if let pasteQuartzOverride {
            return pasteQuartzOverride()
        }
        guard
            let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false)
        else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    public func preflightAutomationPermission() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"System Events\" to get name of first process"]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
