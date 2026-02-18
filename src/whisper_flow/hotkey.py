from __future__ import annotations

import logging
import threading
from dataclasses import dataclass
from typing import Callable

import Quartz

LOGGER = logging.getLogger(__name__)

FN_MASK = getattr(Quartz, "kCGEventFlagMaskSecondaryFn", 1 << 23)
CMD_MASK = getattr(Quartz, "kCGEventFlagMaskCommand", 1 << 20)
OPTION_MASK = getattr(Quartz, "kCGEventFlagMaskAlternate", 1 << 19)
SHIFT_MASK = getattr(Quartz, "kCGEventFlagMaskShift", 1 << 17)
CONTROL_MASK = getattr(Quartz, "kCGEventFlagMaskControl", 1 << 18)
SPACE_KEYCODE = 49
V_KEYCODE = 9


@dataclass
class HotkeyCallbacks:
    on_press: Callable[[], None]
    on_release: Callable[[], None]
    on_paste_last: Callable[[], bool] | None = None


class HotkeyListener:
    def __init__(self, mode: str, callbacks: HotkeyCallbacks) -> None:
        self.mode = mode
        self.callbacks = callbacks

        self._thread: threading.Thread | None = None
        self._running = threading.Event()

        self._event_tap = None
        self._source = None
        self._run_loop = None

        self._fn_down = False
        self._combo_down = False
        self._active = False
        self._last_error = ""

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return

        self._running.set()
        self._thread = threading.Thread(target=self._run, name="hotkey-listener", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._running.clear()

        if self._run_loop is not None:
            Quartz.CFRunLoopStop(self._run_loop)

        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=1.0)

        self._thread = None
        self._event_tap = None
        self._source = None
        self._run_loop = None
        self._active = False

    def reconfigure(self, mode: str) -> None:
        self.stop()
        self.mode = mode
        self._fn_down = False
        self._combo_down = False
        self.start()

    def _run(self) -> None:
        mask = (
            Quartz.CGEventMaskBit(Quartz.kCGEventFlagsChanged)
            | Quartz.CGEventMaskBit(Quartz.kCGEventKeyDown)
            | Quartz.CGEventMaskBit(Quartz.kCGEventKeyUp)
        )

        self._event_tap = Quartz.CGEventTapCreate(
            Quartz.kCGSessionEventTap,
            Quartz.kCGHeadInsertEventTap,
            Quartz.kCGEventTapOptionDefault,
            mask,
            self._event_callback,
            None,
        )

        if not self._event_tap:
            self._active = False
            self._last_error = "Global hotkey unavailable. Grant Input Monitoring permission."
            LOGGER.error("Unable to create global keyboard event tap. Check Input Monitoring permissions.")
            return

        self._last_error = ""
        self._source = Quartz.CFMachPortCreateRunLoopSource(None, self._event_tap, 0)
        self._run_loop = Quartz.CFRunLoopGetCurrent()

        Quartz.CFRunLoopAddSource(self._run_loop, self._source, Quartz.kCFRunLoopCommonModes)
        Quartz.CGEventTapEnable(self._event_tap, True)
        self._active = True
        Quartz.CFRunLoopRun()
        self._active = False

    @staticmethod
    def probe_event_tap() -> bool:
        def _callback(proxy, event_type, event, refcon):  # type: ignore[no-untyped-def]
            return event

        mask = Quartz.CGEventMaskBit(Quartz.kCGEventFlagsChanged)
        tap = Quartz.CGEventTapCreate(
            Quartz.kCGSessionEventTap,
            Quartz.kCGHeadInsertEventTap,
            Quartz.kCGEventTapOptionDefault,
            mask,
            _callback,
            None,
        )
        if not tap:
            return False

        Quartz.CFMachPortInvalidate(tap)
        return True

    def _event_callback(self, proxy, event_type, event, refcon):  # type: ignore[no-untyped-def]
        if event_type in {
            Quartz.kCGEventTapDisabledByTimeout,
            Quartz.kCGEventTapDisabledByUserInput,
        }:
            LOGGER.warning(
                "Event tap disabled (type=%s), re-enabling", event_type
            )
            if self._event_tap is not None:
                Quartz.CGEventTapEnable(self._event_tap, True)
            return event

        if not self._running.is_set():
            return event

        flags = Quartz.CGEventGetFlags(event)
        keycode = Quartz.CGEventGetIntegerValueField(event, Quartz.kCGKeyboardEventKeycode)
        modifiers = flags & (FN_MASK | CMD_MASK | OPTION_MASK | SHIFT_MASK | CONTROL_MASK)

        if (
            event_type == Quartz.kCGEventKeyDown
            and keycode == V_KEYCODE
            and modifiers == (CMD_MASK | OPTION_MASK)
        ):
            handled = False
            if self.callbacks.on_paste_last is not None:
                try:
                    handled = bool(self.callbacks.on_paste_last())
                except Exception:
                    LOGGER.exception("Paste-last callback failed")
            # Consume only when we actually handled paste-last.
            return None if handled else event

        fn_pressed = bool(flags & FN_MASK)

        if self.mode == "fn_hold":
            self._handle_fn_hold(fn_pressed)
            return event

        self._handle_fn_space(event_type, fn_pressed, keycode)
        return event

    def _handle_fn_hold(self, fn_pressed: bool) -> None:
        if fn_pressed and not self._fn_down:
            self._fn_down = True
            try:
                self.callbacks.on_press()
            except Exception:
                LOGGER.exception("Hotkey press callback failed")
            return

        if not fn_pressed and self._fn_down:
            self._fn_down = False
            try:
                self.callbacks.on_release()
            except Exception:
                LOGGER.exception("Hotkey release callback failed")

    def _handle_fn_space(self, event_type: int, fn_pressed: bool, keycode: int) -> None:
        if event_type == Quartz.kCGEventKeyDown and keycode == SPACE_KEYCODE and fn_pressed:
            if not self._combo_down:
                self._combo_down = True
                try:
                    self.callbacks.on_press()
                except Exception:
                    LOGGER.exception("Hotkey press callback failed")
            return

        if event_type == Quartz.kCGEventKeyUp and keycode == SPACE_KEYCODE and self._combo_down:
            self._combo_down = False
            try:
                self.callbacks.on_release()
            except Exception:
                LOGGER.exception("Hotkey release callback failed")

    def is_active(self) -> bool:
        return self._active

    def last_error(self) -> str:
        return self._last_error
