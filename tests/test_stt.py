import types

import numpy as np

from whisper_flow.stt import STTEngine


class _Segment:
    def __init__(self, text: str) -> None:
        self.text = text


class _Info:
    def __init__(self, language: str, language_probability: float) -> None:
        self.language = language
        self.language_probability = language_probability


def test_transcribe_empty_audio_returns_empty_result() -> None:
    engine = STTEngine("large-v3")

    result = engine.transcribe(np.array([], dtype=np.float32))

    assert result.raw_text == ""
    assert result.detected_language is None
    assert result.confidence is None
    assert result.is_mixed_script is False


def test_ensure_model_loads_once_and_caches(monkeypatch) -> None:
    calls = []

    class FakeWhisperModel:
        def __init__(self, model_name, device, compute_type):
            calls.append((model_name, device, compute_type))

    fake_module = types.SimpleNamespace(WhisperModel=FakeWhisperModel)
    monkeypatch.setitem(__import__("sys").modules, "faster_whisper", fake_module)

    engine = STTEngine("large-v3")
    model_a = engine._ensure_model()
    model_b = engine._ensure_model()

    assert model_a is model_b
    assert calls == [("large-v3", "auto", "auto")]


def test_transcribe_joins_segments_and_marks_mixed_script() -> None:
    class FakeModel:
        def transcribe(self, *_args, **_kwargs):
            return [
                _Segment("hello"),
                _Segment("भाई"),
            ], _Info("hi", 0.91)

    engine = STTEngine("large-v3")
    engine._model = FakeModel()

    result = engine.transcribe(np.array([0.1, -0.2], dtype=np.float32))

    assert result.raw_text == "hello भाई"
    assert result.detected_language == "hi"
    assert result.confidence == 0.91
    assert result.is_mixed_script is True


def test_transcribe_marks_non_mixed_for_ascii_text() -> None:
    class FakeModel:
        def transcribe(self, *_args, **_kwargs):
            return [_Segment("hello there")], _Info("en", 0.83)

    engine = STTEngine("large-v3")
    engine._model = FakeModel()

    result = engine.transcribe(np.array([0.2], dtype=np.float32))

    assert result.raw_text == "hello there"
    assert result.detected_language == "en"
    assert result.is_mixed_script is False
