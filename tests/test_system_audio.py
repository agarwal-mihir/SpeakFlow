from __future__ import annotations

import whisper_flow.system_audio as system_audio_module
from whisper_flow.system_audio import SystemAudioDucker


class FakeResult:
    def __init__(self, returncode: int = 0, stdout: str = "", stderr: str = "") -> None:
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


def test_duck_and_restore_sets_and_restores_volume(monkeypatch) -> None:
    calls: list[list[str]] = []

    def fake_run(cmd, check, capture_output, text, timeout):  # noqa: ARG001
        calls.append(cmd)
        script = cmd[-1]
        if script.startswith("output volume"):
            return FakeResult(stdout="42\n")
        return FakeResult()

    monkeypatch.setattr(system_audio_module.subprocess, "run", fake_run)

    ducker = SystemAudioDucker(enabled=True, target_volume_percent=8)
    ducker.duck()
    ducker.restore()

    scripts = [cmd[-1] for cmd in calls]
    assert scripts == [
        "output volume of (get volume settings)",
        "set volume output volume 8",
        "set volume output volume 42",
    ]


def test_duck_is_noop_when_disabled(monkeypatch) -> None:
    calls = []
    monkeypatch.setattr(system_audio_module.subprocess, "run", lambda *args, **kwargs: calls.append((args, kwargs)))

    ducker = SystemAudioDucker(enabled=False, target_volume_percent=8)
    ducker.duck()
    ducker.restore()

    assert calls == []


def test_duck_skips_setting_when_current_volume_already_low(monkeypatch) -> None:
    calls: list[list[str]] = []

    def fake_run(cmd, check, capture_output, text, timeout):  # noqa: ARG001
        calls.append(cmd)
        script = cmd[-1]
        if script.startswith("output volume"):
            return FakeResult(stdout="5\n")
        return FakeResult()

    monkeypatch.setattr(system_audio_module.subprocess, "run", fake_run)

    ducker = SystemAudioDucker(enabled=True, target_volume_percent=8)
    ducker.duck()
    ducker.restore()

    scripts = [cmd[-1] for cmd in calls]
    assert scripts == [
        "output volume of (get volume settings)",
        "set volume output volume 5",
    ]
