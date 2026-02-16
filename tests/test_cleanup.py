import types

import requests

import whisper_flow.cleanup as cleanup_module
from whisper_flow.cleanup import LMStudioClient, TextCleanup
from whisper_flow.config import AppConfig


class FakeTranscript:
    def __init__(self, raw_text: str, detected_language: str, confidence: float, is_mixed_script: bool) -> None:
        self.raw_text = raw_text
        self.detected_language = detected_language
        self.confidence = confidence
        self.is_mixed_script = is_mixed_script


class FakeResponse:
    def __init__(self, payload: dict, status_code: int = 200) -> None:
        self._payload = payload
        self.status_code = status_code

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise requests.HTTPError(f"HTTP {self.status_code}")

    def json(self) -> dict:
        return self._payload


class FakeSecretStore:
    def __init__(self, key: str | None = None) -> None:
        self.key = key

    def get_groq_api_key(self) -> str | None:
        return self.key


def test_cleanup_without_lmstudio_uses_deterministic_english() -> None:
    cfg = AppConfig(lmstudio_enabled=False, language_mode="english")
    cleanup = TextCleanup(cfg)
    transcript = FakeTranscript(
        raw_text="hello from dictation",
        detected_language="en",
        confidence=0.92,
        is_mixed_script=False,
    )

    result = cleanup.clean(transcript)
    assert result.text == "Hello from dictation."
    assert result.output_mode == "english"
    assert result.used_lmstudio is False


def test_cleanup_auto_hinglish_romanizes_when_needed() -> None:
    cfg = AppConfig(lmstudio_enabled=False, language_mode="auto")
    cleanup = TextCleanup(cfg)
    transcript = FakeTranscript(
        raw_text="भाई kya haal hai",
        detected_language="hi",
        confidence=0.9,
        is_mixed_script=True,
    )

    result = cleanup.clean(transcript)
    assert result.text.endswith(".")
    assert "bh" in result.text.lower()
    assert result.output_mode == "hinglish_roman"


def test_cleanup_uses_lmstudio_rewrite_when_available() -> None:
    cfg = AppConfig(lmstudio_enabled=True, language_mode="english")
    cleanup = TextCleanup(cfg)
    cleanup._lmstudio = types.SimpleNamespace(rewrite=lambda _text, _mode: "Hello there!")

    result = cleanup.clean(FakeTranscript("hello there", "en", 0.8, False))

    assert result.text == "Hello there!"
    assert result.used_lmstudio is True


def test_cleanup_uses_groq_rewrite_when_selected() -> None:
    cfg = AppConfig(
        cleanup_provider="groq",
        lmstudio_enabled=True,
        language_mode="english",
    )
    cleanup = TextCleanup(cfg, secret_store=FakeSecretStore("groq-test-key"))
    cleanup._groq = types.SimpleNamespace(rewrite=lambda _text, _mode: "Hello there!")

    result = cleanup.clean(FakeTranscript("hello there", "en", 0.8, False))

    assert result.text == "Hello there!"
    assert result.used_lmstudio is False
    assert result.rewrite_provider == "groq"


def test_cleanup_falls_back_when_groq_key_missing() -> None:
    cfg = AppConfig(
        cleanup_provider="groq",
        lmstudio_enabled=True,
        language_mode="english",
    )
    cleanup = TextCleanup(cfg, secret_store=FakeSecretStore(None))

    result = cleanup.clean(FakeTranscript("hello there", "en", 0.8, False))

    assert result.text == "Hello there."
    assert result.rewrite_provider is None


def test_cleanup_falls_back_when_lmstudio_returns_none() -> None:
    cfg = AppConfig(lmstudio_enabled=True, language_mode="english")
    cleanup = TextCleanup(cfg)
    cleanup._lmstudio = types.SimpleNamespace(rewrite=lambda _text, _mode: None)

    result = cleanup.clean(FakeTranscript("hello there", "en", 0.8, False))

    assert result.text == "Hello there."
    assert result.used_lmstudio is False


def test_cleanup_rejects_meta_lmstudio_output() -> None:
    cfg = AppConfig(lmstudio_enabled=True, language_mode="english")
    cleanup = TextCleanup(cfg)
    cleanup._lmstudio = types.SimpleNamespace(
        rewrite=lambda _text, _mode: "Certainly! Here's a cleaned-up version: Hello there."
    )

    result = cleanup.clean(FakeTranscript("hello there", "en", 0.8, False))

    assert result.text == "Hello there."
    assert result.used_lmstudio is False


