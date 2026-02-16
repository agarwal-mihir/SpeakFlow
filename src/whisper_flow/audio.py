from __future__ import annotations

import logging
import threading
from dataclasses import dataclass

import numpy as np
import sounddevice as sd

LOGGER = logging.getLogger(__name__)


@dataclass
class AudioConfig:
    sample_rate: int = 16_000
    channels: int = 1
    dtype: str = "int16"
    silence_threshold: int = 450
    silence_padding_seconds: float = 0.12


class AudioRecorder:
    def __init__(self, config: AudioConfig | None = None) -> None:
        self.config = config or AudioConfig()
        self._frames: list[np.ndarray] = []
        self._lock = threading.Lock()
        self._stream: sd.InputStream | None = None
        self._live_level: float = 0.0

    @property
    def is_recording(self) -> bool:
        with self._lock:
            return self._stream is not None

    def _on_audio(self, indata: np.ndarray, frames: int, time, status) -> None:  # type: ignore[no-untyped-def]
        if status:
            LOGGER.warning("Audio stream status: %s", status)
        chunk = indata.copy()
        live_level = self._compute_live_level(chunk)
        with self._lock:
            self._frames.append(chunk)
            # Smooth sudden jumps a little so the indicator feels stable.
            self._live_level = max(0.0, min(1.0, (self._live_level * 0.60) + (live_level * 0.40)))

    def start(self) -> None:
        with self._lock:
            if self._stream is not None:
                return

            self._frames = []
            self._live_level = 0.0

            self._stream = sd.InputStream(
                samplerate=self.config.sample_rate,
                channels=self.config.channels,
                dtype=self.config.dtype,
                callback=self._on_audio,
                blocksize=0,
            )
            self._stream.start()

    def stop(self) -> np.ndarray:
        with self._lock:
            if self._stream is None:
                return np.array([], dtype=np.float32)

            stream = self._stream
            self._stream = None

        try:
            stream.stop()
        finally:
            stream.close()

        with self._lock:
            if not self._frames:
                self._live_level = 0.0
                return np.array([], dtype=np.float32)
            stacked = np.concatenate(self._frames, axis=0).reshape(-1)
            self._frames.clear()
            self._live_level = 0.0

        trimmed = self._trim_silence(stacked)
        if trimmed.size == 0:
            return np.array([], dtype=np.float32)

        return trimmed.astype(np.float32) / 32768.0

    def _trim_silence(self, samples: np.ndarray) -> np.ndarray:
        energy = np.abs(samples.astype(np.int32))
        voiced = np.where(energy > self.config.silence_threshold)[0]
        if voiced.size == 0:
            return np.array([], dtype=np.int16)

        pad = int(self.config.silence_padding_seconds * self.config.sample_rate)
        start = max(int(voiced[0]) - pad, 0)
        end = min(int(voiced[-1]) + pad + 1, samples.shape[0])
        return samples[start:end]

    def get_live_level(self) -> float:
        with self._lock:
            return self._live_level

    def reset_live_level(self) -> None:
        with self._lock:
            self._live_level = 0.0

    @staticmethod
    def _compute_live_level(samples: np.ndarray) -> float:
        if samples.size == 0:
            return 0.0
        normalized = samples.astype(np.float32).reshape(-1) / 32768.0
        rms = float(np.sqrt(np.mean(np.square(normalized))))
        # Expand low-level speech dynamics so quiet speech still moves the meter.
        return max(0.0, min(1.0, rms * 6.0))
