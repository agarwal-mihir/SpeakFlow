from __future__ import annotations

import logging
import subprocess
from pathlib import Path

from AppKit import NSApplication, NSApplicationActivationPolicyRegular

from whisper_flow.single_instance import acquire_single_instance_lock
from whisper_flow.ui import run_app

LOG_DIR = Path.home() / "Library" / "Logs" / "SpeakFlow"
LOG_FILE = LOG_DIR / "whisper_flow.log"


def configure_logging() -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
        handlers=[
            logging.FileHandler(LOG_FILE, encoding="utf-8"),
            logging.StreamHandler(),
        ],
    )


def run() -> None:
    if not _enforce_single_instance():
        return
    configure_logging()
    NSApplication.sharedApplication().setActivationPolicy_(NSApplicationActivationPolicyRegular)
    run_app()


def _enforce_single_instance() -> bool:
    """Prevent duplicate app processes and activate existing instance."""
    if acquire_single_instance_lock():
        return True

    subprocess.run(
        ["osascript", "-e", 'tell application id "com.speakflow.desktop" to activate'],
        check=False,
        capture_output=True,
        text=True,
    )
    return False


if __name__ == "__main__":
    run()
