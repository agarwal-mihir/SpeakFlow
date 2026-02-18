from pathlib import Path

import numpy as np

import whisper_flow.ui.controller as controller_module
from whisper_flow.config import AppConfig
from whisper_flow.permissions import PermissionState
from whisper_flow.ui import AppController, ServiceState


class FakeConfigStore:
    def __init__(self):
        self.path = Path("/tmp/test-config.json")
        self.saved = None

    def load(self):
        return AppConfig()

    def save(self, config):
        self.saved = config


class FakeRecorder:
    def __init__(self):
        self.is_recording = False
        self.next_audio = np.array([0.1], dtype=np.float32)
        self.live_level = 0.0

    def start(self):
        self.is_recording = True

    def stop(self):
        self.is_recording = False
        return self.next_audio

    def get_live_level(self):
        return self.live_level

    def reset_live_level(self):
        self.live_level = 0.0


class FakeSTTEngine:
    def __init__(self, _model_name):
        pass


class FakeCleanup:
    def __init__(self, _config, secret_store=None):  # noqa: ARG002
        pass

    def update_config(self, _config):
        return None


class FakeInserter:
    def __init__(self, keep_dictation_on_failure=False):
        self.keep_dictation_on_failure = keep_dictation_on_failure
        self.calls = []

    def insert_text(self, text, restore_clipboard=True, target_pid=None, keep_dictation_on_failure=None):
        self.calls.append(
            {
                "text": text,
                "restore_clipboard": restore_clipboard,
                "target_pid": target_pid,
                "keep_dictation_on_failure": keep_dictation_on_failure,
            }
        )


class FakeFloatingIndicator:
    def __init__(self):
        self.hide_delay_ms = 1000
        self.enabled = True
        self.on_move = None
        self.origin = None
        self.events = []
        self.hidden = False

    @classmethod
    def alloc(cls):
        return cls()

    def initWithHideDelayMs_enabled_onMove_(self, hide_delay_ms, enabled, on_move):  # noqa: N802
        self.hide_delay_ms = hide_delay_ms
        self.enabled = enabled
        self.on_move = on_move
        return self

    def set_origin(self, x, y):
        self.origin = (x, y)

    def set_enabled(self, enabled):
        self.enabled = enabled

    def set_hide_delay_ms(self, hide_delay_ms):
        self.hide_delay_ms = hide_delay_ms

    def show_recording(self, level=0.0):
        self.events.append(("recording", level))

    def show_transcribing(self):
        self.events.append(("transcribing", None))

    def show_done(self, message="Done"):
        self.events.append(("done", message))

    def show_error(self, message):
        self.events.append(("error", message))

    def update_meter(self, level):
        self.events.append(("meter", level))

    def hide(self):
        self.hidden = True
        self.events.append(("hide", None))


class FakeHistory:
    def __init__(self):
        self.added = []

    def search(self, _query, limit=250, offset=0):  # noqa: ARG002
        return []

    def stats(self):
        return {
            "total_count": 0,
            "latest_created_at": "",
            "latest_source_app": "Unknown",
            "top_source_app": "Unknown",
            "top_source_app_count": 0,
        }

    def add(self, **kwargs):
        self.added.append(kwargs)

    def delete(self, _id):  # noqa: A002
        return None


class FakeContentStore:
    def list_dictionary(self, _query, limit=300, offset=0):  # noqa: ARG002
        return []

    def list_snippets(self, _query, limit=300, offset=0):  # noqa: ARG002
        return []

    def list_styles(self, _query, limit=300, offset=0):  # noqa: ARG002
        return []

    def list_notes(self, _query, limit=300, offset=0):  # noqa: ARG002
        return []


class FakePermissionManager:
    def __init__(self, _inserter=None):
        pass

    def check_all(self):
        return PermissionState(True, True, True, True)

    def request_input_monitoring_prompt(self):
        return True


class FakeHotkeyListener:
    def __init__(self, mode, callbacks):
        self.mode = mode
        self.callbacks = callbacks
        self.start_calls = 0
        self.stop_calls = 0

    def start(self):
        self.start_calls += 1

    def stop(self):
        self.stop_calls += 1

    def reconfigure(self, mode):
        self.mode = mode


class FakeAudioDucker:
    def __init__(self, enabled, target_volume_percent):
        self.enabled = enabled
        self.target_volume_percent = target_volume_percent
        self.duck_calls = 0
        self.restore_calls = 0

    def duck(self):
        self.duck_calls += 1

    def restore(self):
        self.restore_calls += 1


class FakeSecretStore:
    def __init__(self):
        self.value = None

    def has_groq_api_key(self):
        return bool(self.value)

    def get_groq_api_key(self):
        return self.value

    def set_groq_api_key(self, api_key):
        self.value = api_key

    def delete_groq_api_key(self):
        self.value = None


