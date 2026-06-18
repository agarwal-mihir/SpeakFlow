import Domain
import Foundation
import Quartz

public final class HotkeyService: HotkeyServiceProtocol, @unchecked Sendable {
    private static let functionKeycode = 63

    private var mode: HotkeyMode = .fnHold
    private var onPress: (@Sendable () -> Void)?
    private var onRelease: (@Sendable () -> Void)?
    private var onPasteLast: (@Sendable () -> Bool)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    private var fnDown = false
    private var comboDown = false

    public init() {}

    public func setHandlers(
        onPress: @escaping @Sendable () -> Void,
        onRelease: @escaping @Sendable () -> Void,
        onPasteLast: @escaping @Sendable () -> Bool
    ) {
        self.onPress = onPress
        self.onRelease = onRelease
        self.onPasteLast = onPasteLast
    }

    public func start(mode: HotkeyMode) {
        stop()
        self.mode = mode
        thread = Thread { [weak self] in
            self?.runEventTapLoop()
        }
        thread?.name = "speakflow-hotkey"
        thread?.start()
    }

    public func stop() {
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }
        eventTap = nil
        runLoopSource = nil
        runLoop = nil
        thread = nil
        fnDown = false
        comboDown = false
    }

    private func runEventTapLoop() {
        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passRetained(event) }
            let this = Unmanaged<HotkeyService>.fromOpaque(refcon).takeUnretainedValue()
            return this.handleEvent(type: type, event: event)
        }

        let ref = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: ref
        ) else {
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoop = CFRunLoopGetCurrent()

        if let runLoopSource, let runLoop {
            CFRunLoopAddSource(runLoop, runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let keycode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let modifiers = flags.intersection([.maskSecondaryFn, .maskCommand, .maskAlternate, .maskShift, .maskControl])

        if type == .keyDown && keycode == 9 && modifiers == [.maskCommand, .maskAlternate] {
            if onPasteLast?() == true {
                return nil
            }
            return Unmanaged.passRetained(event)
        }

        let fnPressed = flags.contains(.maskSecondaryFn)
        switch mode {
        case .fnHold:
            handleFnHold(type: type, fnPressed: fnPressed, keycode: keycode)
        case .fnSpaceHold:
            if handleFnSpace(type: type, fnPressed: fnPressed, keycode: keycode) {
                return nil
            }
        }

        return Unmanaged.passRetained(event)
    }

    private func handleFnHold(type: CGEventType, fnPressed: Bool, keycode: Int) {
        if keycode == Self.functionKeycode && !fnPressed {
            if type == .flagsChanged {
                if fnDown {
                    fnDown = false
                    onRelease?()
                } else {
                    fnDown = true
                    onPress?()
                }
            } else if type == .keyDown && !fnDown {
                fnDown = true
                onPress?()
            } else if type == .keyUp && fnDown {
                fnDown = false
                onRelease?()
            }
            return
        }

        if fnPressed && !fnDown {
            fnDown = true
            onPress?()
        } else if !fnPressed && fnDown {
            fnDown = false
            onRelease?()
        }
    }

    private func handleFnSpace(type: CGEventType, fnPressed: Bool, keycode: Int) -> Bool {
        if type == .keyDown && keycode == 49 && fnPressed {
            if !comboDown {
                comboDown = true
                onPress?()
            }
            return true
        }
        if type == .keyUp && keycode == 49 && comboDown {
            comboDown = false
            onRelease?()
            return true
        }
        return false
    }
}
