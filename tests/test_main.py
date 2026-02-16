import logging
from pathlib import Path

import whisper_flow.main as main


def test_configure_logging_creates_log_dir_and_configures_handlers(monkeypatch, tmp_path: Path) -> None:
    log_dir = tmp_path / "logs"
    log_file = log_dir / "whisper_flow.log"

    monkeypatch.setattr(main, "LOG_DIR", log_dir)
    monkeypatch.setattr(main, "LOG_FILE", log_file)

    captured = {}

    def fake_basic_config(**kwargs):
        captured.update(kwargs)

    monkeypatch.setattr(main.logging, "basicConfig", fake_basic_config)

    main.configure_logging()

    assert log_dir.exists()
    assert captured["level"] == logging.INFO
    assert "%(asctime)s %(levelname)s" in captured["format"]
    assert len(captured["handlers"]) == 2


def test_run_configures_logging_then_starts_app(monkeypatch) -> None:
    calls = []

    monkeypatch.setattr(main, "configure_logging", lambda: calls.append("logging"))
    monkeypatch.setattr(main, "_enforce_single_instance", lambda: True)

    class FakeSharedApp:
        def __init__(self) -> None:
            self.policy = None

        def setActivationPolicy_(self, policy) -> None:
            self.policy = policy
            calls.append(("policy", policy))

    fake_app = FakeSharedApp()

    class FakeNSApplication:
        @staticmethod
        def sharedApplication():
            return fake_app

    monkeypatch.setattr(main, "NSApplication", FakeNSApplication)
    monkeypatch.setattr(main, "run_app", lambda: calls.append("run_app"))

    main.run()

    assert calls[0] == "logging"
    assert calls[1] == ("policy", main.NSApplicationActivationPolicyRegular)
    assert calls[2] == "run_app"


def test_run_exits_early_if_duplicate_instance(monkeypatch) -> None:
    calls = []

    monkeypatch.setattr(main, "_enforce_single_instance", lambda: False)
    monkeypatch.setattr(main, "configure_logging", lambda: calls.append("logging"))
    monkeypatch.setattr(main, "run_app", lambda: calls.append("run_app"))

    main.run()

    assert calls == []


def test_enforce_single_instance_activates_existing_app(monkeypatch) -> None:
    monkeypatch.setattr(main, "acquire_single_instance_lock", lambda: False)
    called = []

    def fake_run(cmd, check=False, capture_output=False, text=False):  # noqa: ARG001
        called.append(cmd)
        class Result:
            returncode = 0
        return Result()

    monkeypatch.setattr(main.subprocess, "run", fake_run)

    assert main._enforce_single_instance() is False
    assert called
    assert called[0][0] == "osascript"
