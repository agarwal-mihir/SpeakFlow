import threading

import whisper_flow.hotkey as hotkey
from whisper_flow.hotkey import FN_MASK, HotkeyCallbacks, HotkeyListener, SPACE_KEYCODE


class _FakeQuartz:
    kCGEventFlagsChanged = 1
    kCGEventKeyDown = 2
    kCGEventKeyUp = 3
    kCGEventTapDisabledByTimeout = 4
    kCGEventTapDisabledByUserInput = 5

    kCGKeyboardEventKeycode = 55
    kCGEventFlagMaskCommand = 1 << 20
    kCGEventFlagMaskAlternate = 1 << 19

    kCGSessionEventTap = 10
    kCGHeadInsertEventTap = 11
    kCGEventTapOptionDefault = 12
    kCGEventTapOptionListenOnly = 13

    kCFRunLoopCommonModes = "common"

    def __init__(self) -> None:
        self.enabled_calls = []
        self.invalidated = []
        self.tap = object()
        self.run_loop = object()
        self.run_called = False

    @staticmethod
    def CGEventMaskBit(value):
        return 1 << value

    def CGEventTapCreate(self, *args):
        return self.tap

    @staticmethod
    def CFMachPortCreateRunLoopSource(_a, _b, _c):
        return object()

    def CFRunLoopGetCurrent(self):
        return self.run_loop

    @staticmethod
    def CFRunLoopAddSource(_loop, _source, _mode):
        return None

    def CGEventTapEnable(self, tap, enabled):
        self.enabled_calls.append((tap, enabled))

    def CFRunLoopRun(self):
        self.run_called = True

    @staticmethod
    def CGEventGetFlags(event):
        return event.get("flags", 0)

    @staticmethod
    def CGEventGetIntegerValueField(event, _field):
        return event.get("keycode", 0)

    @staticmethod
    def CFRunLoopStop(_run_loop):
        return None

    def CFMachPortInvalidate(self, tap):
        self.invalidated.append(tap)


def _callbacks(counter: dict[str, int]) -> HotkeyCallbacks:
    return HotkeyCallbacks(
        on_press=lambda: counter.__setitem__("press", counter["press"] + 1),
        on_release=lambda: counter.__setitem__("release", counter["release"] + 1),
        on_paste_last=lambda: (
            counter.__setitem__("paste_last", counter.get("paste_last", 0) + 1) or True
        ),
    )


def test_fn_hold_transitions() -> None:
    counter = {"press": 0, "release": 0}
    listener = HotkeyListener("fn_hold", _callbacks(counter))

    listener._handle_fn_hold(True)
    listener._handle_fn_hold(True)
    listener._handle_fn_hold(False)

    assert counter == {"press": 1, "release": 1}


def test_fn_space_combo_transitions() -> None:
    counter = {"press": 0, "release": 0}
    listener = HotkeyListener("fn_space_hold", _callbacks(counter))

    listener._handle_fn_space(hotkey.Quartz.kCGEventKeyDown, True, SPACE_KEYCODE)
    listener._handle_fn_space(hotkey.Quartz.kCGEventKeyDown, True, SPACE_KEYCODE)
    listener._handle_fn_space(hotkey.Quartz.kCGEventKeyUp, False, SPACE_KEYCODE)

    assert counter == {"press": 1, "release": 1}


def test_event_callback_reenables_tap_when_disabled(monkeypatch) -> None:
    fake_quartz = _FakeQuartz()
    monkeypatch.setattr(hotkey, "Quartz", fake_quartz)

    listener = HotkeyListener("fn_hold", _callbacks({"press": 0, "release": 0}))
    listener._event_tap = "tap"
    event = {"flags": 0}

    returned = listener._event_callback(None, fake_quartz.kCGEventTapDisabledByTimeout, event, None)

    assert returned is event
    assert fake_quartz.enabled_calls == [("tap", True)]