class FakeWindow:
    def __init__(self):
        self.hidden = False

    def orderOut_(self, _sender):
        self.hidden = True


def _build_controller(monkeypatch) -> AppController:
    monkeypatch.setattr(controller_module, "ConfigStore", FakeConfigStore)
    monkeypatch.setattr(controller_module, "AudioRecorder", FakeRecorder)
    monkeypatch.setattr(controller_module, "STTEngine", FakeSTTEngine)
    monkeypatch.setattr(controller_module, "TextCleanup", FakeCleanup)
    monkeypatch.setattr(controller_module, "TextInserter", FakeInserter)
    monkeypatch.setattr(controller_module, "TranscriptHistoryStore", FakeHistory)
    monkeypatch.setattr(controller_module, "ContentStore", FakeContentStore)
    monkeypatch.setattr(controller_module, "PermissionManager", FakePermissionManager)
    monkeypatch.setattr(controller_module, "HotkeyListener", FakeHotkeyListener)
    monkeypatch.setattr(controller_module, "SystemAudioDucker", FakeAudioDucker)
    monkeypatch.setattr(controller_module, "SecretStore", FakeSecretStore)
    monkeypatch.setattr(controller_module, "FloatingIndicatorController", FakeFloatingIndicator)

    controller = AppController.alloc().init()
    return controller


def test_toggle_service_requires_permissions(monkeypatch) -> None:
    controller = _build_controller(monkeypatch)
    controller._permissions_ready = False
    controller._service_enabled = True

    opened = []
    alerts = []
    monkeypatch.setattr(controller, "openPermissionWizard_", lambda _sender: opened.append(True))
    monkeypatch.setattr(controller, "_show_alert", lambda title, message: alerts.append((title, message)))

    controller._toggle_service()

    assert controller._service_enabled is True
    assert opened == [True]
    assert alerts and alerts[0][0] == "Permissions Required"


def test_toggle_service_toggles_and_syncs_when_ready(monkeypatch) -> None:
    controller = _build_controller(monkeypatch)
    controller._permissions_ready = True
    controller._service_enabled = True

    sync_calls = []
    monkeypatch.setattr(controller, "_sync_pipeline_runtime", lambda: sync_calls.append(True))

    controller._toggle_service()

    assert controller._service_enabled is False
    assert controller.state == ServiceState.IDLE
    assert sync_calls == [True]


def test_hotkey_press_and_release_enqueues_audio(monkeypatch) -> None:
    controller = _build_controller(monkeypatch)
    controller._permissions_ready = True
    controller._service_enabled = True

    monkeypatch.setattr(controller, "_frontmost_app_name", lambda: "ChatGPT")
    monkeypatch.setattr(controller, "_frontmost_app_pid", lambda: 12345)

    controller._on_hotkey_press()
    assert controller.state == ServiceState.RECORDING
    assert controller.audio_ducker.duck_calls == 1

    controller._on_hotkey_release()
    assert controller.state == ServiceState.TRANSCRIBING
    assert controller.audio_ducker.restore_calls == 1

    audio, app_name, app_pid = controller._queue.get_nowait()
    assert isinstance(audio, np.ndarray)
    assert app_name == "ChatGPT"
    assert app_pid == 12345


def test_paste_last_dictation_inserts_without_restoring_clipboard(monkeypatch) -> None:
    controller = _build_controller(monkeypatch)
    controller._permissions_ready = True
    controller._service_enabled = True
    controller._last_dictation_text = "latest text"
    controller.config.paste_last_shortcut_enabled = True
    monkeypatch.setattr(controller, "_frontmost_app_pid", lambda: 7788)

    controller.pasteLastDictation_(None)

    assert controller.inserter.calls[-1]["text"] == "latest text"
    assert controller.inserter.calls[-1]["restore_clipboard"] is False
    assert controller.inserter.calls[-1]["target_pid"] == 7788


def test_paste_last_dictation_without_buffer_sets_nonblocking_error(monkeypatch) -> None:
    controller = _build_controller(monkeypatch)
    controller._permissions_ready = True
    controller._service_enabled = True
    controller.config.paste_last_shortcut_enabled = True

    controller.pasteLastDictation_(None)

    assert "No recent dictation" in controller.last_error


def test_refresh_floating_indicator_tracks_recording_transcribing_done(monkeypatch) -> None:
    controller = _build_controller(monkeypatch)
    controller._service_enabled = True
    controller.config.floating_indicator_enabled = True
    controller.recorder.live_level = 0.55

    controller.state = ServiceState.RECORDING
    controller._refresh_floating_indicator()
    controller.state = ServiceState.TRANSCRIBING
    controller._refresh_floating_indicator()
    controller._show_done_on_next_idle = True
    controller.state = ServiceState.IDLE
    controller._refresh_floating_indicator()

    events = controller.floating_indicator.events
    assert events[0][0] == "recording"
    assert events[1][0] == "transcribing"
    assert events[-1][0] == "done"


