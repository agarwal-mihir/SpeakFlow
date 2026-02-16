from __future__ import annotations

import logging
import subprocess
import threading

LOGGER = logging.getLogger(__name__)


class SystemAudioDucker:
    """Temporarily lowers system output volume while recording to reduce speaker bleed."""

    def __init__(self, enabled: bool, target_volume_percent: int, timeout_seconds: float = 0.8) -> None:
        self.enabled = enabled
        self.target_volume_percent = max(0, min(100, int(target_volume_percent)))
        self.timeout_seconds = max(timeout_seconds, 0.2)
        self._lock = threading.Lock()
        self._previous_volume: int | None = None

    def duck(self) -> None:
        if not self.enabled:
            return

        with self._lock:
            if self._previous_volume is not None:
                return

            current = self._get_output_volume()
            if current is None:
                return

            self._previous_volume = current
            if current <= self.target_volume_percent:
                return

        self._set_output_volume(self.target_volume_percent)

    def restore(self) -> None:
        if not self.enabled:
            return

        with self._lock:
            if self._previous_volume is None:
                return
            target_restore = self._previous_volume
            self._previous_volume = None

        self._set_output_volume(target_restore)

    def _get_output_volume(self) -> int | None:
        result = self._run_osascript("output volume of (get volume settings)")
        if result is None:
            return None

        try:
            return int(result.strip())
        except ValueError:
            LOGGER.warning("Unable to parse system output volume: %r", result)
            return None

    def _set_output_volume(self, volume_percent: int) -> None:
        clamped = max(0, min(100, int(volume_percent)))
        self._run_osascript(f"set volume output volume {clamped}", warn_on_error=True)

    def _run_osascript(self, script: str, warn_on_error: bool = False) -> str | None:
        try:
            completed = subprocess.run(
                ["osascript", "-e", script],
                check=False,
                capture_output=True,
                text=True,
                timeout=self.timeout_seconds,
            )
        except FileNotFoundError:
            LOGGER.debug("osascript command not found; system audio ducking unavailable")
            return None
        except subprocess.SubprocessError:
            LOGGER.debug("osascript command failed unexpectedly", exc_info=True)
            return None

        if completed.returncode != 0:
            if warn_on_error:
                LOGGER.warning("System audio command failed: %s", completed.stderr.strip())
            else:
                LOGGER.debug("System audio query failed: %s", completed.stderr.strip())
            return None

        return completed.stdout
