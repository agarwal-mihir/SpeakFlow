import types

import pytest

import whisper_flow.insert as insert_module
from whisper_flow.insert import TextInserter


def test_insert_text_restores_clipboard(monkeypatch) -> None:
    inserter = TextInserter()
    calls = []

    def fake_get() -> str:
        return "old"

    def fake_set(value: str) -> None:
        calls.append(value)

    def fake_paste(**_kwargs) -> None:
        calls.append("__paste__")

    monkeypatch.setattr(inserter, "_get_clipboard_text", fake_get)
    monkeypatch.setattr(inserter, "_set_clipboard_text", fake_set)
    monkeypatch.setattr(inserter, "_paste_with_retry", fake_paste)

    inserter.insert_text("new text")

    assert calls == ["new text", "__paste__", "old"]


def test_insert_text_noop_for_empty_text(monkeypatch) -> None:
    inserter = TextInserter()

    def fail(*_args, **_kwargs):
        raise AssertionError("No clipboard interaction expected")

    monkeypatch.setattr(inserter, "_get_clipboard_text", fail)
    monkeypatch.setattr(inserter, "_set_clipboard_text", fail)
    monkeypatch.setattr(inserter, "_paste_with_retry", fail)

    inserter.insert_text("")


def test_insert_text_without_restore_does_not_restore_clipboard(monkeypatch) -> None:
    inserter = TextInserter()
    calls = []

    monkeypatch.setattr(inserter, "_get_clipboard_text", lambda: "old")
    monkeypatch.setattr(inserter, "_set_clipboard_text", lambda value: calls.append(value))
    monkeypatch.setattr(inserter, "_paste_with_retry", lambda **_kwargs: calls.append("__paste__"))

    inserter.insert_text("new", restore_clipboard=False)

    assert calls == ["new", "__paste__"]


def test_insert_text_failure_restores_clipboard_by_default(monkeypatch) -> None:
    inserter = TextInserter(keep_dictation_on_failure=False)
    calls = []

    monkeypatch.setattr(inserter, "_get_clipboard_text", lambda: "old")
    monkeypatch.setattr(inserter, "_set_clipboard_text", lambda value: calls.append(value))

    def fail_paste(**_kwargs) -> None:
        raise RuntimeError("paste failed")

    monkeypatch.setattr(inserter, "_paste_with_retry", fail_paste)

    with pytest.raises(RuntimeError):
        inserter.insert_text("new")

    assert calls == ["new", "old"]


def test_insert_text_failure_keeps_dictation_in_clipboard_when_enabled(monkeypatch) -> None:
    inserter = TextInserter(keep_dictation_on_failure=True)
    calls = []

    monkeypatch.setattr(inserter, "_get_clipboard_text", lambda: "old")
    monkeypatch.setattr(inserter, "_set_clipboard_text", lambda value: calls.append(value))

    def fail_paste(**_kwargs) -> None:
        raise RuntimeError("paste failed")

    monkeypatch.setattr(inserter, "_paste_with_retry", fail_paste)

    with pytest.raises(RuntimeError) as exc:
        inserter.insert_text("new")

    assert "Clipboard now contains the last dictation" in str(exc.value)
    assert calls == ["new"]


def test_get_clipboard_text_returns_empty_on_failure(monkeypatch) -> None:
    inserter = TextInserter()

    def fake_run(*_args, **_kwargs):
        return types.SimpleNamespace(returncode=1, stdout="")

    monkeypatch.setattr(insert_module.subprocess, "run", fake_run)

    assert inserter._get_clipboard_text() == ""


def test_paste_with_retry_succeeds_on_second_attempt(monkeypatch) -> None:
    inserter = TextInserter(paste_retry=2)
    attempts = []

    def fake_run(*_args, **_kwargs):
        rc = 1 if len(attempts) == 0 else 0
        attempts.append(rc)
        return types.SimpleNamespace(returncode=rc, stderr="")

    monkeypatch.setattr(insert_module.subprocess, "run", fake_run)
    monkeypatch.setattr(inserter, "_paste_with_quartz", lambda: False)

    inserter._paste_with_retry()

    assert attempts == [1, 0]


def test_paste_with_retry_raises_after_retries(monkeypatch) -> None:
    inserter = TextInserter(paste_retry=1)

    def fake_run(*_args, **_kwargs):
        return types.SimpleNamespace(returncode=1, stderr="denied")

    monkeypatch.setattr(insert_module.subprocess, "run", fake_run)
    monkeypatch.setattr(inserter, "_paste_with_quartz", lambda: False)

    with pytest.raises(RuntimeError):
        inserter._paste_with_retry()


def test_paste_with_retry_uses_quartz_fallback(monkeypatch) -> None:
    inserter = TextInserter(paste_retry=0)

    def fake_run(*_args, **_kwargs):
        return types.SimpleNamespace(returncode=1, stderr="denied")

    monkeypatch.setattr(insert_module.subprocess, "run", fake_run)
    monkeypatch.setattr(inserter, "_paste_with_quartz", lambda: True)

    inserter._paste_with_retry()


def test_preflight_automation_permission_returns_true_on_success(monkeypatch) -> None:
    inserter = TextInserter()

    def fake_run(*_args, **_kwargs):
        return types.SimpleNamespace(returncode=0, stderr="")

    monkeypatch.setattr(insert_module.subprocess, "run", fake_run)
    assert inserter.preflight_automation_permission(prompt=False) is True


def test_preflight_automation_permission_returns_false_on_failure(monkeypatch) -> None:
    inserter = TextInserter()

    def fake_run(*_args, **_kwargs):
        return types.SimpleNamespace(returncode=1, stderr="not allowed")

    monkeypatch.setattr(insert_module.subprocess, "run", fake_run)
    assert inserter.preflight_automation_permission(prompt=True) is False


def test_paste_with_system_events_target_pid_does_not_force_focus(monkeypatch) -> None:
    inserter = TextInserter()
    captured = {}

    def fake_run(cmd, **_kwargs):
        captured["cmd"] = cmd
        return types.SimpleNamespace(returncode=0, stderr="")

    monkeypatch.setattr(insert_module.subprocess, "run", fake_run)

    assert inserter._paste_with_system_events(target_pid=1234) is True
    script = captured["cmd"][2]
    assert "set frontmost of targetProc to true" not in script
    assert "if frontmost of targetProc then" in script


def test_paste_with_system_events_target_pid_falls_back_if_not_frontmost(monkeypatch) -> None:
    inserter = TextInserter()
    captured = {}

    def fake_run(cmd, **_kwargs):
        captured["cmd"] = cmd
        return types.SimpleNamespace(returncode=0, stderr="")

    monkeypatch.setattr(insert_module.subprocess, "run", fake_run)

    inserter._paste_with_system_events(target_pid=4321)
    script = captured["cmd"][2]
    assert "keystroke \"v\" using command down" in script
