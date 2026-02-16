import subprocess
import types

import whisper_flow.audio as audio
import whisper_flow.hotkey as hotkey
from whisper_flow.permissions import PermissionManager, PermissionState


def test_permission_state_all_granted() -> None:
    assert PermissionState(True, True, True, True).all_granted is True
    assert PermissionState(True, True, False, True).all_granted is False


def test_check_all_collects_current_states(monkeypatch) -> None:
    manager = PermissionManager()

    monkeypatch.setattr(manager, "check_microphone", lambda: True)
    monkeypatch.setattr(manager, "check_accessibility", lambda: True)
    monkeypatch.setattr(manager, "check_input_monitoring", lambda: False)
    monkeypatch.setattr(manager, "check_automation", lambda: True)

    state = manager.check_all()

    assert state.microphone is True
    assert state.accessibility is True
    assert state.input_monitoring is False
    assert state.automation is True
    assert state.all_granted is False


def test_check_microphone_returns_true_when_authorized(monkeypatch) -> None:
    manager = PermissionManager()
    fake_av = types.SimpleNamespace(
        AVMediaTypeAudio="audio",
        AVCaptureDevice=types.SimpleNamespace(authorizationStatusForMediaType_=staticmethod(lambda _media: 3)),
    )
    monkeypatch.setitem(__import__("sys").modules, "AVFoundation", fake_av)

    assert manager.check_microphone() is True


def test_check_microphone_returns_false_on_error(monkeypatch) -> None:
    manager = PermissionManager()
    monkeypatch.setitem(__import__("sys").modules, "AVFoundation", None)

    assert manager.check_microphone() is False


def test_request_microphone_uses_avfoundation(monkeypatch) -> None:
    manager = PermissionManager()
    calls = []

    def request_access(media, handler):  # type: ignore[no-untyped-def]
        calls.append(media)
        handler(True)

    fake_av = types.SimpleNamespace(
        AVMediaTypeAudio="audio",
        AVCaptureDevice=types.SimpleNamespace(
            requestAccessForMediaType_completionHandler_=staticmethod(request_access)
        ),
    )
    monkeypatch.setitem(__import__("sys").modules, "AVFoundation", fake_av)

    assert manager.request_microphone() is True
    assert calls == ["audio"]


def test_request_accessibility_prompt_uses_quartz(monkeypatch) -> None:
    manager = PermissionManager()
    fake_quartz = type(
        "FakeQuartz",
        (),
        {
            "kAXTrustedCheckOptionPrompt": "prompt",
            "AXIsProcessTrustedWithOptions": staticmethod(lambda _options: True),
        },
    )
    monkeypatch.setitem(__import__("sys").modules, "Quartz", fake_quartz)
    assert manager.request_accessibility_prompt() is True


def test_check_input_monitoring_delegates_to_hotkey_probe(monkeypatch) -> None:
    manager = PermissionManager()

    monkeypatch.setattr(hotkey.HotkeyListener, "probe_event_tap", staticmethod(lambda: True))
    monkeypatch.setitem(__import__("sys").modules, "Quartz", object())

    assert manager.check_input_monitoring() is True


def test_check_input_monitoring_uses_preflight_api_when_available(monkeypatch) -> None:
    manager = PermissionManager()
    fake_quartz = types.SimpleNamespace(CGPreflightListenEventAccess=lambda: True)
    monkeypatch.setitem(__import__("sys").modules, "Quartz", fake_quartz)

    assert manager.check_input_monitoring() is True


def test_request_input_monitoring_prompt_uses_system_api(monkeypatch) -> None:
    manager = PermissionManager()
    fake_quartz = types.SimpleNamespace(CGRequestListenEventAccess=lambda: True)
    monkeypatch.setitem(__import__("sys").modules, "Quartz", fake_quartz)

    assert manager.request_input_monitoring_prompt() is True


def test_check_automation_handles_inserter_errors() -> None:
    class FailingInserter:
        def preflight_automation_permission(self, prompt=False):  # noqa: ARG002
            raise RuntimeError("denied")

    manager = PermissionManager(inserter=FailingInserter())

    assert manager.check_automation() is False
    assert manager.request_automation_prompt() is False


def test_open_settings_shortcuts_ventura(monkeypatch) -> None:
    manager = PermissionManager()
    calls = []

    def fake_run(cmd, check=False):  # noqa: ARG001
        calls.append(cmd)
        return subprocess.CompletedProcess(cmd, 0)

    monkeypatch.setattr("whisper_flow.permissions.subprocess.run", fake_run)

    manager.open_microphone_settings()
    manager.open_accessibility_settings()
    manager.open_input_monitoring_settings()
    manager.open_automation_settings()

    assert calls == [
        ["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"],
        ["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"],
        ["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"],
        ["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"],
    ]


def test_open_settings_shortcuts_legacy(monkeypatch) -> None:
    manager = PermissionManager()
    calls = []

    def fake_run(cmd, check=False):  # noqa: ARG001
        calls.append(cmd)
        return subprocess.CompletedProcess(cmd, 0)

    monkeypatch.setattr("whisper_flow.permissions.subprocess.run", fake_run)

    manager.open_microphone_settings()
    manager.open_accessibility_settings()
    manager.open_input_monitoring_settings()
    manager.open_automation_settings()

    assert calls == [
        ["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"],
        ["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"],
        ["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"],
        ["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"],
    ]


def test_open_input_monitoring_settings_falls_back_when_primary_fails(monkeypatch) -> None:
    manager = PermissionManager()
    calls = []

    def fake_run(cmd, check=False):  # noqa: ARG001
        calls.append(cmd)
        rc = 1 if "Privacy_ListenEvent" in cmd[1] else 0
        return subprocess.CompletedProcess(cmd, rc)

    monkeypatch.setattr("whisper_flow.permissions.subprocess.run", fake_run)
    manager.open_input_monitoring_settings()

    assert calls == [
        ["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"],
        ["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_InputMonitoring"],
    ]
