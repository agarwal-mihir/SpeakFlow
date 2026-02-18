from __future__ import annotations

import logging
import os
from pathlib import Path
import subprocess

LOGGER = logging.getLogger(__name__)

DEFAULT_KEYCHAIN_SERVICE = "com.speakflow.desktop"
GROQ_API_KEY_ACCOUNT = "groq_api_key"
LOGIN_KEYCHAIN_PATH = Path.home() / "Library" / "Keychains" / "login.keychain-db"
SECURITY_TIMEOUT_SECONDS = 30.0


class SecretStore:
    """Small keychain wrapper for storing provider API keys securely on macOS."""

    def __init__(self, service_name: str = DEFAULT_KEYCHAIN_SERVICE) -> None:
        self.service_name = service_name
        self.keychain_path = str(LOGIN_KEYCHAIN_PATH)

    def get_groq_api_key(self) -> str | None:
        env_key = os.getenv("GROQ_API_KEY")
        if env_key:
            return env_key.strip()

        result = self._run_security(
            [
                "find-generic-password",
                "-a",
                GROQ_API_KEY_ACCOUNT,
                "-s",
                self.service_name,
                "-w",
                self.keychain_path,
            ]
        )
        if result is None:
            return None
        value = result.strip()
        return value or None

    def has_groq_api_key(self) -> bool:
        return bool(self.get_groq_api_key())

    def set_groq_api_key(self, api_key: str) -> None:
        value = api_key.strip()
        if not value:
            raise ValueError("API key cannot be empty")

        self._run_security(
            [
                "add-generic-password",
                "-a",
                GROQ_API_KEY_ACCOUNT,
                "-s",
                self.service_name,
                "-U",
                "-w",
                value,
                self.keychain_path,
            ],
            required=True,
        )

    def delete_groq_api_key(self) -> None:
        self._run_security(
            [
                "delete-generic-password",
                "-a",
                GROQ_API_KEY_ACCOUNT,
                "-s",
                self.service_name,
                self.keychain_path,
            ],
            required=False,
        )

    def _run_security(self, args: list[str], required: bool = False) -> str | None:
        try:
            result = subprocess.run(
                ["security", *args],
                check=False,
                capture_output=True,
                text=True,
                timeout=SECURITY_TIMEOUT_SECONDS,
            )
        except FileNotFoundError:
            if required:
                raise RuntimeError("macOS security command not found") from None
            LOGGER.warning("macOS security command not found")
            return None
        except subprocess.TimeoutExpired:
            message = (
                "Timed out waiting for Keychain authorization. "
                "Please unlock the login keychain in Keychain Access and retry."
            )
            if required:
                raise RuntimeError(message) from None
            LOGGER.warning(message)
            return None
        except subprocess.SubprocessError:
            if required:
                raise RuntimeError("Keychain command failed unexpectedly") from None
            LOGGER.warning("Keychain command failed unexpectedly", exc_info=True)
            return None

        if result.returncode != 0:
            stderr = result.stderr.strip()
            if required:
                message = (
                    "Unable to store Groq API key in Keychain. "
                    "Open Keychain Access, unlock the 'login' keychain, and retry."
                )
                if stderr:
                    message = f"{message} Details: {stderr}"
                if "Unable to obtain authorization for this operation" in stderr:
                    message = (
                        "Keychain authorization denied. "
                        "Open Keychain Access, unlock the 'login' keychain, "
                        "then retry saving the key."
                    )
                LOGGER.warning("Keychain command failed: %s", stderr)
                raise RuntimeError(message) from None
            else:
                LOGGER.debug("Keychain command failed: %s", stderr)
            return None
        return result.stdout
