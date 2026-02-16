from __future__ import annotations

import logging
import queue
import subprocess
import threading
from datetime import datetime, timedelta
from enum import Enum
from pathlib import Path

import numpy as np
import objc
from AppKit import (
    NSAlert,
    NSApp,
    NSAppearance,
    NSApplication,
    NSApplicationActivateIgnoringOtherApps,
    NSBackingStoreBuffered,
    NSButton,
    NSColor,
    NSControlStateValueOff,
    NSControlStateValueOn,
    NSMenu,
    NSMenuItem,
    NSPasteboard,
    NSPasteboardTypeString,
    NSRunningApplication,
    NSSecureTextField,
    NSStatusBar,
    NSTextField,
    NSVariableStatusItemLength,
    NSView,
    NSWindow,
    NSWindowStyleMaskClosable,
    NSWindowStyleMaskMiniaturizable,
    NSWindowStyleMaskResizable,
    NSWindowStyleMaskTitled,
)
from Foundation import NSObject, NSTimer

from whisper_flow.audio import AudioRecorder
from whisper_flow.autostart import install_launch_agent, uninstall_launch_agent
from whisper_flow.cleanup import TextCleanup
from whisper_flow.config import ConfigStore
from whisper_flow.content_store import ContentStore, DictionaryEntry, NoteEntry, SnippetEntry, StyleProfile
from whisper_flow.history import HISTORY_DB_PATH, HistoryRecord, TranscriptHistoryStore
from whisper_flow.hotkey import HotkeyCallbacks, HotkeyListener
from whisper_flow.insert import TextInserter
from whisper_flow.permissions import PermissionManager, PermissionState
from whisper_flow.secret_store import SecretStore
from whisper_flow.stt import STTEngine
from whisper_flow.system_audio import SystemAudioDucker
from whisper_flow.time_utils import format_local_datetime, format_local_time_12h, local_date_key
from whisper_flow.ui import theme
from whisper_flow.ui.components import (
    activate,
    make_day_header,
    make_history_row,
    make_label,
    make_sidebar_button,
    make_sidebar_info_card,
    make_stack,
    pin_edges,
    set_button_title,
    set_sidebar_button_active,
    with_autolayout,
)
from whisper_flow.ui.pages import (
    CrudPageRefs,
    HistoryPageRefs,
    HomePageRefs,
    PermissionsPageRefs,
    SettingsPageRefs,
    build_crud_page,
    build_history_page,
    build_home_page,
    build_permission_wizard,
    build_permissions_page,
    build_settings_page,
)
from whisper_flow.ui.floating_indicator import FloatingIndicatorController

LOGGER = logging.getLogger(__name__)
LOG_FILE = Path.home() / "Library" / "Logs" / "SpeakFlow" / "whisper_flow.log"


class ServiceState(str, Enum):
    IDLE = "Idle"
    RECORDING = "Recording"
    TRANSCRIBING = "Transcribing"
    ERROR = "Error"


class HistoryTableDataSource(NSObject):
    def init(self):  # type: ignore[no-untyped-def]
        self = objc.super(HistoryTableDataSource, self).init()
        if self is None:
            return None
        self.records: list[HistoryRecord] = []
        return self

    def set_records(self, records: list[HistoryRecord]) -> None:
        self.records = records

    def numberOfRowsInTableView_(self, _table_view):  # type: ignore[no-untyped-def]
        return len(self.records)

    def tableView_objectValueForTableColumn_row_(self, _table_view, table_column, row):  # type: ignore[no-untyped-def]
        if row < 0 or row >= len(self.records):
            return ""

        record = self.records[row]
        identifier = str(table_column.identifier())
        if identifier == "time":
            return format_local_datetime(record.created_at)
        if identifier == "app":
            return record.source_app or "Unknown"
        return record.final_text


class GenericTableDataSource(NSObject):
    def init(self):  # type: ignore[no-untyped-def]
        self = objc.super(GenericTableDataSource, self).init()
        if self is None:
            return None
        self.rows: list[dict[str, str]] = []
        return self

    def set_rows(self, rows: list[dict[str, str]]) -> None:
        self.rows = rows

    def numberOfRowsInTableView_(self, _table_view):  # type: ignore[no-untyped-def]
        return len(self.rows)

    def tableView_objectValueForTableColumn_row_(self, _table_view, table_column, row):  # type: ignore[no-untyped-def]
        if row < 0 or row >= len(self.rows):
            return ""

        key = str(table_column.identifier())
        return self.rows[row].get(key, "")


