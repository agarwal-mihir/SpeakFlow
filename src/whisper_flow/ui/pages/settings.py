from __future__ import annotations

from dataclasses import dataclass

from AppKit import NSButton, NSPopUpButton, NSTextField

from whisper_flow.ui import theme
from whisper_flow.ui.components import (
    activate,
    make_button,
    make_card,
    make_content_page,
    make_label,
    make_popup,
    make_stack,
    make_switch,
    pin_edges,
)


@dataclass
class SettingsPageRefs:
    view: object
    service_button: NSButton
    lmstudio_switch: NSButton
    cleanup_provider_popup: NSPopUpButton
    groq_key_status_label: NSTextField
    set_groq_key_button: NSButton
    clear_groq_key_button: NSButton
    language_popup: NSPopUpButton
    hotkey_popup: NSPopUpButton
    density_popup: NSPopUpButton
    welcome_switch: NSButton
    floating_indicator_switch: NSButton
    paste_last_shortcut_switch: NSButton
    paste_fallback_switch: NSButton
    reset_indicator_position_button: NSButton


def build_settings_page(target) -> SettingsPageRefs:  # type: ignore[no-untyped-def]
    root, stack = make_content_page("Settings", "App behavior, startup, and diagnostics.")

    # ── Service controls (moved from Home) ──────────────────────────
    service_card = make_card()
    service_stack = make_stack(vertical=True, spacing=theme.SPACE.md)
    service_card.contentView().addSubview_(service_stack)
    pin_edges(service_stack, service_card.contentView(), inset=theme.SPACE.md)
    service_stack.addArrangedSubview_(make_label("Dictation Service", font=theme.strong_font()))

    svc_row = make_stack(vertical=False, spacing=theme.SPACE.md)
    service_button = make_button("Stop Service", target, "toggleServiceFromSettings:", primary=True)
    lmstudio_switch = make_switch("Use AI cleanup", target, "toggleLmStudioFromSettings:")
    cleanup_provider_popup = make_popup(
        ["Groq -> LM Studio", "Deterministic"],
        target,
        "changeCleanupProvider:",
    )
    svc_row.addArrangedSubview_(service_button)
    svc_row.addArrangedSubview_(lmstudio_switch)
    svc_row.addArrangedSubview_(cleanup_provider_popup)
    service_stack.addArrangedSubview_(svc_row)

    groq_row = make_stack(vertical=False, spacing=theme.SPACE.sm)
    groq_key_status_label = make_label("Groq key: Missing", color=theme.secondary_text_color())
    set_groq_key_button = make_button("Set Groq API Key", target, "setGroqApiKey:")
    clear_groq_key_button = make_button("Clear Key", target, "clearGroqApiKey:")
    groq_row.addArrangedSubview_(groq_key_status_label)
    groq_row.addArrangedSubview_(set_groq_key_button)
    groq_row.addArrangedSubview_(clear_groq_key_button)
    service_stack.addArrangedSubview_(groq_row)

    mode_row = make_stack(vertical=False, spacing=theme.SPACE.md)
    language_popup = make_popup(["Auto", "English", "Hinglish (Roman)"], target, "changeLanguageMode:")
    hotkey_popup = make_popup(["Fn Hold", "Fn+Space Hold"], target, "changeHotkeyMode:")
    permission_button = make_button("Permission Setup", target, "openPermissionWizard:")
    mode_row.addArrangedSubview_(language_popup)
    mode_row.addArrangedSubview_(hotkey_popup)
    mode_row.addArrangedSubview_(permission_button)
    service_stack.addArrangedSubview_(mode_row)

    stack.addArrangedSubview_(service_card)

    # ── UI preferences ──────────────────────────────────────────────
    ui_stack = make_stack(vertical=False, spacing=theme.SPACE.md)
    density_popup = make_popup(["Comfortable", "Compact"], target, "changeUiDensity:")
    welcome_switch = make_switch("Show welcome card", target, "toggleWelcomeCard:")
    ui_stack.addArrangedSubview_(density_popup)
    ui_stack.addArrangedSubview_(welcome_switch)

    indicator_stack = make_stack(vertical=True, spacing=theme.SPACE.sm)
    floating_indicator_switch = make_switch(
        "Floating recording indicator",
        target,
        "toggleFloatingIndicatorFromSettings:",
    )
    paste_last_shortcut_switch = make_switch(
        "Enable Option+Cmd+V paste-last",
        target,
        "togglePasteLastShortcutFromSettings:",
    )
    paste_fallback_switch = make_switch(
        "Keep dictation in clipboard if auto-paste fails",
        target,
        "togglePasteFallbackFromSettings:",
    )
    reset_indicator_position_button = make_button(
        "Reset Indicator Position",
        target,
        "resetFloatingIndicatorPosition:",
    )
    indicator_stack.addArrangedSubview_(floating_indicator_switch)
    indicator_stack.addArrangedSubview_(paste_last_shortcut_switch)
    indicator_stack.addArrangedSubview_(paste_fallback_switch)
    indicator_stack.addArrangedSubview_(reset_indicator_position_button)

    # ── File actions ────────────────────────────────────────────────
    actions = make_stack(vertical=True, spacing=theme.SPACE.sm)
    actions.addArrangedSubview_(make_button("Open Config", target, "openConfig:"))
    actions.addArrangedSubview_(make_button("Open Logs", target, "openLogs:"))
    actions.addArrangedSubview_(make_button("Open History Folder", target, "openHistoryFolder:"))
    actions.addArrangedSubview_(make_button("Install Auto-start", target, "installAutostart:"))
    actions.addArrangedSubview_(make_button("Uninstall Auto-start", target, "uninstallAutostart:"))

    stack.addArrangedSubview_(ui_stack)
    stack.addArrangedSubview_(indicator_stack)
    stack.addArrangedSubview_(actions)

    activate(
        [
            cleanup_provider_popup.widthAnchor().constraintGreaterThanOrEqualToConstant_(180.0),
            density_popup.widthAnchor().constraintGreaterThanOrEqualToConstant_(180.0),
        ]
    )

    return SettingsPageRefs(
        view=root,
        service_button=service_button,
        lmstudio_switch=lmstudio_switch,
        cleanup_provider_popup=cleanup_provider_popup,
        groq_key_status_label=groq_key_status_label,
        set_groq_key_button=set_groq_key_button,
        clear_groq_key_button=clear_groq_key_button,
        language_popup=language_popup,
        hotkey_popup=hotkey_popup,
        density_popup=density_popup,
        welcome_switch=welcome_switch,
        floating_indicator_switch=floating_indicator_switch,
        paste_last_shortcut_switch=paste_last_shortcut_switch,
        paste_fallback_switch=paste_fallback_switch,
        reset_indicator_position_button=reset_indicator_position_button,
    )
