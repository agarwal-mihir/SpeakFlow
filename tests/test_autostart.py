import plistlib
import subprocess

import whisper_flow.autostart as autostart


def test_is_app_bundle_executable_detects_path_shape() -> None:
    assert autostart._is_app_bundle_executable(
        autostart.Path("/Applications/SpeakFlow.app/Contents/MacOS/SpeakFlow")
    )
    assert not autostart._is_app_bundle_executable(autostart.Path("/usr/bin/python3"))


def test_build_launch_agent_dict_for_app_mode(monkeypatch) -> None:
    monkeypatch.setattr(autostart.sys, "executable", "/Users/test/Applications/SpeakFlow.app/Contents/MacOS/SpeakFlow")

    payload, mode = autostart._build_launch_agent_dict()

    assert mode == "app"
    assert payload["ProgramArguments"] == ["/Users/test/Applications/SpeakFlow.app/Contents/MacOS/SpeakFlow"]
    assert payload["WorkingDirectory"] == "/Users/test/Applications/SpeakFlow.app"
    assert "EnvironmentVariables" not in payload


def test_build_launch_agent_dict_for_python_mode(monkeypatch) -> None:
    monkeypatch.setattr(autostart.sys, "executable", "/usr/bin/python3")

    payload, mode = autostart._build_launch_agent_dict()

    assert mode == "python"
    assert payload["ProgramArguments"][0] == "/usr/bin/python3"
    assert payload["ProgramArguments"][1:] == ["-m", "whisper_flow.main"]
    assert payload["EnvironmentVariables"]["PYTHONPATH"].endswith("/src")


def test_install_launch_agent_writes_plist_and_runs_launchctl(monkeypatch, tmp_path) -> None:
    agent_path = tmp_path / "com.speakflow.desktop.plist"
    log_dir = tmp_path / "logs"

    monkeypatch.setattr(autostart, "AGENT_PATH", agent_path)
    monkeypatch.setattr(autostart, "LOG_DIR", log_dir)
    monkeypatch.setattr(autostart.os, "getuid", lambda: 501)

    payload = {
        "Label": autostart.LABEL,
        "ProgramArguments": ["/Applications/SpeakFlow.app/Contents/MacOS/SpeakFlow"],
        "RunAtLoad": True,
        "KeepAlive": True,
        "WorkingDirectory": "/Applications/SpeakFlow.app",
        "StandardOutPath": str(log_dir / "launchd.stdout.log"),
        "StandardErrorPath": str(log_dir / "launchd.stderr.log"),
    }
    monkeypatch.setattr(autostart, "_build_launch_agent_dict", lambda: (payload, "app"))

    calls = []

    def fake_run(cmd, **kwargs):
        calls.append((cmd, kwargs))
        return subprocess.CompletedProcess(cmd, 0)

    monkeypatch.setattr(autostart.subprocess, "run", fake_run)

    mode = autostart.install_launch_agent()

    assert mode == "app"
    assert agent_path.exists()
    with agent_path.open("rb") as handle:
        on_disk = plistlib.load(handle)
    assert on_disk["Label"] == autostart.LABEL

    assert calls[0][0][:2] == ["launchctl", "bootout"]
    assert calls[1][0][:2] == ["launchctl", "bootstrap"]
    assert calls[2][0][:2] == ["launchctl", "enable"]
    assert calls[3][0][:2] == ["launchctl", "kickstart"]


def test_uninstall_launch_agent_disables_and_removes_file(monkeypatch, tmp_path) -> None:
    agent_path = tmp_path / "com.speakflow.desktop.plist"
    agent_path.write_text("plist", encoding="utf-8")

    monkeypatch.setattr(autostart, "AGENT_PATH", agent_path)
    monkeypatch.setattr(autostart.os, "getuid", lambda: 501)

    calls = []

    def fake_run(cmd, **kwargs):
        calls.append((cmd, kwargs))
        return subprocess.CompletedProcess(cmd, 0)

    monkeypatch.setattr(autostart.subprocess, "run", fake_run)

    autostart.uninstall_launch_agent()

    assert not agent_path.exists()
    assert calls[0][0][:2] == ["launchctl", "bootout"]
    assert calls[1][0][:2] == ["launchctl", "disable"]
