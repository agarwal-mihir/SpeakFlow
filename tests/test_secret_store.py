from __future__ import annotations

import whisper_flow.secret_store as secret_store_module
from whisper_flow.secret_store import GROQ_API_KEY_ACCOUNT, LOGIN_KEYCHAIN_PATH, SecretStore


class FakeResult:
    def __init__(self, returncode: int = 0, stdout: str = "", stderr: str = "") -> None:
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


def test_get_groq_api_key_prefers_env(monkeypatch) -> None:
    monkeypatch.setenv("GROQ_API_KEY", "env-secret")
    calls = []
    monkeypatch.setattr(secret_store_module.subprocess, "run", lambda *args, **kwargs: calls.append((args, kwargs)))

    store = SecretStore(service_name="svc")
    assert store.get_groq_api_key() == "env-secret"
    assert calls == []


def test_set_and_get_groq_api_key_via_security(monkeypatch) -> None:
    monkeypatch.delenv("GROQ_API_KEY", raising=False)
    calls: list[list[str]] = []

    def fake_run(cmd, check, capture_output, text, timeout):  # noqa: ARG001
        calls.append(cmd)
        if cmd[1] == "find-generic-password":
            return FakeResult(stdout="stored-key\n")
        return FakeResult()

    monkeypatch.setattr(secret_store_module.subprocess, "run", fake_run)

    store = SecretStore(service_name="svc")
    store.set_groq_api_key("stored-key")
    value = store.get_groq_api_key()

    assert value == "stored-key"
    assert calls[0][:2] == ["security", "add-generic-password"]
    assert "stored-key" in calls[0]
    assert calls[0][-1] == str(LOGIN_KEYCHAIN_PATH)
    assert calls[1][:2] == ["security", "find-generic-password"]
    assert calls[1][-1] == str(LOGIN_KEYCHAIN_PATH)
    assert GROQ_API_KEY_ACCOUNT in calls[0]


def test_delete_groq_api_key_is_non_fatal(monkeypatch) -> None:
    monkeypatch.delenv("GROQ_API_KEY", raising=False)

    def fake_run(cmd, check, capture_output, text, timeout):  # noqa: ARG001
        return FakeResult(returncode=44, stderr="not found")

    monkeypatch.setattr(secret_store_module.subprocess, "run", fake_run)

    store = SecretStore(service_name="svc")
    store.delete_groq_api_key()
    assert store.has_groq_api_key() is False


def test_set_groq_api_key_rejects_empty() -> None:
    store = SecretStore(service_name="svc")
    try:
        store.set_groq_api_key("  ")
    except ValueError:
        pass
    else:
        raise AssertionError("Expected ValueError for empty key")