def test_cleanup_rejects_hinglish_translation_from_lmstudio() -> None:
    cfg = AppConfig(lmstudio_enabled=True, language_mode="auto")
    cleanup = TextCleanup(cfg)
    cleanup._lmstudio = types.SimpleNamespace(rewrite=lambda _text, _mode: "Brother, what is going on?")

    result = cleanup.clean(FakeTranscript("bhai kya haal hai", "hi", 0.92, True))

    assert "bhai" in result.text.lower()
    assert "kya" in result.text.lower()
    assert result.used_lmstudio is False


def test_cleanup_accepts_valid_hinglish_rewrite() -> None:
    cfg = AppConfig(lmstudio_enabled=True, language_mode="auto")
    cleanup = TextCleanup(cfg)
    cleanup._lmstudio = types.SimpleNamespace(rewrite=lambda _text, _mode: "Bhai, kya haal hai?")

    result = cleanup.clean(FakeTranscript("bhai kya haal hai", "hi", 0.92, True))

    assert result.text == "Bhai, kya haal hai?"
    assert result.used_lmstudio is True


def test_update_config_recreates_lmstudio_client() -> None:
    cleanup = TextCleanup(AppConfig(lmstudio_base_url="http://127.0.0.1:1234/v1"), secret_store=FakeSecretStore("x"))
    old_client = cleanup._lmstudio
    old_groq = cleanup._groq

    cleanup.update_config(AppConfig(lmstudio_base_url="http://127.0.0.1:9000/v1", lmstudio_model="x"))

    assert cleanup._lmstudio is not old_client
    assert cleanup._groq is not old_groq
    assert cleanup._lmstudio.base_url == "http://127.0.0.1:9000/v1"
    assert cleanup._lmstudio.model == "x"


def test_lmstudio_client_resolves_model_from_models_endpoint(monkeypatch) -> None:
    client = LMStudioClient(base_url="http://127.0.0.1:1234/v1", timeout_ms=800)

    def fake_get(url, timeout):
        assert url.endswith("/models")
        assert timeout == 0.8
        return FakeResponse({"data": [{"id": "local-model"}]})

    monkeypatch.setattr(cleanup_module.requests, "get", fake_get)

    assert client._resolve_model() == "local-model"
    assert client.model == "local-model"


def test_lmstudio_client_autostarts_when_server_unreachable(monkeypatch) -> None:
    client = LMStudioClient(base_url="http://127.0.0.1:1234/v1", timeout_ms=800, auto_start=True, start_timeout_ms=2000)
    calls = {"get": 0, "open": 0}

    def fake_get(url, timeout):  # noqa: ARG001
        calls["get"] += 1
        if calls["get"] == 1:
            raise requests.ConnectionError("offline")
        return FakeResponse({"data": [{"id": "local-model"}]})

    def fake_run(cmd, check, capture_output, text, timeout):  # noqa: ARG001
        calls["open"] += 1
        assert cmd == ["open", "-a", "LM Studio"]
        return types.SimpleNamespace(returncode=0, stdout="", stderr="")

    monkeypatch.setattr(cleanup_module.requests, "get", fake_get)
    monkeypatch.setattr(cleanup_module.subprocess, "run", fake_run)
    monkeypatch.setattr(cleanup_module.time, "sleep", lambda _seconds: None)

    assert client._resolve_model() == "local-model"
    assert calls["open"] == 1


def test_lmstudio_client_rewrite_returns_none_when_no_choices(monkeypatch) -> None:
    client = LMStudioClient(base_url="http://127.0.0.1:1234/v1", timeout_ms=800, model="local-model")

    def fake_post(url, json, timeout):
        assert url.endswith("/chat/completions")
        assert json["model"] == "local-model"
        assert timeout == 0.8
        return FakeResponse({"choices": []})

    monkeypatch.setattr(cleanup_module.requests, "post", fake_post)

    assert client.rewrite("hello", "english") is None


def test_groq_client_sends_auth_header(monkeypatch) -> None:
    cfg = AppConfig(cleanup_provider="groq", lmstudio_enabled=True)
    cleanup = TextCleanup(cfg, secret_store=FakeSecretStore("gsk_123"))

    def fake_post(url, json, headers, timeout):  # noqa: ARG001
        assert url.endswith("/chat/completions")
        assert headers["Authorization"] == "Bearer gsk_123"
        assert json["model"] == cfg.groq_model
        return FakeResponse({"choices": [{"message": {"content": "Hello there!"}}]})

    monkeypatch.setattr(cleanup_module.requests, "post", fake_post)

    assert cleanup._groq.rewrite("hello there", "english") == "Hello there!"


def test_lmstudio_client_rewrite_handles_http_error(monkeypatch) -> None:
    client = LMStudioClient(base_url="http://127.0.0.1:1234/v1", timeout_ms=800, model="local-model")

    def fake_post(*_args, **_kwargs):
        return FakeResponse({}, status_code=500)

    monkeypatch.setattr(cleanup_module.requests, "post", fake_post)

    assert client.rewrite("hello", "english") is None