def test_event_callback_ignores_when_not_running(monkeypatch) -> None:
    fake_quartz = _FakeQuartz()
    monkeypatch.setattr(hotkey, "Quartz", fake_quartz)

    counter = {"press": 0, "release": 0}
    listener = HotkeyListener("fn_hold", _callbacks(counter))

    listener._event_callback(None, fake_quartz.kCGEventFlagsChanged, {"flags": FN_MASK}, None)

    assert counter == {"press": 0, "release": 0}


def test_event_callback_fn_hold_uses_flags(monkeypatch) -> None:
    fake_quartz = _FakeQuartz()
    monkeypatch.setattr(hotkey, "Quartz", fake_quartz)

    counter = {"press": 0, "release": 0}
    listener = HotkeyListener("fn_hold", _callbacks(counter))
    listener._running.set()

    listener._event_callback(None, fake_quartz.kCGEventFlagsChanged, {"flags": FN_MASK}, None)
    listener._event_callback(None, fake_quartz.kCGEventFlagsChanged, {"flags": 0}, None)

    assert counter == {"press": 1, "release": 1}


def test_event_callback_fn_space_uses_key_events(monkeypatch) -> None:
    fake_quartz = _FakeQuartz()
    monkeypatch.setattr(hotkey, "Quartz", fake_quartz)

    counter = {"press": 0, "release": 0}
    listener = HotkeyListener("fn_space_hold", _callbacks(counter))
    listener._running.set()

    listener._event_callback(
        None,
        fake_quartz.kCGEventKeyDown,
        {"flags": FN_MASK, "keycode": SPACE_KEYCODE},
        None,
    )
    listener._event_callback(
        None,
        fake_quartz.kCGEventKeyUp,
        {"flags": 0, "keycode": SPACE_KEYCODE},
        None,
    )

    assert counter == {"press": 1, "release": 1}


def test_event_callback_option_cmd_v_triggers_paste_last_and_consumes_event(monkeypatch) -> None:
    fake_quartz = _FakeQuartz()
    monkeypatch.setattr(hotkey, "Quartz", fake_quartz)

    counter = {"press": 0, "release": 0, "paste_last": 0}
    listener = HotkeyListener("fn_hold", _callbacks(counter))
    listener._running.set()

    event = {
        "flags": fake_quartz.kCGEventFlagMaskCommand | fake_quartz.kCGEventFlagMaskAlternate,
        "keycode": hotkey.V_KEYCODE,
    }
    returned = listener._event_callback(None, fake_quartz.kCGEventKeyDown, event, None)

    assert returned is None
    assert counter["paste_last"] == 1


def test_event_callback_option_cmd_v_without_callback_is_not_consumed(monkeypatch) -> None:
    fake_quartz = _FakeQuartz()
    monkeypatch.setattr(hotkey, "Quartz", fake_quartz)

    listener = HotkeyListener(
        "fn_hold",
        HotkeyCallbacks(on_press=lambda: None, on_release=lambda: None, on_paste_last=None),
    )
    listener._running.set()
    event = {
        "flags": fake_quartz.kCGEventFlagMaskCommand | fake_quartz.kCGEventFlagMaskAlternate,
        "keycode": hotkey.V_KEYCODE,
    }

    returned = listener._event_callback(None, fake_quartz.kCGEventKeyDown, event, None)
    assert returned is event


def test_event_callback_plain_cmd_v_is_not_consumed(monkeypatch) -> None:
    fake_quartz = _FakeQuartz()
    monkeypatch.setattr(hotkey, "Quartz", fake_quartz)

    counter = {"press": 0, "release": 0, "paste_last": 0}
    listener = HotkeyListener("fn_hold", _callbacks(counter))
    listener._running.set()
    event = {
        "flags": fake_quartz.kCGEventFlagMaskCommand,
        "keycode": hotkey.V_KEYCODE,
    }

    returned = listener._event_callback(None, fake_quartz.kCGEventKeyDown, event, None)

    assert returned is event
    assert counter["paste_last"] == 0


