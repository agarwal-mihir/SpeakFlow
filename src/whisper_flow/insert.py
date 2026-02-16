from __future__ import annotations

import logging
import subprocess
import time

LOGGER = logging.getLogger(__name__)


class TextInserter:
    def __init__(self, paste_retry: int = 1, keep_dictation_on_failure: bool = False) -> None:
        self.paste_retry = max(0, paste_retry)
        self.keep_dictation_on_failure = keep_dictation_on_failure

    def insert_text(
        self,
        text: str,
        restore_clipboard: bool = True,
        target_pid: int | None = None,
        keep_dictation_on_failure: bool | None = None,
    ) -> None:
        if not text:
            return

        original_clipboard = self._get_clipboard_text()
        keep_on_failure = (
            self.keep_dictation_on_failure if keep_dictation_on_failure is None else bool(keep_dictation_on_failure)
        )

        pasted = False
        try:
            self._set_clipboard_text(text)
            # Give macOS a brief moment to propagate new clipboard contents.
            time.sleep(0.05)
            self._paste_with_retry(target_pid=target_pid)
            pasted = True
        except Exception as exc:
            if restore_clipboard and not keep_on_failure:
                try:
                    self._set_clipboard_text(original_clipboard)
                except Exception:
                    pass
            if keep_on_failure:
                raise RuntimeError(
                    f"{exc} Clipboard now contains the last dictation for manual paste."
                ) from exc
            raise
        finally:
            if pasted and restore_clipboard:
                # Wait for the target app to process the paste event before
                # restoring the original clipboard contents.
                time.sleep(0.20)
                try:
                    self._set_clipboard_text(original_clipboard)
                except Exception:
                    pass  # Don't mask the original error

    def _get_clipboard_text(self) -> str:
        result = subprocess.run(
            ["pbpaste"],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            return ""
        return result.stdout

    def _set_clipboard_text(self, text: str) -> None:
        subprocess.run(["pbcopy"], input=text, text=True, check=True, timeout=10)

    def _paste_with_retry(self, target_pid: int | None = None) -> None:
        attempts = self.paste_retry + 1
        last_errors: list[str] = []
        for attempt in range(attempts):
            if self._paste_with_system_events(target_pid=target_pid):
                time.sleep(0.06)
                return
            last_errors.append("System Events keystroke failed")

            if self._paste_with_quartz():
                time.sleep(0.06)
                return
            last_errors.append("Quartz keyboard event failed")

            if attempt < attempts - 1:
                time.sleep(0.08)

        detail = "; ".join(last_errors[-2:]) if last_errors else "Unknown paste failure"
        raise RuntimeError(
            f"Failed to paste text into focused app. Check Accessibility/Input Monitoring permissions. ({detail})"
        )

    def _paste_with_system_events(self, target_pid: int | None = None) -> bool:
        script = 'tell application "System Events" to keystroke "v" using command down'
        if target_pid is not None:
            script = f'''
tell application "System Events"
  try
    set targetProc to first process whose unix id is {int(target_pid)}
    if frontmost of targetProc then
      tell targetProc to keystroke "v" using command down
    else
      keystroke "v" using command down
    end if
  on error
    keystroke "v" using command down
  end try
end tell
'''.strip()

        result = subprocess.run(
            ["osascript", "-e", script],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0:
            return True

        LOGGER.debug("System Events paste failed: %s", result.stderr.strip())
        return False

    def _paste_with_quartz(self) -> bool:
        try:
            import Quartz

            keycode_v = 9
            down = Quartz.CGEventCreateKeyboardEvent(None, keycode_v, True)
            up = Quartz.CGEventCreateKeyboardEvent(None, keycode_v, False)
            if down is None or up is None:
                return False

            Quartz.CGEventSetFlags(down, Quartz.kCGEventFlagMaskCommand)
            Quartz.CGEventSetFlags(up, Quartz.kCGEventFlagMaskCommand)
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, down)
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, up)
            return True
        except Exception:
            LOGGER.debug("Quartz paste fallback failed", exc_info=True)
            return False

    def preflight_automation_permission(self, prompt: bool = False) -> bool:
        # Any AppleEvents call to System Events is enough to validate/request Automation permission.
        script = 'tell application "System Events" to get name of first process'
        result = subprocess.run(
            ["osascript", "-e", script],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0:
            return True
        return False
