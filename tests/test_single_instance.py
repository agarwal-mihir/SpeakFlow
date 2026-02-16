from pathlib import Path

import whisper_flow.single_instance as single_instance


def test_acquire_single_instance_lock_success(monkeypatch, tmp_path: Path) -> None:
    lock_path = tmp_path / "instance.lock"

    # reset global
    single_instance._LOCK_HANDLE = None

    called = []

    def fake_flock(fd, op):  # noqa: ARG001
        called.append(op)

    monkeypatch.setattr(single_instance.fcntl, "flock", fake_flock)

    acquired = single_instance.acquire_single_instance_lock(lock_path)

    assert acquired is True
    assert lock_path.exists()
    assert called


def test_acquire_single_instance_lock_failure(monkeypatch, tmp_path: Path) -> None:
    lock_path = tmp_path / "instance.lock"

    # reset global
    single_instance._LOCK_HANDLE = None

    def fake_flock(fd, op):  # noqa: ARG001
        raise OSError("busy")

    monkeypatch.setattr(single_instance.fcntl, "flock", fake_flock)

    acquired = single_instance.acquire_single_instance_lock(lock_path)

    assert acquired is False


def test_release_single_instance_lock_noop_when_unset() -> None:
    single_instance._LOCK_HANDLE = None
    single_instance.release_single_instance_lock()
    assert single_instance._LOCK_HANDLE is None
