from __future__ import annotations

import logging
import subprocess
from dataclasses import dataclass

from whisper_flow.insert import TextInserter

LOGGER = logging.getLogger(__name__)


@dataclass
class PermissionState:
    microphone: bool
    accessibility: bool
    input_monitoring: bool
    automation: bool

    @property
    def all_granted(self) -> bool:
        return (
            self.microphone
            and self.accessibility
            and self.input_monitoring
            and self.automation
        )


class PermissionManager:
    def __init__(self, inserter: TextInserter | None = None) -> None:
        self._inserter = inserter or TextInserter()

    def check_microphone(self) -> bool:
        try:
            import AVFoundation

            status = AVFoundation.AVCaptureDevice.authorizationStatusForMediaType_(
                AVFoundation.AVMediaTypeAudio
            )
            # AVAuthorizationStatusAuthorized = 3
            return status == 3
        except Exception:
            LOGGER.debug("Microphone permission check failed", exc_info=True)
            return False

    def request_microphone(self) -> bool:
        try:
            import AVFoundation
        except ImportError:
            LOGGER.debug("Microphone permission request failed", exc_info=True)
            return False

        import threading

        granted = {"value": False}
        done = threading.Event()

        def handler(result):  # type: ignore[no-untyped-def]
            granted["value"] = bool(result)
            done.set()

        try:
            AVFoundation.AVCaptureDevice.requestAccessForMediaType_completionHandler_(
                AVFoundation.AVMediaTypeAudio, handler
            )
        except (AttributeError, TypeError, RuntimeError):
            LOGGER.debug("Microphone permission request failed", exc_info=True)
            return False

        done.wait(timeout=60)
        return granted["value"] if done.is_set() else False

    def check_accessibility(self) -> bool:
        try:
            import Quartz

            if hasattr(Quartz, "AXIsProcessTrusted"):
                return bool(Quartz.AXIsProcessTrusted())
        except Exception:
            LOGGER.debug("Quartz accessibility check failed", exc_info=True)
        # Fallback: use ctypes to call ApplicationServices directly
        try:
            import ctypes

            lib = ctypes.cdll.LoadLibrary(
                "/System/Library/Frameworks/ApplicationServices.framework"
                "/ApplicationServices"
            )
            lib.AXIsProcessTrusted.restype = ctypes.c_bool
            return lib.AXIsProcessTrusted()
        except Exception:
            LOGGER.debug("ctypes accessibility check failed", exc_info=True)
            return False

    def request_accessibility_prompt(self) -> bool:
        try:
            import Quartz

            if hasattr(Quartz, "AXIsProcessTrustedWithOptions"):
                options = {Quartz.kAXTrustedCheckOptionPrompt: True}
                return bool(Quartz.AXIsProcessTrustedWithOptions(options))
        except Exception:
            LOGGER.debug("Quartz accessibility prompt failed", exc_info=True)
        # Fallback: use ctypes with kAXTrustedCheckOptionPrompt
        try:
            import ctypes
            import ctypes.util

            from Foundation import NSDictionary, NSNumber

            objc_path = ctypes.util.find_library("objc")
            if not objc_path:
                return self.check_accessibility()
            lib = ctypes.cdll.LoadLibrary(
                "/System/Library/Frameworks/ApplicationServices.framework"
                "/ApplicationServices"
            )
            lib.AXIsProcessTrustedWithOptions.restype = ctypes.c_bool
            lib.AXIsProcessTrustedWithOptions.argtypes = [ctypes.c_void_p]
            opts = NSDictionary.dictionaryWithObject_forKey_(
                NSNumber.numberWithBool_(True),
                "AXTrustedCheckOptionPrompt",
            )
            return lib.AXIsProcessTrustedWithOptions(opts)
        except Exception:
            LOGGER.debug("ctypes accessibility prompt failed", exc_info=True)
            return self.check_accessibility()

    def check_input_monitoring(self) -> bool:
        try:
            import Quartz

            if hasattr(Quartz, "CGPreflightListenEventAccess"):
                return bool(Quartz.CGPreflightListenEventAccess())
        except Exception:
            LOGGER.debug("Input monitoring preflight check failed", exc_info=True)

        try:
            from whisper_flow.hotkey import HotkeyListener

            return HotkeyListener.probe_event_tap()
        except Exception:
            LOGGER.debug("Input monitoring check failed", exc_info=True)
            return False

    def request_input_monitoring_prompt(self) -> bool:
        try:
            import Quartz

            if hasattr(Quartz, "CGRequestListenEventAccess"):
                return bool(Quartz.CGRequestListenEventAccess())
        except Exception:
            LOGGER.debug("Input monitoring prompt request failed", exc_info=True)
        return self.check_input_monitoring()

    def check_automation(self) -> bool:
        try:
            return self._inserter.preflight_automation_permission(prompt=False)
        except Exception:
            LOGGER.debug("Automation permission check failed", exc_info=True)
            return False

    def request_automation_prompt(self) -> bool:
        try:
            return self._inserter.preflight_automation_permission(prompt=True)
        except Exception:
            LOGGER.debug("Automation prompt request failed", exc_info=True)
            return False

    def check_all(self) -> PermissionState:
        return PermissionState(
            microphone=self.check_microphone(),
            accessibility=self.check_accessibility(),
            input_monitoring=self.check_input_monitoring(),
            automation=self.check_automation(),
        )

    def _privacy_settings_url(self, section: str) -> str:
        return f"x-apple.systempreferences:com.apple.preference.security?Privacy_{section}"

    def open_microphone_settings(self) -> None:
        subprocess.run(["open", self._privacy_settings_url("Microphone")], check=False)

    def open_accessibility_settings(self) -> None:
        subprocess.run(["open", self._privacy_settings_url("Accessibility")], check=False)

    def open_input_monitoring_settings(self) -> None:
        result = subprocess.run(["open", self._privacy_settings_url("ListenEvent")], check=False)
        if result.returncode != 0:
            subprocess.run(["open", self._privacy_settings_url("InputMonitoring")], check=False)

    def open_automation_settings(self) -> None:
        subprocess.run(["open", self._privacy_settings_url("Automation")], check=False)


__all__ = ["PermissionManager", "PermissionState"]
