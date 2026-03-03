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
}
