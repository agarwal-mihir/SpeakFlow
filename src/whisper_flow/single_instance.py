from __future__ import annotations

import fcntl
import os
from pathlib import Path

from whisper_flow.config import APP_DIR

LOCK_PATH = APP_DIR / "whisper_flow.lock"
_LOCK_HANDLE = None


def acquire_single_instance_lock(path: Path = LOCK_PATH) -> bool:
    global _LOCK_HANDLE

    path.parent.mkdir(parents=True, exist_ok=True)
    handle = path.open("a+", encoding="utf-8")
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        handle.close()
        return False

    handle.seek(0)
    handle.truncate(0)
    handle.write(str(os.getpid()))
    handle.flush()

    _LOCK_HANDLE = handle
    return True


def release_single_instance_lock() -> None:
    global _LOCK_HANDLE

    if _LOCK_HANDLE is None:
        return

    try:
        fcntl.flock(_LOCK_HANDLE.fileno(), fcntl.LOCK_UN)
    except OSError:
        pass

    try:
        _LOCK_HANDLE.close()
    finally:
        _LOCK_HANDLE = None


__all__ = ["LOCK_PATH", "acquire_single_instance_lock", "release_single_instance_lock"]
