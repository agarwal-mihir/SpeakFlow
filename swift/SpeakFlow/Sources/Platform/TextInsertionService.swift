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
            if pasteWithQuartz() || pasteWithSystemEventsIfOverridden(targetPID: targetPID) {
                Thread.sleep(forTimeInterval: 0.06)
                return true
            }
            if attempt < pasteRetry {
                Thread.sleep(forTimeInterval: 0.08)
            }
        }
        return false
    }

    private func pasteWithSystemEventsIfOverridden(targetPID: Int32?) -> Bool {
        if let pasteSystemOverride {
            return pasteSystemOverride(targetPID)
        }
        return false
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

}
