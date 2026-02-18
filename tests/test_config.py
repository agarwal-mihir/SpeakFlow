import json
from pathlib import Path

import pytest

from whisper_flow.config import AppConfig, ConfigStore


def test_config_store_writes_and_reads(tmp_path: Path) -> None:
    store = ConfigStore(path=tmp_path / "config.json")
    config = AppConfig(language_mode="hinglish_roman", lmstudio_enabled=False)

    store.save(config)
    loaded = store.load()

    assert loaded.language_mode == "hinglish_roman"
    assert loaded.lmstudio_enabled is False
    assert loaded.lmstudio_auto_start is True
    assert loaded.lmstudio_start_timeout_ms == 8000
    assert loaded.cleanup_provider == "priority"
    assert loaded.groq_base_url == "https://api.groq.com/openai/v1"
    assert loaded.groq_model == "meta-llama/llama-4-maverick-17b-128e-instruct"
    assert loaded.duck_system_audio_while_recording is True
    assert loaded.duck_target_volume_percent == 8
    assert loaded.close_behavior == "hide_to_background"
    assert loaded.login_window_behavior == "open"
    assert loaded.floating_indicator_enabled is True
    assert loaded.floating_indicator_hide_delay_ms == 1000
    assert loaded.floating_indicator_origin_x is None
    assert loaded.floating_indicator_origin_y is None
    assert loaded.paste_last_shortcut_enabled is True
    assert loaded.paste_failure_keep_dictation_in_clipboard is True
    assert loaded.ui_last_tab == "home"
    assert loaded.ui_density == "comfortable"
    assert loaded.ui_show_welcome_card is True


def test_load_creates_default_file_when_missing(tmp_path: Path) -> None:
    path = tmp_path / "nested" / "config.json"
    store = ConfigStore(path=path)

    loaded = store.load()

    assert path.exists()
    assert loaded.hotkey_mode == "fn_hold"
    assert loaded.language_mode == "auto"


def test_load_ignores_unknown_keys(tmp_path: Path) -> None:
    path = tmp_path / "config.json"
    payload = {
        "hotkey_mode": "fn_space_hold",
        "language_mode": "english",
        "unknown_field": "ignored",
    }
    path.write_text(json.dumps(payload), encoding="utf-8")

    loaded = ConfigStore(path=path).load()

    assert loaded.hotkey_mode == "fn_space_hold"
    assert loaded.language_mode == "english"
    assert not hasattr(loaded, "unknown_field")


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("hotkey_mode", "bad"),
        ("language_mode", "bad"),
        ("insert_mode", "keyboard"),
        ("cleanup_provider", "openai"),
        ("max_cleanup_timeout_ms", 150),
        ("lmstudio_start_timeout_ms", 200),
        ("groq_model", ""),
        ("duck_target_volume_percent", -1),
        ("duck_target_volume_percent", 101),
        ("close_behavior", "quit"),
        ("login_window_behavior", "hidden"),
        ("floating_indicator_hide_delay_ms", 100),
        ("floating_indicator_hide_delay_ms", 20001),
        ("floating_indicator_origin_x", "left"),
        ("floating_indicator_origin_y", "bottom"),
        ("ui_density", "dense"),
        ("ui_last_tab", ""),
    ],
)
def test_validation_rejects_unsupported_values(field: str, value) -> None:  # type: ignore[no-untyped-def]
    cfg = AppConfig()
    setattr(cfg, field, value)

    with pytest.raises(ValueError):
        cfg.validate()
