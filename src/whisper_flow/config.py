from __future__ import annotations

import json
import logging
import os
from dataclasses import asdict, dataclass, fields
from pathlib import Path
from typing import Literal

HotkeyMode = Literal["fn_hold", "fn_space_hold"]
LanguageMode = Literal["auto", "english", "hinglish_roman"]
InsertMode = Literal["clipboard_paste"]
CleanupProvider = Literal["lmstudio", "groq", "deterministic"]
CloseBehavior = Literal["hide_to_background"]
LoginWindowBehavior = Literal["open"]
UIDensity = Literal["comfortable", "compact"]

LOGGER = logging.getLogger(__name__)

APP_DIR = Path.home() / "Library" / "Application Support" / "SpeakFlow"
CONFIG_PATH = APP_DIR / "config.json"


@dataclass
class AppConfig:
    hotkey_mode: HotkeyMode = "fn_hold"
    language_mode: LanguageMode = "auto"
    stt_model: str = "large-v3"
    lmstudio_enabled: bool = True
    lmstudio_base_url: str = "http://127.0.0.1:1234/v1"
    lmstudio_model: str | None = None
    lmstudio_auto_start: bool = True
    lmstudio_start_timeout_ms: int = 8000
    cleanup_provider: CleanupProvider = "lmstudio"
    groq_base_url: str = "https://api.groq.com/openai/v1"
    groq_model: str = "meta-llama/llama-4-maverick-17b-128e-instruct"
    insert_mode: InsertMode = "clipboard_paste"
    max_cleanup_timeout_ms: int = 1000
    duck_system_audio_while_recording: bool = True
    duck_target_volume_percent: int = 8
    autostart_enabled: bool = True
    close_behavior: CloseBehavior = "hide_to_background"
    login_window_behavior: LoginWindowBehavior = "open"
    floating_indicator_enabled: bool = True
    floating_indicator_hide_delay_ms: int = 1000
    floating_indicator_origin_x: float | None = None
    floating_indicator_origin_y: float | None = None
    paste_last_shortcut_enabled: bool = True
    paste_failure_keep_dictation_in_clipboard: bool = True
    ui_last_tab: str = "home"
    ui_density: UIDensity = "comfortable"
    ui_show_welcome_card: bool = True

    def validate(self) -> None:
        if self.hotkey_mode not in {"fn_hold", "fn_space_hold"}:
            raise ValueError(f"Unsupported hotkey_mode: {self.hotkey_mode}")
        if self.language_mode not in {"auto", "english", "hinglish_roman"}:
            raise ValueError(f"Unsupported language_mode: {self.language_mode}")
        if self.insert_mode != "clipboard_paste":
            raise ValueError("Only clipboard_paste is currently supported")
        if self.cleanup_provider not in {"lmstudio", "groq", "deterministic"}:
            raise ValueError(f"Unsupported cleanup_provider: {self.cleanup_provider}")
        if self.max_cleanup_timeout_ms < 200:
            raise ValueError("max_cleanup_timeout_ms must be >= 200")
        if self.lmstudio_start_timeout_ms < 500:
            raise ValueError("lmstudio_start_timeout_ms must be >= 500")
        if not self.groq_model.strip():
            raise ValueError("groq_model cannot be empty")
        if self.duck_target_volume_percent < 0 or self.duck_target_volume_percent > 100:
            raise ValueError("duck_target_volume_percent must be between 0 and 100")
        if self.close_behavior != "hide_to_background":
            raise ValueError("Only hide_to_background close behavior is supported")
        if self.login_window_behavior != "open":
            raise ValueError("Only open login_window_behavior is supported")
        if self.floating_indicator_hide_delay_ms < 200 or self.floating_indicator_hide_delay_ms > 10000:
            raise ValueError("floating_indicator_hide_delay_ms must be between 200 and 10000")
        if self.floating_indicator_origin_x is not None and not isinstance(
            self.floating_indicator_origin_x, (int, float)
        ):
            raise ValueError("floating_indicator_origin_x must be a number or null")
        if self.floating_indicator_origin_y is not None and not isinstance(
            self.floating_indicator_origin_y, (int, float)
        ):
            raise ValueError("floating_indicator_origin_y must be a number or null")
        if self.ui_density not in {"comfortable", "compact"}:
            raise ValueError(f"Unsupported ui_density: {self.ui_density}")
        if not self.ui_last_tab:
            raise ValueError("ui_last_tab cannot be empty")


class ConfigStore:
    def __init__(self, path: Path = CONFIG_PATH) -> None:
        self.path = path

    def ensure_dir(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)

    def load(self) -> AppConfig:
        self.ensure_dir()
        try:
            raw_text = self.path.read_text(encoding="utf-8")
        except FileNotFoundError:
            cfg = AppConfig()
            self.save(cfg)
            return cfg

        try:
            raw = json.loads(raw_text)
            known_keys = {f.name for f in fields(AppConfig)}
            cfg = AppConfig(**{k: v for k, v in raw.items() if k in known_keys})
            cfg.validate()
            return cfg
        except (json.JSONDecodeError, TypeError, ValueError) as exc:
            LOGGER.warning("Config file corrupt or invalid, using defaults: %s", exc)
            return AppConfig()

    def save(self, config: AppConfig) -> None:
        config.validate()
        self.ensure_dir()
        tmp_path = self.path.with_suffix('.tmp')
        tmp_path.write_text(
            json.dumps(asdict(config), indent=2, sort_keys=True),
            encoding="utf-8",
        )
        os.replace(str(tmp_path), str(self.path))