def test_run_sets_error_when_event_tap_creation_fails(monkeypatch) -> None:
    fake_quartz = _FakeQuartz()
    fake_quartz.tap = None
    monkeypatch.setattr(hotkey, "Quartz", fake_quartz)

    listener = HotkeyListener("fn_hold", _callbacks({"press": 0, "release": 0}))
    listener._running.set()

    listener._run()

    assert listener.is_active() is False
    assert "Input Monitoring" in listener.last_error()


def test_run_initializes_loop_when_event_tap_available(monkeypatch) -> None:
    fake_quartz = _FakeQuartz()
    monkeypatch.setattr(hotkey, "Quartz", fake_quartz)

    listener = HotkeyListener("fn_hold", _callbacks({"press": 0, "release": 0}))
    listener._running.set()

    listener._run()

    assert fake_quartz.run_called is True
    assert listener.is_active() is False
    assert listener.last_error() == ""
    assert fake_quartz.enabled_calls[0][1] is True


def test_probe_event_tap_returns_false_when_unavailable(monkeypatch) -> None:
    fake_quartz = _FakeQuartz()
    fake_quartz.tap = None
    monkeypatch.setattr(hotkey, "Quartz", fake_quartz)

    assert HotkeyListener.probe_event_tap() is False


def test_probe_event_tap_invalidates_created_tap(monkeypatch) -> None:
    fake_quartz = _FakeQuartz()
    marker = object()
    fake_quartz.tap = marker
    monkeypatch.setattr(hotkey, "Quartz", fake_quartz)

    assert HotkeyListener.probe_event_tap() is True
    assert fake_quartz.invalidated == [marker]


def test_start_noop_if_thread_is_alive(monkeypatch) -> None:
    listener = HotkeyListener("fn_hold", _callbacks({"press": 0, "release": 0}))

    class FakeThread:
        def is_alive(self):
            return True

    listener._thread = FakeThread()

    def fail_thread(*_args, **_kwargs):
        raise AssertionError("Thread should not be created")

    monkeypatch.setattr(hotkey.threading, "Thread", fail_thread)
    listener.start()


def test_stop_stops_run_loop_and_resets_state(monkeypatch) -> None:
    fake_quartz = _FakeQuartz()
    stopped = []

    def fake_stop(run_loop):
        stopped.append(run_loop)

    fake_quartz.CFRunLoopStop = fake_stop
    monkeypatch.setattr(hotkey, "Quartz", fake_quartz)

    listener = HotkeyListener("fn_hold", _callbacks({"press": 0, "release": 0}))
    listener._running.set()
    listener._run_loop = "loop"
    listener._event_tap = "tap"
    listener._source = "source"
    listener._active = True

    class FakeThread:
        def __init__(self) -> None:
            self.joined = False

        def is_alive(self):
            return True

        def join(self, timeout=None):
            self.joined = True

    thread = FakeThread()
    listener._thread = thread

    listener.stop()

    assert stopped == ["loop"]
    assert thread.joined is True
    assert listener._thread is None
    assert listener._event_tap is None
    assert listener._source is None
    assert listener._run_loop is None
    assert listener.is_active() is False


def test_reconfigure_resets_flags_and_restarts(monkeypatch) -> None:
    listener = HotkeyListener("fn_hold", _callbacks({"press": 0, "release": 0}))
    listener._fn_down = True
    listener._combo_down = True

    calls = []
    monkeypatch.setattr(listener, "stop", lambda: calls.append("stop"))
    monkeypatch.setattr(listener, "start", lambda: calls.append("start"))

    listener.reconfigure("fn_space_hold")

    assert listener.mode == "fn_space_hold"
    assert listener._fn_down is False
    assert listener._combo_down is False
    assert calls == ["stop", "start"]
