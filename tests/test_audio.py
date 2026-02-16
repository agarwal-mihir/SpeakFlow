import numpy as np

from whisper_flow.audio import AudioConfig, AudioRecorder


class FakeInputStream:
    instances = []

    def __init__(self, *, samplerate, channels, dtype, callback, blocksize):
        self.samplerate = samplerate
        self.channels = channels
        self.dtype = dtype
        self.callback = callback
        self.blocksize = blocksize
        self.started = False
        self.stopped = False
        self.closed = False
        FakeInputStream.instances.append(self)

    def start(self) -> None:
        self.started = True

    def stop(self) -> None:
        self.stopped = True

    def close(self) -> None:
        self.closed = True


def test_start_and_stop_returns_trimmed_normalized_audio(monkeypatch) -> None:
    FakeInputStream.instances.clear()
    monkeypatch.setattr("whisper_flow.audio.sd.InputStream", FakeInputStream)

    recorder = AudioRecorder(AudioConfig(sample_rate=16000, silence_threshold=10, silence_padding_seconds=0))
    recorder.start()

    stream = FakeInputStream.instances[0]
    assert stream.started is True
    assert recorder.is_recording is True

    # Keep only voiced samples (> threshold) after trimming.
    chunk = np.array([[0], [20], [-30], [0]], dtype=np.int16)
    stream.callback(chunk, 4, None, None)

    out = recorder.stop()

    assert recorder.is_recording is False
    assert stream.stopped is True
    assert stream.closed is True
    assert out.dtype == np.float32
    assert out.shape == (2,)
    assert np.allclose(out, np.array([20 / 32768.0, -30 / 32768.0], dtype=np.float32))


def test_start_is_idempotent(monkeypatch) -> None:
    FakeInputStream.instances.clear()
    monkeypatch.setattr("whisper_flow.audio.sd.InputStream", FakeInputStream)

    recorder = AudioRecorder()
    recorder.start()
    recorder.start()

    assert len(FakeInputStream.instances) == 1


def test_stop_without_start_returns_empty() -> None:
    recorder = AudioRecorder()
    out = recorder.stop()
    assert out.shape == (0,)
    assert out.dtype == np.float32


def test_stop_with_no_frames_returns_empty(monkeypatch) -> None:
    FakeInputStream.instances.clear()
    monkeypatch.setattr("whisper_flow.audio.sd.InputStream", FakeInputStream)

    recorder = AudioRecorder()
    recorder.start()
    out = recorder.stop()

    assert out.shape == (0,)
    assert out.dtype == np.float32


def test_trim_silence_returns_empty_when_no_voiced() -> None:
    recorder = AudioRecorder(AudioConfig(silence_threshold=1000))
    samples = np.array([1, 10, 200], dtype=np.int16)

    trimmed = recorder._trim_silence(samples)

    assert trimmed.shape == (0,)


def test_trim_silence_applies_padding_and_bounds() -> None:
    config = AudioConfig(sample_rate=10, silence_threshold=5, silence_padding_seconds=0.2)
    recorder = AudioRecorder(config)
    samples = np.array([0, 0, 0, 0, 0, 9, 0, 0, 0, 0], dtype=np.int16)

    trimmed = recorder._trim_silence(samples)

    # voiced at idx 5, pad=2 => [3:8]
    assert np.array_equal(trimmed, np.array([0, 0, 9, 0, 0], dtype=np.int16))


def test_live_level_updates_from_audio_callback(monkeypatch) -> None:
    FakeInputStream.instances.clear()
    monkeypatch.setattr("whisper_flow.audio.sd.InputStream", FakeInputStream)

    recorder = AudioRecorder(AudioConfig(sample_rate=16000, silence_threshold=10))
    recorder.start()
    stream = FakeInputStream.instances[0]

    quiet = np.array([[500], [500], [500], [500]], dtype=np.int16)
    loud = np.array([[12000], [12000], [12000], [12000]], dtype=np.int16)
    stream.callback(quiet, 4, None, None)
    quiet_level = recorder.get_live_level()
    stream.callback(loud, 4, None, None)
    loud_level = recorder.get_live_level()

    assert 0.0 <= quiet_level <= 1.0
    assert 0.0 <= loud_level <= 1.0
    assert loud_level > quiet_level


def test_reset_live_level_clears_meter() -> None:
    recorder = AudioRecorder()
    recorder._live_level = 0.75

    recorder.reset_live_level()

    assert recorder.get_live_level() == 0.0
