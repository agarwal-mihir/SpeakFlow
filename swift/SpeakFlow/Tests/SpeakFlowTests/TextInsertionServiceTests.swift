import Domain
import Foundation
import Testing
@testable import Platform

struct TextInsertionServiceTests {
    @Test func insertSuccessRestoresClipboard() {
        final class Box: @unchecked Sendable {
            var clipboard = "original"
            var pasteAttempts = 0
        }
        let box = Box()

        let service = TextInsertionService(
            pasteRetry: 0,
            getClipboard: { box.clipboard },
            setClipboard: { box.clipboard = $0 },
            pasteSystem: { _ in
                box.pasteAttempts += 1
                return true
            },
            pasteQuartz: { false }
        )

        let result = service.insert(
            text: "hello",
            targetPID: nil,
            restoreClipboard: true,
            keepOnFailure: true
        )

        #expect(result.inserted)
        #expect(box.pasteAttempts == 1)
        #expect(box.clipboard == "original")
    }

    @Test func insertFailureKeepsDictationInClipboardWhenConfigured() {
        final class Box: @unchecked Sendable {
            var clipboard = "before"
        }
        let box = Box()

        let service = TextInsertionService(
            pasteRetry: 0,
            getClipboard: { box.clipboard },
            setClipboard: { box.clipboard = $0 },
            pasteSystem: { _ in false },
            pasteQuartz: { false }
        )

        let result = service.insert(
            text: "dictated text",
            targetPID: nil,
            restoreClipboard: true,
            keepOnFailure: true
        )

        #expect(result.inserted == false)
        #expect(result.usedClipboardFallback)
        #expect(box.clipboard == "dictated text")
    }

    @Test func insertFailureRestoresClipboardWhenFallbackDisabled() {
        final class Box: @unchecked Sendable {
            var clipboard = "before"
        }
        let box = Box()

        let service = TextInsertionService(
            pasteRetry: 0,
            getClipboard: { box.clipboard },
            setClipboard: { box.clipboard = $0 },
            pasteSystem: { _ in false },
            pasteQuartz: { false }
        )

        let result = service.insert(
            text: "dictated text",
            targetPID: nil,
            restoreClipboard: true,
            keepOnFailure: false
        )

        #expect(result.inserted == false)
        #expect(result.usedClipboardFallback == false)
        #expect(box.clipboard == "before")
    }

    @Test func insertFocusesTargetBeforePasting() {
        final class Box: @unchecked Sendable {
            var clipboard = "original"
            var focusedPID: Int32?
            var pasteAttempts = 0
        }
        let box = Box()

        let service = TextInsertionService(
            pasteRetry: 0,
            getClipboard: { box.clipboard },
            setClipboard: { box.clipboard = $0 },
            pasteSystem: { _ in
                box.pasteAttempts += 1
                return true
            },
            pasteQuartz: { false },
            focusTarget: { pid in
                box.focusedPID = pid
                return true
            }
        )

        let result = service.insert(
            text: "targeted paste",
            targetPID: 42,
            restoreClipboard: true,
            keepOnFailure: true
        )

        #expect(result.inserted)
        #expect(box.focusedPID == 42)
        #expect(box.pasteAttempts == 1)
        #expect(box.clipboard == "original")
    }

    @Test func missingAccessibilityKeepsDictationInClipboardWithSpecificError() {
        final class Box: @unchecked Sendable {
            var clipboard = "before"
            var pasteAttempts = 0
        }
        let box = Box()

        let service = TextInsertionService(
            pasteRetry: 0,
            getClipboard: { box.clipboard },
            setClipboard: { box.clipboard = $0 },
            pasteSystem: { _ in
                box.pasteAttempts += 1
                return true
            },
            pasteQuartz: { false },
            accessibilityTrusted: { false }
        )

        let result = service.insert(
            text: "dictated text",
            targetPID: 42,
            restoreClipboard: true,
            keepOnFailure: true
        )

        #expect(result.inserted == false)
        #expect(result.usedClipboardFallback)
        #expect(result.errorMessage == "Accessibility permission is required for auto-paste. Clipboard now contains last dictation.")
        #expect(box.clipboard == "dictated text")
        #expect(box.pasteAttempts == 0)
    }
}
