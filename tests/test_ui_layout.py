from whisper_flow.ui.pages import build_crud_page, build_history_page, build_home_page, build_permissions_page, build_settings_page
from whisper_flow.ui.floating_indicator import FloatingIndicatorController


class DummyTarget:
    pass


def _constraint_count(view) -> int:  # type: ignore[no-untyped-def]
    return len(view.constraints())


def test_home_page_builds_with_dashboard() -> None:
    refs = build_home_page(DummyTarget())

    assert refs.welcome_label is not None
    assert refs.status_label is not None
    assert refs.transcript_stack is not None
    assert _constraint_count(refs.view) > 0


def test_history_page_builds_with_table_and_search() -> None:
    refs = build_history_page(DummyTarget())

    assert refs.search_field is not None
    assert refs.table is not None
    assert refs.stats_label is not None
    assert _constraint_count(refs.view) > 0


def test_crud_page_builds_with_all_actions() -> None:
    refs = build_crud_page(
        DummyTarget(),
        title="Dictionary",
        subtitle="test",
        search_action="noop:",
        add_action="noop:",
        edit_action="noop:",
        delete_action="noop:",
        table_columns=[("a", "A", 100.0)],
        extra_action="noop:",
        extra_title="Extra",
    )

    assert refs.search_field is not None
    assert refs.table is not None
    assert refs.add_button is not None
    assert refs.edit_button is not None
    assert refs.delete_button is not None
    assert refs.extra_button is not None
    assert _constraint_count(refs.view) > 0


def test_settings_page_and_permissions_page_build() -> None:
    settings = build_settings_page(DummyTarget())
    permissions = build_permissions_page(DummyTarget())

    assert settings.density_popup is not None
    assert settings.welcome_switch is not None
    assert settings.service_button is not None
    assert settings.language_popup is not None
    assert settings.hotkey_popup is not None
    assert settings.lmstudio_switch is not None
    assert settings.cleanup_provider_popup is not None
    assert settings.groq_key_status_label is not None
    assert settings.set_groq_key_button is not None
    assert settings.clear_groq_key_button is not None
    assert settings.floating_indicator_switch is not None
    assert settings.paste_last_shortcut_switch is not None
    assert settings.paste_fallback_switch is not None
    assert settings.reset_indicator_position_button is not None
    assert sorted(permissions.rows.keys()) == [
        "accessibility",
        "automation",
        "input_monitoring",
        "microphone",
    ]
    assert _constraint_count(settings.view) > 0
    assert _constraint_count(permissions.view) > 0


def test_floating_indicator_builds_and_tracks_origin() -> None:
    moved = []
    indicator = FloatingIndicatorController.alloc().initWithHideDelayMs_enabled_onMove_(
        1000,
        True,
        lambda x, y: moved.append((x, y)),
    )

    indicator.set_origin(120.0, 90.0)
    indicator.show_recording(0.4)
    origin = indicator.current_origin()

    assert origin is not None
    assert origin[0] >= 0.0
    assert origin[1] >= 0.0
    indicator.hide()
