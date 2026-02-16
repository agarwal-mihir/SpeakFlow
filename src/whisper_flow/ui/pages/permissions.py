from __future__ import annotations

from dataclasses import dataclass

from AppKit import NSButton, NSTextField

from whisper_flow.ui import theme
from whisper_flow.ui.components import make_button, make_card, make_content_page, make_label, make_stack, pin_edges


@dataclass
class PermissionRowRefs:
    status_label: NSTextField
    action_button: NSButton


@dataclass
class PermissionsPageRefs:
    view: object
    rows: dict[str, PermissionRowRefs]
    continue_button: NSButton | None = None


def _build_permission_row(target, title: str, action_title: str, selector: str, help_text: str) -> tuple[object, PermissionRowRefs]:  # type: ignore[no-untyped-def]
    card = make_card()
    content = make_stack(vertical=True, spacing=theme.SPACE.sm)
    card.contentView().addSubview_(content)
    pin_edges(content, card.contentView(), inset=theme.SPACE.md)

    row = make_stack(vertical=False, spacing=theme.SPACE.md)
    title_label = make_label(title, font=theme.strong_font())
    status_label = make_label("Missing", color=theme.danger_color())
    action_button = make_button(action_title, target, selector)

    row.addArrangedSubview_(title_label)
    row.addArrangedSubview_(status_label)
    row.addArrangedSubview_(action_button)
    content.addArrangedSubview_(row)

    help_label = make_label(help_text, font=theme.meta_font(), color=theme.secondary_text_color())
    help_label.setLineBreakMode_(0)  # NSLineBreakByWordWrapping
    help_label.setUsesSingleLineMode_(False)
    help_label.setMaximumNumberOfLines_(0)
    help_label.setPreferredMaxLayoutWidth_(980.0)
    cell = help_label.cell()
    if cell is not None:
        cell.setWraps_(True)
        cell.setScrollable_(False)
    content.addArrangedSubview_(help_label)

    return card, PermissionRowRefs(status_label=status_label, action_button=action_button)


def build_permissions_page(target) -> PermissionsPageRefs:  # type: ignore[no-untyped-def]
    root, stack = make_content_page("Permissions", "Grant all permissions for reliable dictation and insertion.")

    rows: dict[str, PermissionRowRefs] = {}
    specs = [
        ("microphone", "Microphone", "Grant Access", "requestMicrophonePermission:",
         "Manual: System Settings → Privacy & Security → Microphone → Toggle on SpeakFlow. "
         "If still 'Missing' after granting, remove SpeakFlow from the list and re-add it (required after rebuilding the app)."),
        ("accessibility", "Accessibility", "Grant Access", "requestAccessibilityPermission:",
         "Manual: System Settings → Privacy & Security → Accessibility → Add SpeakFlow and enable. "
         "If still 'Missing' after granting, remove SpeakFlow from the list, click '+', and re-add the new app."),
        ("input_monitoring", "Input Monitoring", "Grant Access", "requestInputMonitoringPermission:",
         "Manual: System Settings → Privacy & Security → Input Monitoring → Add SpeakFlow and enable. "
         "If still 'Missing' after granting, remove SpeakFlow from the list, click '+', and re-add the new app."),
        ("automation", "Automation", "Grant Access", "requestAutomationPermission:",
         "Manual: System Settings → Privacy & Security → Automation → SpeakFlow → Enable System Events. "
         "If still 'Missing' after granting, remove SpeakFlow from the list and re-add it."),
    ]

    for key, title, action, selector, help_text in specs:
        card, refs = _build_permission_row(target, title, action, selector, help_text)
        rows[key] = refs
        stack.addArrangedSubview_(card)

    footer = make_stack(vertical=False, spacing=theme.SPACE.sm)
    footer.addArrangedSubview_(make_button("Re-check", target, "refreshPermissions:"))
    footer.addArrangedSubview_(make_button("Open Setup Wizard", target, "openPermissionWizard:"))
    stack.addArrangedSubview_(footer)

    return PermissionsPageRefs(view=root, rows=rows)


def build_permission_wizard(target) -> PermissionsPageRefs:  # type: ignore[no-untyped-def]
    root, stack = make_content_page("Complete setup", "SpeakFlow needs all permissions before dictation starts.")

    rows: dict[str, PermissionRowRefs] = {}
    specs = [
        ("microphone", "Microphone", "Grant Access", "requestMicrophonePermission:",
         "Manual: System Settings → Privacy & Security → Microphone → Toggle on SpeakFlow. "
         "If still 'Missing' after granting, remove SpeakFlow from the list and re-add it (required after rebuilding the app)."),
        ("accessibility", "Accessibility", "Grant Access", "requestAccessibilityPermission:",
         "Manual: System Settings → Privacy & Security → Accessibility → Add SpeakFlow and enable. "
         "If still 'Missing' after granting, remove SpeakFlow from the list, click '+', and re-add the new app."),
        ("input_monitoring", "Input Monitoring", "Grant Access", "requestInputMonitoringPermission:",
         "Manual: System Settings → Privacy & Security → Input Monitoring → Add SpeakFlow and enable. "
         "If still 'Missing' after granting, remove SpeakFlow from the list, click '+', and re-add the new app."),
        ("automation", "Automation", "Grant Access", "requestAutomationPermission:",
         "Manual: System Settings → Privacy & Security → Automation → SpeakFlow → Enable System Events. "
         "If still 'Missing' after granting, remove SpeakFlow from the list and re-add it."),
    ]

    for key, title, action, selector, help_text in specs:
        card, refs = _build_permission_row(target, title, action, selector, help_text)
        rows[key] = refs
        stack.addArrangedSubview_(card)

    footer = make_stack(vertical=False, spacing=theme.SPACE.sm)
    footer.addArrangedSubview_(make_button("Re-check", target, "refreshPermissions:"))
    continue_button = make_button("Continue", target, "continueAfterPermissionSetup:", primary=True)
    footer.addArrangedSubview_(continue_button)
    stack.addArrangedSubview_(footer)

    return PermissionsPageRefs(view=root, rows=rows, continue_button=continue_button)