class AppController(NSObject):
    def init(self):  # type: ignore[no-untyped-def]
        self = objc.super(AppController, self).init()
        if self is None:
            return None

        self.config_store = ConfigStore()
        self.config = self.config_store.load()

        self.state = ServiceState.IDLE
        self.last_error = ""

        self.recorder = AudioRecorder()
        self.audio_ducker = SystemAudioDucker(
            enabled=self.config.duck_system_audio_while_recording,
            target_volume_percent=self.config.duck_target_volume_percent,
        )
        self.stt_engine = STTEngine(self.config.stt_model)
        self.secret_store = SecretStore()
        self.cleanup = TextCleanup(self.config, secret_store=self.secret_store)
        self.inserter = TextInserter(
            keep_dictation_on_failure=self.config.paste_failure_keep_dictation_in_clipboard
        )
        self.history = TranscriptHistoryStore()
        self.content_store = ContentStore()
        self.permission_manager = PermissionManager(self.inserter)
        self.permission_state = PermissionState(False, False, False, False)

        self._service_enabled = True
        self._permissions_ready = False

        self._record_lock = threading.Lock()
        self._state_lock = threading.Lock()

        self._queue: queue.Queue[tuple[np.ndarray, str | None, int | None]] = queue.Queue(maxsize=5)
        self._worker_stop = threading.Event()
        self._worker = threading.Thread(target=self._worker_loop, name="transcription-worker", daemon=True)

        callbacks = HotkeyCallbacks(
            on_press=self._on_hotkey_press,
            on_release=self._on_hotkey_release,
            on_paste_last=self._on_paste_last_hotkey,
        )
        self.hotkey_listener = HotkeyListener(mode=self.config.hotkey_mode, callbacks=callbacks)
        self.floating_indicator = FloatingIndicatorController.alloc().initWithHideDelayMs_enabled_onMove_(
            self.config.floating_indicator_hide_delay_ms,
            self.config.floating_indicator_enabled,
            self._on_floating_indicator_moved,
        )
        self.floating_indicator.set_origin(
            self.config.floating_indicator_origin_x,
            self.config.floating_indicator_origin_y,
        )
        self._last_dictation_text = ""
        self._show_done_on_next_idle = False
        self._hide_indicator_on_next_tick = False
        self._last_indicator_state = ServiceState.IDLE
        self._last_indicator_error = ""

        self._history_rows: list[HistoryRecord] = []
        self._history_query = ""
        self._history_dirty = True

        self._dictionary_rows: list[DictionaryEntry] = []
        self._dictionary_query = ""
        self._dictionary_dirty = True

        self._snippet_rows: list[SnippetEntry] = []
        self._snippet_query = ""
        self._snippet_dirty = True

        self._style_rows: list[StyleProfile] = []
        self._style_query = ""
        self._style_dirty = True

        self._note_rows: list[NoteEntry] = []
        self._note_query = ""
        self._note_dirty = True

        self.window = None
        self.permission_window = None
        self.status_item = None

        self.sidebar_buttons: dict[str, NSButton] = {}
        self.pages: dict[str, NSView] = {}
        self.current_panel = "home"

        self.home_page: HomePageRefs | None = None
        self.history_page: HistoryPageRefs | None = None
        self.dictionary_page: CrudPageRefs | None = None
        self.snippet_page: CrudPageRefs | None = None
        self.style_page: CrudPageRefs | None = None
        self.note_page: CrudPageRefs | None = None
        self.settings_page: SettingsPageRefs | None = None
        self.permissions_page: PermissionsPageRefs | None = None
        self.permission_wizard: PermissionsPageRefs | None = None

        self.history_data_source = HistoryTableDataSource.alloc().init()
        self.dictionary_data_source = GenericTableDataSource.alloc().init()
        self.snippet_data_source = GenericTableDataSource.alloc().init()
        self.style_data_source = GenericTableDataSource.alloc().init()
        self.note_data_source = GenericTableDataSource.alloc().init()

        self.permission_labels_main: dict[str, NSTextField] = {}
        self.permission_labels_wizard: dict[str, NSTextField] = {}
        self.permission_continue_button = None

        self.menu_status_item = None
        self.menu_toggle_service_item = None
        self._sidebar_status_label = None

        self._ui_timer = None
        self._permission_check_counter = 0
        self._groq_key_present = self.secret_store.has_groq_api_key()
        return self

    # App lifecycle
    def applicationDidFinishLaunching_(self, _notification):  # type: ignore[no-untyped-def]
        self._build_app_menu()
        self._build_main_window()
        self._build_status_item()
        self._build_permission_window()

        self._worker.start()
        self._ui_timer = NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            0.25,
            self,
            "tick:",
            None,
            True,
        )

        self._run_initial_permission_flow()

        if self.config.login_window_behavior == "open":
            self.show_main_window()
        self._sync_pipeline_runtime()

    def applicationShouldHandleReopen_hasVisibleWindows_(self, _app, _flag):  # type: ignore[no-untyped-def]
        self.show_main_window()
        return True

    def applicationWillTerminate_(self, _notification):  # type: ignore[no-untyped-def]
        self._worker_stop.set()
        self.hotkey_listener.stop()
        self.floating_indicator.hide()
        self.audio_ducker.restore()
        with self._record_lock:
            if self.recorder.is_recording:
                self.recorder.stop()
        if self.status_item is not None:
            NSStatusBar.systemStatusBar().removeStatusItem_(self.status_item)
            self.status_item = None

    def windowShouldClose_(self, sender):  # type: ignore[no-untyped-def]
        if self.config.close_behavior == "hide_to_background":
            sender.orderOut_(None)
            return False
        return True

    def tick_(self, _timer):  # type: ignore[no-untyped-def]
        self._refresh_status_ui()
        self._refresh_floating_indicator()
        self._refresh_permission_labels()

        # Re-check permissions every ~5 seconds (20 ticks × 0.25s)
        self._permission_check_counter += 1
        if self._permission_check_counter >= 20:
            self._permission_check_counter = 0
            self._update_permissions_state()

        if self._history_dirty:
            self._reload_history()
        if self._dictionary_dirty:
            self._reload_dictionary()
        if self._snippet_dirty:
            self._reload_snippets()
        if self._style_dirty:
            self._reload_styles()
        if self._note_dirty:
            self._reload_notes()

    # Builders
    def _build_app_menu(self) -> None:
        main_menu = NSMenu.alloc().init()
        app_item = NSMenuItem.alloc().init()
        main_menu.addItem_(app_item)

        app_submenu = NSMenu.alloc().initWithTitle_("SpeakFlow")
        quit_item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_("Quit SpeakFlow", "terminate:", "q")
        app_submenu.addItem_(quit_item)
        app_item.setSubmenu_(app_submenu)

        NSApp().setMainMenu_(main_menu)

    def _build_status_item(self) -> None:
        self.status_item = NSStatusBar.systemStatusBar().statusItemWithLength_(NSVariableStatusItemLength)
        self.status_item.button().setTitle_("WF")

        menu = NSMenu.alloc().initWithTitle_("SpeakFlow")

        open_item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_("Open SpeakFlow", "openMainWindow:", "")
        open_item.setTarget_(self)
        menu.addItem_(open_item)

        self.menu_status_item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_("Status: Idle", None, "")
        menu.addItem_(self.menu_status_item)

        self.menu_toggle_service_item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
            "Stop Service", "toggleServiceFromMenu:", ""
        )
        self.menu_toggle_service_item.setTarget_(self)
        menu.addItem_(self.menu_toggle_service_item)

        permission_item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
            "Permission Setup", "openPermissionWizard:", ""
        )
        permission_item.setTarget_(self)
        menu.addItem_(permission_item)

        menu.addItem_(NSMenuItem.separatorItem())

        quit_item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_("Quit", "terminate:", "q")
        menu.addItem_(quit_item)

        self.status_item.setMenu_(menu)

    def _build_main_window(self) -> None:
        frame = ((120.0, 80.0), (1360.0, 840.0))
        mask = (
            NSWindowStyleMaskTitled
            | NSWindowStyleMaskClosable
            | NSWindowStyleMaskMiniaturizable
            | NSWindowStyleMaskResizable
        )
        self.window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            frame,
            mask,
            NSBackingStoreBuffered,
            False,
        )
        self.window.setTitle_("SpeakFlow")
        self.window.setAppearance_(NSAppearance.appearanceNamed_("NSAppearanceNameAqua"))
        self.window.setDelegate_(self)
        self.window.setMinSize_((1080.0, 700.0))

        content = self.window.contentView()
        content.setWantsLayer_(True)
        content.layer().setBackgroundColor_(theme.app_background_color().CGColor())

        root = with_autolayout(NSView.alloc().init())
        content.addSubview_(root)
        pin_edges(root, content)

        sidebar = with_autolayout(NSView.alloc().init())
        sidebar.setWantsLayer_(True)
        sidebar.layer().setBackgroundColor_(theme.sidebar_background_color().CGColor())

        page_host = with_autolayout(NSView.alloc().init())

        root.addSubview_(sidebar)
        root.addSubview_(page_host)

        activate(
            [
                sidebar.leadingAnchor().constraintEqualToAnchor_(root.leadingAnchor()),
                sidebar.topAnchor().constraintEqualToAnchor_(root.topAnchor()),
                sidebar.bottomAnchor().constraintEqualToAnchor_(root.bottomAnchor()),
                sidebar.widthAnchor().constraintEqualToConstant_(theme.SIDEBAR_WIDTH),
                page_host.leadingAnchor().constraintEqualToAnchor_(sidebar.trailingAnchor()),
                page_host.topAnchor().constraintEqualToAnchor_(root.topAnchor()),
                page_host.trailingAnchor().constraintEqualToAnchor_(root.trailingAnchor()),
                page_host.bottomAnchor().constraintEqualToAnchor_(root.bottomAnchor()),
            ]
        )

        self._build_sidebar(sidebar)
        self._build_pages(page_host)

    def _build_sidebar(self, sidebar: NSView) -> None:
        stack = make_stack(vertical=True, spacing=theme.SPACE.xs)
        sidebar.addSubview_(stack)
        pin_edges(stack, sidebar, inset=theme.SPACE.md)

        brand = make_label("SpeakFlow", font=theme.sidebar_brand_font())
        brand_row = make_stack(vertical=False, spacing=theme.SPACE.sm)
        brand_row.addArrangedSubview_(brand)
        stack.addArrangedSubview_(brand_row)

        # Small spacer after brand
        spacer_top = with_autolayout(NSView.alloc().init())
        activate([spacer_top.heightAnchor().constraintEqualToConstant_(theme.SPACE.sm)])
        stack.addArrangedSubview_(spacer_top)

        nav_specs = [
            ("home", "Home", "showHomePanel:", "house"),
            ("history", "History", "showHistoryPanel:", "clock"),
            ("dictionary", "Dictionary", "showDictionaryPanel:", "book"),
            ("snippets", "Snippets", "showSnippetsPanel:", "scissors"),
            ("style", "Style", "showStylePanel:", "textformat"),
            ("notes", "Notes", "showNotesPanel:", "note.text"),
            ("settings", "Settings", "showSettingsPanel:", "gear"),
            ("permissions", "Permissions", "showPermissionsPanel:", "lock.shield"),
        ]

        for key, title, selector, sf_symbol in nav_specs:
            button = make_sidebar_button(title, sf_symbol, self, selector)
            self.sidebar_buttons[key] = button
            stack.addArrangedSubview_(button)
            activate([button.leadingAnchor().constraintEqualToAnchor_(stack.leadingAnchor()),
                      button.trailingAnchor().constraintEqualToAnchor_(stack.trailingAnchor())])

        # Flexible spacer to push info card to bottom
        flex_spacer = with_autolayout(NSView.alloc().init())
        flex_spacer.setContentHuggingPriority_forOrientation_(1, 1)  # Low priority = stretches
        stack.addArrangedSubview_(flex_spacer)

        # Bottom info card
        info_card, self._sidebar_status_label = make_sidebar_info_card()
        stack.addArrangedSubview_(info_card)

    def _build_pages(self, page_host: NSView) -> None:
        self.home_page = build_home_page(self)
        self.history_page = build_history_page(self)

        self.dictionary_page = build_crud_page(
            self,
            title="Dictionary",
            subtitle="Phrase replacements for repeated wording.",
            search_action="dictionarySearchChanged:",
            add_action="addDictionary:",
            edit_action="editDictionary:",
            delete_action="deleteDictionary:",
            table_columns=[("trigger", "Trigger", 300.0), ("replacement", "Replacement", 700.0), ("updated", "Updated", 200.0)],
        )

        self.snippet_page = build_crud_page(
            self,
            title="Snippets",
            subtitle="Reusable content blocks with optional shortcuts.",
            search_action="snippetSearchChanged:",
            add_action="addSnippet:",
            edit_action="editSnippet:",
            delete_action="deleteSnippet:",
            table_columns=[("title", "Title", 300.0), ("shortcut", "Shortcut", 220.0), ("updated", "Updated", 200.0)],
        )

        self.style_page = build_crud_page(
            self,
            title="Style",
            subtitle="Output styles for post-processing and formatting.",
            search_action="styleSearchChanged:",
            add_action="addStyle:",
            edit_action="editStyle:",
            delete_action="deleteStyle:",
            table_columns=[("name", "Style", 280.0), ("default", "Default", 120.0), ("updated", "Updated", 220.0)],
            extra_action="setDefaultStyle:",
            extra_title="Set Default",
        )

        self.note_page = build_crud_page(
            self,
            title="Notes",
            subtitle="Quick local notes and references.",
            search_action="noteSearchChanged:",
            add_action="addNote:",
            edit_action="editNote:",
            delete_action="deleteNote:",
            table_columns=[("pinned", "Pinned", 120.0), ("title", "Title", 500.0), ("updated", "Updated", 220.0)],
            extra_action="toggleNotePin:",
            extra_title="Pin/Unpin",
        )

        self.settings_page = build_settings_page(self)
        self.permissions_page = build_permissions_page(self)

        self.pages = {
            "home": self.home_page.view,
            "history": self.history_page.view,
            "dictionary": self.dictionary_page.view,
            "snippets": self.snippet_page.view,
            "style": self.style_page.view,
            "notes": self.note_page.view,
            "settings": self.settings_page.view,
            "permissions": self.permissions_page.view,
        }

        for key, page in self.pages.items():
            page_host.addSubview_(page)
            pin_edges(page, page_host)
            page.setHidden_(True)

        # Data source wiring
        self.history_page.table.setDataSource_(self.history_data_source)
        self.history_page.table.setDelegate_(self)

        self.dictionary_page.table.setDataSource_(self.dictionary_data_source)
        self.snippet_page.table.setDataSource_(self.snippet_data_source)
        self.style_page.table.setDataSource_(self.style_data_source)
        self.note_page.table.setDataSource_(self.note_data_source)

        self.permission_labels_main = {
            key: refs.status_label for key, refs in self.permissions_page.rows.items()
        }

        initial = self.config.ui_last_tab if self.config.ui_last_tab in self.pages else "home"
        self._show_panel(initial, persist=False)

    def _build_permission_window(self) -> None:
        frame = ((300.0, 200.0), (760.0, 500.0))
        mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        self.permission_window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            frame,
            mask,
            NSBackingStoreBuffered,
            False,
        )
        self.permission_window.setTitle_("SpeakFlow Setup")
        self.permission_window.setAppearance_(NSAppearance.appearanceNamed_("NSAppearanceNameAqua"))

        self.permission_wizard = build_permission_wizard(self)
        content = self.permission_window.contentView()
        content.addSubview_(self.permission_wizard.view)
        pin_edges(self.permission_wizard.view, content)

        self.permission_labels_wizard = {
            key: refs.status_label for key, refs in self.permission_wizard.rows.items()
        }
        self.permission_continue_button = self.permission_wizard.continue_button

    # Permission flow
    def _run_initial_permission_flow(self) -> None:
        self.permission_manager.request_microphone()
        self.permission_manager.request_accessibility_prompt()
        self.permission_manager.request_automation_prompt()

        self._update_permissions_state()
        if not self.permission_state.input_monitoring:
            self.permission_manager.open_input_monitoring_settings()

        if not self.permission_state.all_granted:
            self.last_error = "Complete permission setup to enable dictation."
            self._service_enabled = True
            self._permissions_ready = False
            self.openPermissionWizard_(None)

    def _update_permissions_state(self) -> None:
        self.permission_state = self.permission_manager.check_all()
        self._permissions_ready = self.permission_state.all_granted
        self._refresh_permission_labels()
        self._sync_pipeline_runtime()

    def _refresh_permission_labels(self) -> None:
        mapping = {
            "microphone": self.permission_state.microphone,
            "accessibility": self.permission_state.accessibility,
            "input_monitoring": self.permission_state.input_monitoring,
            "automation": self.permission_state.automation,
        }

        for key, granted in mapping.items():
            text = "Granted" if granted else "Missing"
            color = theme.success_color() if granted else theme.danger_color()

            label_main = self.permission_labels_main.get(key)
            if label_main is not None:
                label_main.setStringValue_(text)
                label_main.setTextColor_(color)

            label_wizard = self.permission_labels_wizard.get(key)
            if label_wizard is not None:
                label_wizard.setStringValue_(text)
                label_wizard.setTextColor_(color)

            # Keep action text meaningful as permission state changes.
            self._update_permission_action_button_title(key, granted)

        if self.permission_continue_button is not None:
            self.permission_continue_button.setEnabled_(self.permission_state.all_granted)

    def _update_permission_action_button_title(self, key: str, granted: bool) -> None:
        title_when_missing = "Grant Access"
        title_when_granted = "Open Settings"
        if key == "input_monitoring":
            title_when_missing = "Grant Access"
            title_when_granted = "Open Settings"

        button_title = title_when_granted if granted else title_when_missing

        if self.permissions_page is not None and key in self.permissions_page.rows:
            set_button_title(self.permissions_page.rows[key].action_button, button_title)
        if self.permission_wizard is not None and key in self.permission_wizard.rows:
            set_button_title(self.permission_wizard.rows[key].action_button, button_title)

    # Panel switching
    def _show_panel(self, panel_name: str, persist: bool = True) -> None:
        self.current_panel = panel_name

        for key, page in self.pages.items():
            page.setHidden_(key != panel_name)

        for key, button in self.sidebar_buttons.items():
            set_sidebar_button_active(button, key == panel_name)

        if persist and self.config.ui_last_tab != panel_name:
            self.config.ui_last_tab = panel_name
            self._save_config()

        if panel_name == "history":
            self._history_dirty = True
        if panel_name == "dictionary":
            self._dictionary_dirty = True
        if panel_name == "snippets":
            self._snippet_dirty = True
        if panel_name == "style":
            self._style_dirty = True
        if panel_name == "notes":
            self._note_dirty = True
        if panel_name == "settings":
            self._groq_key_present = self.secret_store.has_groq_api_key()

    def _on_floating_indicator_moved(self, x: float, y: float) -> None:
        # Save persisted location so the indicator comes back where the user dragged it.
        if (
            self.config.floating_indicator_origin_x == x
            and self.config.floating_indicator_origin_y == y
        ):
            return
        self.config.floating_indicator_origin_x = x
        self.config.floating_indicator_origin_y = y
        self.config_store.save(self.config)

    def _refresh_floating_indicator(self) -> None:
        if not self.config.floating_indicator_enabled or not self._service_enabled:
            self.floating_indicator.hide()
            self._last_indicator_state = self.state
            return

        if self._hide_indicator_on_next_tick:
            self._hide_indicator_on_next_tick = False
            self.floating_indicator.hide()
            self._last_indicator_state = self.state
            return

        if self.state == ServiceState.RECORDING:
            level = self.recorder.get_live_level()
            if self._last_indicator_state != ServiceState.RECORDING:
                self.floating_indicator.show_recording(level)
            else:
                self.floating_indicator.update_meter(level)
            self._last_indicator_state = ServiceState.RECORDING
            return

        if self.state == ServiceState.TRANSCRIBING:
            if self._last_indicator_state != ServiceState.TRANSCRIBING:
                self.floating_indicator.show_transcribing()
            else:
                self.floating_indicator.update_meter(0.0)
            self._last_indicator_state = ServiceState.TRANSCRIBING
            return

        if self.state == ServiceState.ERROR:
            message = self.last_error or "Dictation failed"
            if (
                self._last_indicator_state != ServiceState.ERROR
                or self._last_indicator_error != message
            ):
                self.floating_indicator.show_error(message)
                self._last_indicator_error = message
            self._last_indicator_state = ServiceState.ERROR
            return

        if self._show_done_on_next_idle:
            self._show_done_on_next_idle = False
            self.floating_indicator.show_done("Done")

        self._last_indicator_error = ""
        self._last_indicator_state = ServiceState.IDLE

    # UI refresh
    def _refresh_status_ui(self) -> None:
        if self.state == ServiceState.RECORDING:
            status_text = "Recording"
            status_short = "REC"
        elif self.state == ServiceState.TRANSCRIBING:
            status_text = "Transcribing"
            status_short = "..."
        elif self.state == ServiceState.ERROR:
            status_text = "Error"
            status_short = "ERR"
        else:
            status_text = "Idle"
            status_short = "WF"

        if not self._permissions_ready:
            status_text = "Permission setup required"
            status_short = "PERM"

        if self.status_item is not None:
            self.status_item.button().setTitle_(status_short)

        if self.menu_status_item is not None:
            suffix = f" - {self.last_error}" if self.last_error else ""
            self.menu_status_item.setTitle_(f"Status: {status_text}{suffix}")

        toggle_title = "Stop Service" if self._service_enabled else "Start Service"
        if self.menu_toggle_service_item is not None:
            self.menu_toggle_service_item.setTitle_(toggle_title)

        if self.home_page is not None:
            self.home_page.status_label.setStringValue_(f"Status: {status_text}")
            self.home_page.error_label.setStringValue_(self.last_error)

        if self._sidebar_status_label is not None:
            bg_text = "Running in background" if self._service_enabled else "Service stopped"
            self._sidebar_status_label.setStringValue_(bg_text)

        if self.settings_page is not None:
            set_button_title(self.settings_page.service_button, toggle_title)
            self.settings_page.lmstudio_switch.setState_(
                NSControlStateValueOn if self.config.lmstudio_enabled else NSControlStateValueOff
            )
            provider_index = {"lmstudio": 0, "groq": 1, "deterministic": 2}.get(self.config.cleanup_provider, 0)
            self.settings_page.cleanup_provider_popup.selectItemAtIndex_(provider_index)
            key_status = "Configured" if self._groq_key_present else "Missing"
            self.settings_page.groq_key_status_label.setStringValue_(f"Groq key: {key_status}")
            self.settings_page.groq_key_status_label.setTextColor_(
                theme.success_color() if self._groq_key_present else theme.secondary_text_color()
            )

            language_index = {"auto": 0, "english": 1, "hinglish_roman": 2}.get(self.config.language_mode, 0)
            hotkey_index = {"fn_hold": 0, "fn_space_hold": 1}.get(self.config.hotkey_mode, 0)
            self.settings_page.language_popup.selectItemAtIndex_(language_index)
            self.settings_page.hotkey_popup.selectItemAtIndex_(hotkey_index)

            density_index = {"comfortable": 0, "compact": 1}.get(self.config.ui_density, 0)
            self.settings_page.density_popup.selectItemAtIndex_(density_index)
            self.settings_page.welcome_switch.setState_(
                NSControlStateValueOn if self.config.ui_show_welcome_card else NSControlStateValueOff
            )
            self.settings_page.floating_indicator_switch.setState_(
                NSControlStateValueOn if self.config.floating_indicator_enabled else NSControlStateValueOff
            )
            self.settings_page.paste_last_shortcut_switch.setState_(
                NSControlStateValueOn if self.config.paste_last_shortcut_enabled else NSControlStateValueOff
            )
            self.settings_page.paste_fallback_switch.setState_(
                NSControlStateValueOn
                if self.config.paste_failure_keep_dictation_in_clipboard
                else NSControlStateValueOff
            )

    def _reload_history(self) -> None:
        self._history_rows = self.history.search(self._history_query, limit=250, offset=0)
        self.history_data_source.set_records(self._history_rows)
        if self.history_page is not None:
            self.history_page.table.reloadData()

            stats = self.history.stats()
            self.history_page.stats_label.setStringValue_(
                f"Total: {stats['total_count']} | Latest App: {stats['latest_source_app']} | Top App: {stats['top_source_app']}"
            )

        if self.home_page is not None:
            self._populate_home_transcripts()

        self._history_dirty = False

    def _populate_home_transcripts(self) -> None:
        if self.home_page is None or self.home_page.transcript_stack is None:
            return

        stack = self.home_page.transcript_stack
        # Remove all existing subviews
        for view in list(stack.arrangedSubviews()):
            stack.removeArrangedSubview_(view)
            view.removeFromSuperview()

        recent = self._history_rows[:15]
        if not recent:
            no_data = make_label("No dictation yet.", color=theme.secondary_text_color())
            stack.addArrangedSubview_(no_data)
            return

        today_str = datetime.now().strftime("%Y-%m-%d")
        yesterday_str = (datetime.now() - timedelta(days=1)).strftime("%Y-%m-%d")

        current_group = None
        for record in recent:
            date_part = local_date_key(record.created_at)
            if date_part == today_str:
                group = "TODAY"
            elif date_part == yesterday_str:
                group = "YESTERDAY"
            else:
                group = date_part

            if group != current_group:
                current_group = group
                stack.addArrangedSubview_(make_day_header(group))

            time_display = format_local_time_12h(record.created_at)

            text_preview = record.final_text[:120]
            stack.addArrangedSubview_(make_history_row(time_display, text_preview))

        # Update stats
        stats = self.history.stats()
        if self.home_page.stats_words is not None:
            self.home_page.stats_words.setStringValue_(f"{stats['total_count']:,} words")

    def _reload_dictionary(self) -> None:
        self._dictionary_rows = self.content_store.list_dictionary(self._dictionary_query, limit=300, offset=0)
        rows = [
            {
                "trigger": entry.trigger,
                "replacement": entry.replacement,
                "updated": format_local_datetime(entry.updated_at),
            }
            for entry in self._dictionary_rows
        ]
        self.dictionary_data_source.set_rows(rows)
        if self.dictionary_page is not None:
            self.dictionary_page.table.reloadData()
            self.dictionary_page.stats_label.setStringValue_(f"{len(self._dictionary_rows)} items")
        self._dictionary_dirty = False

    def _reload_snippets(self) -> None:
        self._snippet_rows = self.content_store.list_snippets(self._snippet_query, limit=300, offset=0)
        rows = [
            {
                "title": entry.title,
                "shortcut": entry.shortcut,
                "updated": format_local_datetime(entry.updated_at),
            }
            for entry in self._snippet_rows
        ]
        self.snippet_data_source.set_rows(rows)
        if self.snippet_page is not None:
            self.snippet_page.table.reloadData()
            self.snippet_page.stats_label.setStringValue_(f"{len(self._snippet_rows)} items")
        self._snippet_dirty = False

    def _reload_styles(self) -> None:
        self._style_rows = self.content_store.list_styles(self._style_query, limit=300, offset=0)
        rows = [
            {
                "name": entry.name,
                "default": "Yes" if entry.is_default else "",
                "updated": format_local_datetime(entry.updated_at),
            }
            for entry in self._style_rows
        ]
        self.style_data_source.set_rows(rows)
        if self.style_page is not None:
            self.style_page.table.reloadData()
            self.style_page.stats_label.setStringValue_(f"{len(self._style_rows)} items")
        self._style_dirty = False

    def _reload_notes(self) -> None:
        self._note_rows = self.content_store.list_notes(self._note_query, limit=300, offset=0)
        rows = [
            {
                "pinned": "Yes" if entry.pinned else "",
                "title": entry.title,
                "updated": format_local_datetime(entry.updated_at),
            }
            for entry in self._note_rows
        ]
        self.note_data_source.set_rows(rows)
        if self.note_page is not None:
            self.note_page.table.reloadData()
            self.note_page.stats_label.setStringValue_(f"{len(self._note_rows)} items")
        self._note_dirty = False

    def _save_config(self) -> None:
        self.config_store.save(self.config)
        self.audio_ducker = SystemAudioDucker(
            enabled=self.config.duck_system_audio_while_recording,
            target_volume_percent=self.config.duck_target_volume_percent,
        )
        self.inserter.keep_dictation_on_failure = self.config.paste_failure_keep_dictation_in_clipboard
        self.cleanup.update_config(self.config)
        self.floating_indicator.set_enabled(self.config.floating_indicator_enabled)
        self.floating_indicator.set_hide_delay_ms(self.config.floating_indicator_hide_delay_ms)
        self.floating_indicator.set_origin(
            self.config.floating_indicator_origin_x,
            self.config.floating_indicator_origin_y,
        )

    def _sync_pipeline_runtime(self) -> None:
        should_run_hotkey = self._service_enabled and self._permissions_ready
        if should_run_hotkey:
            self.hotkey_listener.start()
            return

        self.hotkey_listener.stop()
        self.floating_indicator.hide()

    def _frontmost_app_name(self) -> str | None:
        try:
            from AppKit import NSWorkspace

            app = NSWorkspace.sharedWorkspace().frontmostApplication()
            if app is None:
                return None
            return str(app.localizedName()) if app.localizedName() else None
        except Exception:
            return None

    def _frontmost_app_pid(self) -> int | None:
        try:
            from AppKit import NSWorkspace

            app = NSWorkspace.sharedWorkspace().frontmostApplication()
            if app is None:
                return None
            pid = int(app.processIdentifier())
            return pid if pid > 0 else None
        except Exception:
            return None

    def _set_error(self, exc: Exception) -> None:
        with self._state_lock:
            self.state = ServiceState.ERROR
            self.last_error = str(exc)
            self._show_done_on_next_idle = False

    # Worker
    def _worker_loop(self) -> None:
        while not self._worker_stop.is_set():
            try:
                audio, source_app, source_pid = self._queue.get(timeout=0.25)
            except queue.Empty:
                continue

            try:
                transcript = self.stt_engine.transcribe(audio)
                cleanup_result = self.cleanup.clean(transcript)
                final_text = cleanup_result.text
                inserted = False
                if final_text:
                    with self._state_lock:
                        self._last_dictation_text = final_text
                    self.inserter.insert_text(
                        final_text,
                        restore_clipboard=True,
                        target_pid=source_pid,
                        keep_dictation_on_failure=self.config.paste_failure_keep_dictation_in_clipboard,
                    )
                    inserted = True
                    self.history.add(
                        raw_text=transcript.raw_text,
                        final_text=final_text,
                        detected_language=transcript.detected_language,
                        confidence=transcript.confidence,
                        output_mode=cleanup_result.output_mode,
                        source_app=source_app,
                    )
                    with self._state_lock:
                        self._history_dirty = True
                with self._state_lock:
                    self.last_error = ""
                    self.state = ServiceState.IDLE
                    self._show_done_on_next_idle = inserted
                    self._hide_indicator_on_next_tick = not inserted
            except Exception as exc:
                LOGGER.exception("Transcription pipeline failed")
                self._set_error(exc)
                with self._state_lock:
                    self._show_done_on_next_idle = False
            finally:
                self._queue.task_done()

    # Hotkey callbacks
    def _on_hotkey_press(self) -> None:
        if not self._service_enabled or not self._permissions_ready:
            return

        with self._record_lock:
            if self.recorder.is_recording:
                return
            try:
                with self._state_lock:
                    self.last_error = ""
                    self._last_indicator_error = ""
                    self._hide_indicator_on_next_tick = False
                self.recorder.reset_live_level()
                self.audio_ducker.duck()
                self.recorder.start()
                with self._state_lock:
                    self.state = ServiceState.RECORDING
            except Exception as exc:
                self.audio_ducker.restore()
                LOGGER.exception("Unable to start recording")
                self._set_error(exc)

    def _on_hotkey_release(self) -> None:
        if not self._service_enabled or not self._permissions_ready:
            return

        with self._record_lock:
            if not self.recorder.is_recording:
                return
            try:
                audio = self.recorder.stop()
            except Exception as exc:
                self.audio_ducker.restore()
                LOGGER.exception("Unable to stop recording")
                self._set_error(exc)
                return
            finally:
                self.audio_ducker.restore()

        if audio.size == 0:
            with self._state_lock:
                self.state = ServiceState.IDLE
                self._show_done_on_next_idle = False
                self._hide_indicator_on_next_tick = True
            return

        source_app = self._frontmost_app_name()
        source_pid = self._frontmost_app_pid()
        self._queue.put((audio, source_app, source_pid))
        with self._state_lock:
            self.state = ServiceState.TRANSCRIBING
            self._show_done_on_next_idle = False

    def _on_paste_last_hotkey(self) -> None:
        self.pasteLastDictation_(None)

    def pasteLastDictation_(self, _sender):  # type: ignore[no-untyped-def]
        if not self._service_enabled or not self._permissions_ready:
            return
        if not self.config.paste_last_shortcut_enabled:
            return

        text = self._last_dictation_text.strip()
        if not text:
            with self._state_lock:
                self.last_error = "No recent dictation available to paste."
            return

        try:
            self.inserter.insert_text(
                text,
                restore_clipboard=False,
                target_pid=self._frontmost_app_pid(),
                keep_dictation_on_failure=True,
            )
            with self._state_lock:
                self.last_error = ""
        except Exception as exc:
            self._set_error(exc)

    # Menu/status actions
    def openMainWindow_(self, _sender):  # type: ignore[no-untyped-def]
        self.show_main_window()

    def toggleServiceFromMenu_(self, _sender):  # type: ignore[no-untyped-def]
        self._toggle_service()

    def toggleServiceFromHome_(self, _sender):  # type: ignore[no-untyped-def]
        self._toggle_service()

    def toggleServiceFromSettings_(self, _sender):  # type: ignore[no-untyped-def]
        self._toggle_service()

    def toggleLmStudioFromSettings_(self, _sender):  # type: ignore[no-untyped-def]
        if self.settings_page is None:
            return
        self.config.lmstudio_enabled = bool(self.settings_page.lmstudio_switch.state() == NSControlStateValueOn)
        self._save_config()

    def changeCleanupProvider_(self, _sender):  # type: ignore[no-untyped-def]
        if self.settings_page is None:
            return
        index = int(self.settings_page.cleanup_provider_popup.indexOfSelectedItem())
        mapping = {0: "lmstudio", 1: "groq", 2: "deterministic"}
        self.config.cleanup_provider = mapping.get(index, "lmstudio")
        if self.config.cleanup_provider == "groq":
            self._groq_key_present = self.secret_store.has_groq_api_key()
            if not self._groq_key_present:
                self._show_alert(
                    "Groq Key Missing",
                    "Set your Groq API key in Settings. Cleanup will fall back to deterministic mode until key is configured.",
                )
        self._save_config()

    def setGroqApiKey_(self, _sender):  # type: ignore[no-untyped-def]
        value = self._prompt_secret_field(
            "Set Groq API Key",
            "Paste your Groq API key. It will be stored in macOS Keychain.",
        )
        if value is None:
            return
        try:
            self.secret_store.set_groq_api_key(value)
            self._groq_key_present = True
            self._show_alert("Groq Key Saved", "Groq API key saved in Keychain.")
        except Exception as exc:
            self._show_alert("Groq Key Save Failed", str(exc))

    def clearGroqApiKey_(self, _sender):  # type: ignore[no-untyped-def]
        try:
            self.secret_store.delete_groq_api_key()
            self._groq_key_present = False
            self._show_alert("Groq Key Removed", "Groq API key removed from Keychain.")
        except Exception as exc:
            self._show_alert("Groq Key Removal Failed", str(exc))

    def _toggle_service(self) -> None:
        if not self._permissions_ready:
            self.openPermissionWizard_(None)
            self._show_alert("Permissions Required", "Complete permission setup before starting dictation service.")
            return

        self._service_enabled = not self._service_enabled
        self.state = ServiceState.IDLE
        self._show_done_on_next_idle = False
        self._hide_indicator_on_next_tick = True
        self._sync_pipeline_runtime()

    def toggleLmStudioFromHome_(self, _sender):  # type: ignore[no-untyped-def]
        # Legacy — now handled by toggleLmStudioFromSettings_
        if self.settings_page is None:
            return
        self.config.lmstudio_enabled = bool(self.settings_page.lmstudio_switch.state() == NSControlStateValueOn)
        self._save_config()

    def changeLanguageMode_(self, _sender):  # type: ignore[no-untyped-def]
        if self.settings_page is None:
            return
        index = int(self.settings_page.language_popup.indexOfSelectedItem())
        mapping = {0: "auto", 1: "english", 2: "hinglish_roman"}
        self.config.language_mode = mapping.get(index, "auto")
        self._save_config()

    def changeHotkeyMode_(self, _sender):  # type: ignore[no-untyped-def]
        if self.settings_page is None:
            return
        index = int(self.settings_page.hotkey_popup.indexOfSelectedItem())
        mapping = {0: "fn_hold", 1: "fn_space_hold"}
        self.config.hotkey_mode = mapping.get(index, "fn_hold")
        self._save_config()
        self.hotkey_listener.reconfigure(self.config.hotkey_mode)
        self._sync_pipeline_runtime()

    def show_main_window(self) -> None:
        if self.window is None:
            return
        self.window.makeKeyAndOrderFront_(None)
        NSRunningApplication.currentApplication().activateWithOptions_(NSApplicationActivateIgnoringOtherApps)

    # Sidebar actions
    def showHomePanel_(self, _sender):  # type: ignore[no-untyped-def]
        self._show_panel("home")

    def showHistoryPanel_(self, _sender):  # type: ignore[no-untyped-def]
        self._show_panel("history")

    def showDictionaryPanel_(self, _sender):  # type: ignore[no-untyped-def]
        self._show_panel("dictionary")

    def showSnippetsPanel_(self, _sender):  # type: ignore[no-untyped-def]
        self._show_panel("snippets")

    def showStylePanel_(self, _sender):  # type: ignore[no-untyped-def]
        self._show_panel("style")

    def showNotesPanel_(self, _sender):  # type: ignore[no-untyped-def]
        self._show_panel("notes")

    def showSettingsPanel_(self, _sender):  # type: ignore[no-untyped-def]
        self._show_panel("settings")

    def showPermissionsPanel_(self, _sender):  # type: ignore[no-untyped-def]
        self._show_panel("permissions")

    # History actions
    def historySearchChanged_(self, _sender):  # type: ignore[no-untyped-def]
        if self.history_page is None:
            return
        self._history_query = str(self.history_page.search_field.stringValue())
        self._history_dirty = True

    def refreshHistory_(self, _sender):  # type: ignore[no-untyped-def]
        self._history_dirty = True

    def copySelectedHistory_(self, _sender):  # type: ignore[no-untyped-def]
        if self.history_page is None:
            return
        row = int(self.history_page.table.selectedRow())
        if row < 0 or row >= len(self._history_rows):
            return

        record = self._history_rows[row]
        board = NSPasteboard.generalPasteboard()
        board.clearContents()
        board.setString_forType_(record.final_text, NSPasteboardTypeString)

    def deleteSelectedHistory_(self, _sender):  # type: ignore[no-untyped-def]
        if self.history_page is None:
            return
        row = int(self.history_page.table.selectedRow())
        if row < 0 or row >= len(self._history_rows):
            return

        record = self._history_rows[row]
        try:
            self.history.delete(record.id)
            self._history_dirty = True
        except Exception as exc:
            self._show_alert("Delete Failed", str(exc))

    # CRUD helper prompts
    def _prompt_two_fields(self, title: str, first_label: str, second_label: str, first: str = "", second: str = "") -> tuple[str, str] | None:
        alert = NSAlert.alloc().init()
        alert.setMessageText_(title)
        alert.addButtonWithTitle_("Save")
        alert.addButtonWithTitle_("Cancel")

        container = NSView.alloc().initWithFrame_(((0.0, 0.0), (420.0, 88.0)))

        first_title = NSTextField.labelWithString_(first_label)
        first_title.setFrame_(((0.0, 62.0), (120.0, 20.0)))
        container.addSubview_(first_title)

        first_field = NSTextField.alloc().initWithFrame_(((124.0, 58.0), (290.0, 24.0)))
        first_field.setStringValue_(first)
        container.addSubview_(first_field)

        second_title = NSTextField.labelWithString_(second_label)
        second_title.setFrame_(((0.0, 30.0), (120.0, 20.0)))
        container.addSubview_(second_title)

        second_field = NSTextField.alloc().initWithFrame_(((124.0, 26.0), (290.0, 24.0)))
        second_field.setStringValue_(second)
        container.addSubview_(second_field)

        alert.setAccessoryView_(container)
        result = alert.runModal()
        if int(result) != 1000:
            return None

        return str(first_field.stringValue()).strip(), str(second_field.stringValue()).strip()

    def _prompt_secret_field(self, title: str, message: str) -> str | None:
        alert = NSAlert.alloc().init()
        alert.setMessageText_(title)
        alert.setInformativeText_(message)
        alert.addButtonWithTitle_("Save")
        alert.addButtonWithTitle_("Cancel")

        field = NSSecureTextField.alloc().initWithFrame_(((0.0, 0.0), (420.0, 24.0)))
        alert.setAccessoryView_(field)
        result = alert.runModal()
        if int(result) != 1000:
            return None

        value = str(field.stringValue()).strip()
        return value or None

    # Dictionary actions
    def dictionarySearchChanged_(self, _sender):  # type: ignore[no-untyped-def]
        if self.dictionary_page is None:
            return
        self._dictionary_query = str(self.dictionary_page.search_field.stringValue())
        self._dictionary_dirty = True

    def addDictionary_(self, _sender):  # type: ignore[no-untyped-def]
        values = self._prompt_two_fields("Add Dictionary Entry", "Trigger", "Replacement")
        if not values:
            return
        trigger, replacement = values
        if not trigger or not replacement:
            self._show_alert("Invalid Entry", "Trigger and replacement are required.")
            return
        try:
            self.content_store.upsert_dictionary(DictionaryEntry(trigger=trigger, replacement=replacement))
            self._dictionary_dirty = True
        except Exception as exc:
            self._show_alert("Save Failed", str(exc))

    def editDictionary_(self, _sender):  # type: ignore[no-untyped-def]
        if self.dictionary_page is None:
            return
        row = int(self.dictionary_page.table.selectedRow())
        if row < 0 or row >= len(self._dictionary_rows):
            return
        entry = self._dictionary_rows[row]
        values = self._prompt_two_fields(
            "Edit Dictionary Entry",
            "Trigger",
            "Replacement",
            first=entry.trigger,
            second=entry.replacement,
        )
        if not values:
            return
        trigger, replacement = values
        if not trigger or not replacement:
            self._show_alert("Invalid Entry", "Trigger and replacement are required.")
            return
        try:
            self.content_store.upsert_dictionary(
                DictionaryEntry(id=entry.id, trigger=trigger, replacement=replacement)
            )
            self._dictionary_dirty = True
        except Exception as exc:
            self._show_alert("Save Failed", str(exc))

    def deleteDictionary_(self, _sender):  # type: ignore[no-untyped-def]
        if self.dictionary_page is None:
            return
        row = int(self.dictionary_page.table.selectedRow())
        if row < 0 or row >= len(self._dictionary_rows):
            return
        try:
            self.content_store.delete_dictionary(int(self._dictionary_rows[row].id))
            self._dictionary_dirty = True
        except Exception as exc:
            self._show_alert("Delete Failed", str(exc))

    # Snippet actions
    def snippetSearchChanged_(self, _sender):  # type: ignore[no-untyped-def]
        if self.snippet_page is None:
            return
        self._snippet_query = str(self.snippet_page.search_field.stringValue())
        self._snippet_dirty = True

    def addSnippet_(self, _sender):  # type: ignore[no-untyped-def]
        values = self._prompt_two_fields("Add Snippet", "Title", "Body")
        if not values:
            return
        title, body = values
        if not title:
            self._show_alert("Invalid Entry", "Title is required.")
            return
        try:
            self.content_store.upsert_snippet(SnippetEntry(title=title, body=body, shortcut=""))
            self._snippet_dirty = True
        except Exception as exc:
            self._show_alert("Save Failed", str(exc))

    def editSnippet_(self, _sender):  # type: ignore[no-untyped-def]
        if self.snippet_page is None:
            return
        row = int(self.snippet_page.table.selectedRow())
        if row < 0 or row >= len(self._snippet_rows):
            return
        entry = self._snippet_rows[row]
        values = self._prompt_two_fields("Edit Snippet", "Title", "Body", first=entry.title, second=entry.body)
        if not values:
            return
        title, body = values
        if not title:
            self._show_alert("Invalid Entry", "Title is required.")
            return
        try:
            self.content_store.upsert_snippet(
                SnippetEntry(id=entry.id, title=title, body=body, shortcut=entry.shortcut)
            )
            self._snippet_dirty = True
        except Exception as exc:
            self._show_alert("Save Failed", str(exc))

    def deleteSnippet_(self, _sender):  # type: ignore[no-untyped-def]
        if self.snippet_page is None:
            return
        row = int(self.snippet_page.table.selectedRow())
        if row < 0 or row >= len(self._snippet_rows):
            return
        try:
            self.content_store.delete_snippet(int(self._snippet_rows[row].id))
            self._snippet_dirty = True
        except Exception as exc:
            self._show_alert("Delete Failed", str(exc))

    # Style actions
    def styleSearchChanged_(self, _sender):  # type: ignore[no-untyped-def]
        if self.style_page is None:
            return
        self._style_query = str(self.style_page.search_field.stringValue())
        self._style_dirty = True

    def addStyle_(self, _sender):  # type: ignore[no-untyped-def]
        values = self._prompt_two_fields("Add Style", "Name", "Instructions")
        if not values:
            return
        name, instructions = values
        if not name:
            self._show_alert("Invalid Entry", "Name is required.")
            return
        try:
            self.content_store.upsert_style(StyleProfile(name=name, instructions=instructions, is_default=False))
            self._style_dirty = True
        except Exception as exc:
            self._show_alert("Save Failed", str(exc))

    def editStyle_(self, _sender):  # type: ignore[no-untyped-def]
        if self.style_page is None:
            return
        row = int(self.style_page.table.selectedRow())
        if row < 0 or row >= len(self._style_rows):
            return
        entry = self._style_rows[row]
        values = self._prompt_two_fields(
            "Edit Style",
            "Name",
            "Instructions",
            first=entry.name,
            second=entry.instructions,
        )
        if not values:
            return
        name, instructions = values
        if not name:
            self._show_alert("Invalid Entry", "Name is required.")
            return
        try:
            self.content_store.upsert_style(
                StyleProfile(id=entry.id, name=name, instructions=instructions, is_default=entry.is_default)
            )
            self._style_dirty = True
        except Exception as exc:
            self._show_alert("Save Failed", str(exc))

    def deleteStyle_(self, _sender):  # type: ignore[no-untyped-def]
        if self.style_page is None:
            return
        row = int(self.style_page.table.selectedRow())
        if row < 0 or row >= len(self._style_rows):
            return
        try:
            self.content_store.delete_style(int(self._style_rows[row].id))
            self._style_dirty = True
        except Exception as exc:
            self._show_alert("Delete Failed", str(exc))

    def setDefaultStyle_(self, _sender):  # type: ignore[no-untyped-def]
        if self.style_page is None:
            return
        row = int(self.style_page.table.selectedRow())
        if row < 0 or row >= len(self._style_rows):
            return
        try:
            self.content_store.set_default_style(int(self._style_rows[row].id))
            self._style_dirty = True
        except Exception as exc:
            self._show_alert("Save Failed", str(exc))

    # Note actions
    def noteSearchChanged_(self, _sender):  # type: ignore[no-untyped-def]
        if self.note_page is None:
            return
        self._note_query = str(self.note_page.search_field.stringValue())
        self._note_dirty = True

    def addNote_(self, _sender):  # type: ignore[no-untyped-def]
        values = self._prompt_two_fields("Add Note", "Title", "Body")
        if not values:
            return
        title, body = values
        if not title:
            self._show_alert("Invalid Entry", "Title is required.")
            return
        try:
            self.content_store.upsert_note(NoteEntry(title=title, body=body, pinned=False))
            self._note_dirty = True
        except Exception as exc:
            self._show_alert("Save Failed", str(exc))

    def editNote_(self, _sender):  # type: ignore[no-untyped-def]
        if self.note_page is None:
            return
        row = int(self.note_page.table.selectedRow())
        if row < 0 or row >= len(self._note_rows):
            return
        entry = self._note_rows[row]
        values = self._prompt_two_fields("Edit Note", "Title", "Body", first=entry.title, second=entry.body)
        if not values:
            return
        title, body = values
        if not title:
            self._show_alert("Invalid Entry", "Title is required.")
            return
        try:
            self.content_store.upsert_note(
                NoteEntry(id=entry.id, title=title, body=body, pinned=entry.pinned)
            )
            self._note_dirty = True
        except Exception as exc:
            self._show_alert("Save Failed", str(exc))

    def deleteNote_(self, _sender):  # type: ignore[no-untyped-def]
        if self.note_page is None:
            return
        row = int(self.note_page.table.selectedRow())
        if row < 0 or row >= len(self._note_rows):
            return
        try:
            self.content_store.delete_note(int(self._note_rows[row].id))
            self._note_dirty = True
        except Exception as exc:
            self._show_alert("Delete Failed", str(exc))

    def toggleNotePin_(self, _sender):  # type: ignore[no-untyped-def]
        if self.note_page is None:
            return
        row = int(self.note_page.table.selectedRow())
        if row < 0 or row >= len(self._note_rows):
            return
        entry = self._note_rows[row]
        try:
            self.content_store.upsert_note(
                NoteEntry(
                    id=entry.id,
                    title=entry.title,
                    body=entry.body,
                    pinned=not entry.pinned,
                )
            )
            self._note_dirty = True
        except Exception as exc:
            self._show_alert("Save Failed", str(exc))

    # Settings actions
    def openConfig_(self, _sender):  # type: ignore[no-untyped-def]
        subprocess.run(["open", str(self.config_store.path)], check=False)

    def openLogs_(self, _sender):  # type: ignore[no-untyped-def]
        subprocess.run(["open", str(LOG_FILE.parent)], check=False)

    def openHistoryFolder_(self, _sender):  # type: ignore[no-untyped-def]
        subprocess.run(["open", str(HISTORY_DB_PATH.parent)], check=False)

    def installAutostart_(self, _sender):  # type: ignore[no-untyped-def]
        try:
            mode = install_launch_agent()
            self.config.autostart_enabled = True
            self._save_config()
            self._show_alert("Auto-start Enabled", f"Launch agent installed ({mode} mode).")
        except Exception as exc:
            self._show_alert("Auto-start Failed", str(exc))

    def uninstallAutostart_(self, _sender):  # type: ignore[no-untyped-def]
        try:
            uninstall_launch_agent()
            self.config.autostart_enabled = False
            self._save_config()
            self._show_alert("Auto-start Disabled", "Launch agent removed.")
        except Exception as exc:
            self._show_alert("Auto-start Failed", str(exc))

    def changeUiDensity_(self, _sender):  # type: ignore[no-untyped-def]
        if self.settings_page is None:
            return
        index = int(self.settings_page.density_popup.indexOfSelectedItem())
        self.config.ui_density = "comfortable" if index == 0 else "compact"
        self._save_config()

    def toggleWelcomeCard_(self, _sender):  # type: ignore[no-untyped-def]
        if self.settings_page is None:
            return
        self.config.ui_show_welcome_card = bool(self.settings_page.welcome_switch.state() == NSControlStateValueOn)
        self._save_config()

    def toggleFloatingIndicatorFromSettings_(self, _sender):  # type: ignore[no-untyped-def]
        if self.settings_page is None:
            return
        self.config.floating_indicator_enabled = bool(
            self.settings_page.floating_indicator_switch.state() == NSControlStateValueOn
        )
        self._save_config()

    def togglePasteLastShortcutFromSettings_(self, _sender):  # type: ignore[no-untyped-def]
        if self.settings_page is None:
            return
        self.config.paste_last_shortcut_enabled = bool(
            self.settings_page.paste_last_shortcut_switch.state() == NSControlStateValueOn
        )
        self._save_config()

    def togglePasteFallbackFromSettings_(self, _sender):  # type: ignore[no-untyped-def]
        if self.settings_page is None:
            return
        self.config.paste_failure_keep_dictation_in_clipboard = bool(
            self.settings_page.paste_fallback_switch.state() == NSControlStateValueOn
        )
        self._save_config()

    def resetFloatingIndicatorPosition_(self, _sender):  # type: ignore[no-untyped-def]
        self.config.floating_indicator_origin_x = None
        self.config.floating_indicator_origin_y = None
        self._save_config()

    # Permission actions
    def openPermissionWizard_(self, _sender):  # type: ignore[no-untyped-def]
        if self.permission_window is None:
            return
        self.permission_window.makeKeyAndOrderFront_(None)
        NSRunningApplication.currentApplication().activateWithOptions_(NSApplicationActivateIgnoringOtherApps)

    def continueAfterPermissionSetup_(self, _sender):  # type: ignore[no-untyped-def]
        self._update_permissions_state()
        if not self.permission_state.all_granted:
            self._show_alert("Permissions Missing", "All permissions must be granted to continue.")
            return
        if self.permission_window is not None:
            self.permission_window.orderOut_(None)
        self.last_error = ""

    def refreshPermissions_(self, _sender):  # type: ignore[no-untyped-def]
        self._permission_check_counter = 0
        self._update_permissions_state()
        if self.permission_state.all_granted:
            self.last_error = ""
            self._show_alert("Permissions Updated", "All required permissions are granted.")
            return

        missing = []
        if not self.permission_state.microphone:
            missing.append("Microphone")
        if not self.permission_state.accessibility:
            missing.append("Accessibility")
        if not self.permission_state.input_monitoring:
            missing.append("Input Monitoring")
        if not self.permission_state.automation:
            missing.append("Automation")

        message = f"Still missing: {', '.join(missing)}."
        if "Input Monitoring" in missing:
            message += " macOS may require app restart after toggling Input Monitoring."
        self._show_alert("Permissions Still Missing", message)

    def requestMicrophonePermission_(self, _sender):  # type: ignore[no-untyped-def]
        self.permission_manager.request_microphone()
        self._update_permissions_state()
        if not self.permission_state.microphone:
            self.permission_manager.open_microphone_settings()

    def requestAccessibilityPermission_(self, _sender):  # type: ignore[no-untyped-def]
        self.permission_manager.request_accessibility_prompt()
        self._update_permissions_state()
        if not self.permission_state.accessibility:
            self.permission_manager.open_accessibility_settings()

    def openInputMonitoringSettings_(self, _sender):  # type: ignore[no-untyped-def]
        self.permission_manager.open_input_monitoring_settings()

    def requestInputMonitoringPermission_(self, _sender):  # type: ignore[no-untyped-def]
        self.permission_manager.request_input_monitoring_prompt()
        self._update_permissions_state()
        if not self.permission_state.input_monitoring:
            self.permission_manager.open_input_monitoring_settings()

    def requestAutomationPermission_(self, _sender):  # type: ignore[no-untyped-def]
        self.permission_manager.request_automation_prompt()
        self._update_permissions_state()
        if not self.permission_state.automation:
            self.permission_manager.open_automation_settings()

    # Alerts
    def _show_alert(self, title: str, text: str) -> None:
        alert = NSAlert.alloc().init()
        alert.setMessageText_(title)
        alert.setInformativeText_(text)
        alert.runModal()


def run_app() -> None:
    app = NSApplication.sharedApplication()
    delegate = AppController.alloc().init()
    app.setDelegate_(delegate)
    app.run()


__all__ = ["run_app", "AppController", "ServiceState", "HistoryTableDataSource"]
