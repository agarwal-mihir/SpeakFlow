import AppKit
import Domain
import Foundation
import Infra
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
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private let stateLock = NSLock()

    private var fnDown = false
    private var functionModifierDown = false
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
        installGlobalFlagsMonitor()
        thread = Thread { [weak self] in
            self?.runEventTapLoop()
        }
        thread?.name = "speakflow-hotkey"
        thread?.start()
        AppLogger.info("Hotkey service starting. mode=\(mode.rawValue)")
    }

    public func stop() {
        removeGlobalFlagsMonitor()
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
        functionModifierDown = false
        comboDown = false
    }

    private func installGlobalFlagsMonitor() {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                installGlobalFlagsMonitorOnMain()
            }
        } else {
            Task { @MainActor [weak self] in
                self?.installGlobalFlagsMonitorOnMain()
            }
        }
    }

    private func removeGlobalFlagsMonitor() {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                removeGlobalFlagsMonitorOnMain()
            }
        } else {
            Task { @MainActor [weak self] in
                self?.removeGlobalFlagsMonitorOnMain()
            }
        }
    }

    @MainActor
    private func installGlobalFlagsMonitorOnMain() {
        guard globalFlagsMonitor == nil else { return }
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleGlobalFlagsChanged(event)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleGlobalFlagsChanged(event)
            return event
        }
        if globalFlagsMonitor == nil {
            AppLogger.error("Failed to install global Fn flags monitor.")
        } else {
            AppLogger.info("Global Fn flags monitor installed.")
        }
        if localFlagsMonitor == nil {
            AppLogger.error("Failed to install local Fn flags monitor.")
        } else {
            AppLogger.info("Local Fn flags monitor installed.")
        }
    }

    @MainActor
    private func removeGlobalFlagsMonitorOnMain() {
        if let monitor = globalFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            globalFlagsMonitor = nil
        }
        if let monitor = localFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            localFlagsMonitor = nil
        }
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
            AppLogger.error("Failed to create hotkey event tap. Input Monitoring may need to be re-granted for /Applications/SpeakFlow.app.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoop = CFRunLoopGetCurrent()

        if let runLoopSource, let runLoop {
            CFRunLoopAddSource(runLoop, runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            AppLogger.info("Hotkey event tap installed.")
            CFRunLoopRun()
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                AppLogger.info("Hotkey event tap re-enabled after disable event.")
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
            if handleFnSpace(type: type, fnPressed: fnPressed || isFunctionModifierDown(), keycode: keycode) {
                return nil
            }
        }

        return Unmanaged.passRetained(event)
    }

    private func handleGlobalFlagsChanged(_ event: NSEvent) {
        let fnPressed = event.modifierFlags.contains(.function)
        setFunctionModifierDown(fnPressed)
        guard mode == .fnHold else { return }
        fire(transitionFn(pressed: fnPressed, source: "global-monitor"))
    }

    private func handleFnHold(type: CGEventType, fnPressed: Bool, keycode: Int) {
        if type == .flagsChanged {
            setFunctionModifierDown(fnPressed)
            fire(transitionFn(pressed: fnPressed, source: "event-tap-flag"))
            return
        }

        if fnPressed {
            setFunctionModifierDown(true)
            fire(transitionFn(pressed: true, source: "event-tap-flag"))
            return
        }

        if keycode == Self.functionKeycode {
            if type == .keyDown {
                setFunctionModifierDown(true)
                fire(transitionFn(pressed: true, source: "event-tap-keydown"))
            } else if type == .keyUp {
                setFunctionModifierDown(false)
                fire(transitionFn(pressed: false, source: "event-tap-keyup"))
            }
            return
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

    private enum FnTransition {
        case pressed(String)
        case released(String)
    }

    private func setFunctionModifierDown(_ down: Bool) {
        stateLock.lock()
        functionModifierDown = down
        stateLock.unlock()
    }

    private func isFunctionModifierDown() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return functionModifierDown
    }

    private func transitionFn(pressed: Bool, source: String) -> FnTransition? {
        stateLock.lock()
        defer { stateLock.unlock() }

        if pressed && !fnDown {
            fnDown = true
            return .pressed(source)
        }
        if !pressed && fnDown {
            fnDown = false
            return .released(source)
        }
        return nil
    }

    private func fire(_ transition: FnTransition?) {
        guard let transition else { return }
        switch transition {
        case let .pressed(source):
            AppLogger.info("Fn hotkey pressed. source=\(source)")
            onPress?()
        case let .released(source):
            AppLogger.info("Fn hotkey released. source=\(source)")
            onRelease?()
        }
    }
}
