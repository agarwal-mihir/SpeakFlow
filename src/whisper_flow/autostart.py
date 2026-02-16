from __future__ import annotations

import os
import plistlib
import subprocess
import sys
from pathlib import Path

LABEL = "com.speakflow.desktop"
AGENT_PATH = Path.home() / "Library" / "LaunchAgents" / f"{LABEL}.plist"
LOG_DIR = Path.home() / "Library" / "Logs" / "SpeakFlow"


def _is_app_bundle_executable(path: Path) -> bool:
    return ".app/Contents/MacOS/" in str(path)


def _build_launch_agent_dict() -> tuple[dict, str]:
    executable = Path(sys.executable)

    if _is_app_bundle_executable(executable):
        mode = "app"
        app_bundle = executable.parents[2]
        # Launch the app executable directly; avoids launchd/open keepalive loops.
        program_arguments = [str(executable)]
        environment = None
        working_dir = str(app_bundle)
    else:
        mode = "python"
        package_root = Path(__file__).resolve().parents[2]
        program_arguments = [str(executable), "-m", "whisper_flow.main"]
        environment = {
            "PYTHONPATH": str(package_root / "src"),
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        }
        working_dir = str(package_root)

    payload = {
        "Label": LABEL,
        "ProgramArguments": program_arguments,
        "RunAtLoad": True,
        "KeepAlive": True,
        "WorkingDirectory": working_dir,
        "StandardOutPath": str(LOG_DIR / "launchd.stdout.log"),
        "StandardErrorPath": str(LOG_DIR / "launchd.stderr.log"),
    }
    if environment:
        payload["EnvironmentVariables"] = environment

    return payload, mode


def install_launch_agent() -> str:
    agent_payload, mode = _build_launch_agent_dict()

    AGENT_PATH.parent.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)

    with AGENT_PATH.open("wb") as handle:
        plistlib.dump(agent_payload, handle)

    uid = os.getuid()
    subprocess.run(["launchctl", "bootout", f"gui/{uid}/{LABEL}"], check=False, capture_output=True)
    subprocess.run(["launchctl", "bootstrap", f"gui/{uid}", str(AGENT_PATH)], check=True)
    subprocess.run(["launchctl", "enable", f"gui/{uid}/{LABEL}"], check=True)
    subprocess.run(["launchctl", "kickstart", "-k", f"gui/{uid}/{LABEL}"], check=True)

    return mode


def uninstall_launch_agent() -> None:
    uid = os.getuid()
    subprocess.run(["launchctl", "bootout", f"gui/{uid}/{LABEL}"], check=False, capture_output=True)
    subprocess.run(["launchctl", "disable", f"gui/{uid}/{LABEL}"], check=False, capture_output=True)

    if AGENT_PATH.exists():
        AGENT_PATH.unlink()


__all__ = ["AGENT_PATH", "install_launch_agent", "uninstall_launch_agent"]