def test_hotkey_release_with_empty_audio_returns_to_idle(monkeypatch) -> None:
    controller = _build_controller(monkeypatch)
    controller._permissions_ready = True
    controller._service_enabled = True

    controller.recorder.next_audio = np.array([], dtype=np.float32)
    controller._on_hotkey_press()
    controller._on_hotkey_release()

    assert controller.state == ServiceState.IDLE


def test_window_should_close_hides_window_by_default(monkeypatch) -> None:
    controller = _build_controller(monkeypatch)
    sender = FakeWindow()

    should_close = controller.windowShouldClose_(sender)

    assert should_close is False
    assert sender.hidden is True


def test_sync_pipeline_runtime_starts_and_stops_hotkey(monkeypatch) -> None:
    controller = _build_controller(monkeypatch)

    controller._permissions_ready = True
    controller._service_enabled = True
    controller._sync_pipeline_runtime()

    controller._service_enabled = False
    controller._sync_pipeline_runtime()

    assert controller.hotkey_listener.start_calls == 1
    assert controller.hotkey_listener.stop_calls == 1


def test_show_panel_updates_last_tab_and_persists(monkeypatch) -> None:
    controller = _build_controller(monkeypatch)
    saved = []
    controller.pages = {"home": object(), "history": object()}  # type: ignore[assignment]
    controller.sidebar_buttons = {}
    monkeypatch.setattr(controller, "_save_config", lambda: saved.append(controller.config.ui_last_tab))

    class FakePage:
        def __init__(self):
            self.hidden = None

        def setHidden_(self, value):
            self.hidden = value

    page_home = FakePage()
    page_history = FakePage()
    controller.pages = {"home": page_home, "history": page_history}

    controller._show_panel("history")

    assert controller.current_panel == "history"
    assert controller.config.ui_last_tab == "history"
    assert saved == ["history"]
    assert page_home.hidden is True
    assert page_history.hidden is False


def test_change_cleanup_provider_updates_config(monkeypatch) -> None:
    controller = _build_controller(monkeypatch)
    saved = []
    monkeypatch.setattr(controller, "_save_config", lambda: saved.append(controller.config.cleanup_provider))
    monkeypatch.setattr(controller, "_show_alert", lambda *_args, **_kwargs: None)

    class FakePopup:
        def __init__(self, idx):
            self._idx = idx

        def indexOfSelectedItem(self):
            return self._idx

    class FakeSettings:
        def __init__(self):
            self.cleanup_provider_popup = FakePopup(1)

    controller.settings_page = FakeSettings()  # type: ignore[assignment]
    controller.changeCleanupProvider_(None)

    assert controller.config.cleanup_provider == "deterministic"
    assert saved == ["deterministic"]


def test_set_groq_key_uses_secret_store(monkeypatch) -> None:
    controller = _build_controller(monkeypatch)
    alerts = []
    monkeypatch.setattr(controller, "_show_alert", lambda title, message: alerts.append((title, message)))
    monkeypatch.setattr(controller, "_prompt_secret_field", lambda *_args, **_kwargs: "gsk_test")

    controller.setGroqApiKey_(None)

    assert controller.secret_store.get_groq_api_key() == "gsk_test"
    assert controller._groq_key_present is True
    assert alerts and alerts[0][0] == "Groq Key Saved"


def test_refresh_permissions_shows_missing_list(monkeypatch) -> None:
    controller = _build_controller(monkeypatch)
    controller.permission_state = PermissionState(True, True, True, True)
    controller.permission_manager.check_all = lambda: PermissionState(False, True, False, True)  # type: ignore[attr-defined]

    alerts = []
    monkeypatch.setattr(controller, "_show_alert", lambda title, message: alerts.append((title, message)))

    controller.refreshPermissions_(None)

    assert alerts
    assert alerts[0][0] == "Permissions Still Missing"
    assert "Microphone" in alerts[0][1]
    assert "Input Monitoring" in alerts[0][1]


def test_refresh_permissions_success_message(monkeypatch) -> None:
    controller = _build_controller(monkeypatch)
    controller.permission_state = PermissionState(False, False, False, False)
    controller.permission_manager.check_all = lambda: PermissionState(True, True, True, True)  # type: ignore[attr-defined]

    alerts = []
    monkeypatch.setattr(controller, "_show_alert", lambda title, message: alerts.append((title, message)))

    controller.refreshPermissions_(None)

    assert alerts
    assert alerts[0][0] == "Permissions Updated"
