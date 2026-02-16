from __future__ import annotations

import logging
import threading
from dataclasses import dataclass
from typing import Any

import numpy as np

from whisper_flow.language import mixed_script_ratio

LOGGER = logging.getLogger(__name__)


@dataclass
class TranscriptResult:
    raw_text: str
    detected_language: str | None
    confidence: float | None
    is_mixed_script: bool


class STTEngine:
    def __init__(self, model_name: str) -> None:
        self.model_name = model_name
        self._model: Any | None = None
        self._model_lock = threading.Lock()

    def _ensure_model(self) -> Any:
        with self._model_lock:
            if self._model is not None:
                return self._model

            from faster_whisper import WhisperModel

            LOGGER.info("Loading faster-whisper model: %s", self.model_name)
            self._model = WhisperModel(self.model_name, device="auto", compute_type="auto")
            return self._model

    def transcribe(self, audio: np.ndarray) -> TranscriptResult:
        if audio.size == 0:
            return TranscriptResult("", None, None, False)

        model = self._ensure_model()
        segments, info = model.transcribe(
            audio,
            beam_size=5,
            task="transcribe",
            condition_on_previous_text=False,
            vad_filter=False,
        )
        text = " ".join(segment.text.strip() for segment in segments).strip()

        mixed_ratio = mixed_script_ratio(text)
        return TranscriptResult(
            raw_text=text,
            detected_language=getattr(info, "language", None),
            confidence=getattr(info, "language_probability", None),
            is_mixed_script=mixed_ratio >= 0.07,
        )
