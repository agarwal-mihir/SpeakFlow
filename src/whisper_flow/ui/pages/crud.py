from __future__ import annotations

from dataclasses import dataclass

from AppKit import NSButton, NSSearchField, NSTableView, NSTextField

from whisper_flow.ui import theme
from whisper_flow.ui.components import (
    activate,
    make_button,
    make_content_page,
    make_search_field,
    make_stack,
    make_table,
)


@dataclass
class CrudPageRefs:
    view: object
    search_field: NSSearchField
    table: NSTableView
    stats_label: NSTextField
    add_button: NSButton
    edit_button: NSButton
    delete_button: NSButton
    extra_button: NSButton | None = None


def build_crud_page(
    target,  # type: ignore[no-untyped-def]
    title: str,
    subtitle: str,
    search_action: str,
    add_action: str,
    edit_action: str,
    delete_action: str,
    table_columns: list[tuple[str, str, float]],
    extra_action: str | None = None,
    extra_title: str | None = None,
) -> CrudPageRefs:
    root, stack = make_content_page(title, subtitle)

    top_row = make_stack(vertical=False, spacing=theme.SPACE.md)
    search_field = make_search_field(f"Search {title.lower()}", target, search_action)
    stats_label = NSTextField.labelWithString_("0 items")
    stats_label.setFont_(theme.meta_font())
    stats_label.setTextColor_(theme.secondary_text_color())
    stats_label.setTranslatesAutoresizingMaskIntoConstraints_(False)
    top_row.addArrangedSubview_(search_field)
    top_row.addArrangedSubview_(stats_label)

    scroll, table = make_table(table_columns)

    actions = make_stack(vertical=False, spacing=theme.SPACE.sm)
    add_button = make_button("Add", target, add_action, primary=True)
    edit_button = make_button("Edit", target, edit_action)
    delete_button = make_button("Delete", target, delete_action)
    actions.addArrangedSubview_(add_button)
    actions.addArrangedSubview_(edit_button)
    actions.addArrangedSubview_(delete_button)

    extra_button = None
    if extra_action and extra_title:
        extra_button = make_button(extra_title, target, extra_action)
        actions.addArrangedSubview_(extra_button)

    stack.addArrangedSubview_(top_row)
    stack.addArrangedSubview_(scroll)
    stack.addArrangedSubview_(actions)

    activate(
        [
            search_field.widthAnchor().constraintGreaterThanOrEqualToConstant_(340.0),
            scroll.heightAnchor().constraintGreaterThanOrEqualToConstant_(340.0),
        ]
    )

    return CrudPageRefs(
        view=root,
        search_field=search_field,
        table=table,
        stats_label=stats_label,
        add_button=add_button,
        edit_button=edit_button,
        delete_button=delete_button,
        extra_button=extra_button,
    )
