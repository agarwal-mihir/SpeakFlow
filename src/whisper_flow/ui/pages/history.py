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
class HistoryPageRefs:
    view: object
    search_field: NSSearchField
    stats_label: NSTextField
    table: NSTableView
    copy_button: NSButton
    delete_button: NSButton


def build_history_page(target) -> HistoryPageRefs:  # type: ignore[no-untyped-def]
    root, stack = make_content_page("History", "Search and manage past dictations.")

    top_row = make_stack(vertical=False, spacing=theme.SPACE.md)
    search_field = make_search_field("Search transcripts", target, "historySearchChanged:")
    stats_label = NSTextField.labelWithString_("Total: 0")
    stats_label.setFont_(theme.meta_font())
    stats_label.setTextColor_(theme.secondary_text_color())
    stats_label.setTranslatesAutoresizingMaskIntoConstraints_(False)
    top_row.addArrangedSubview_(search_field)
    top_row.addArrangedSubview_(stats_label)

    scroll, table = make_table(
        [
            ("time", "Time", 180.0),
            ("app", "App", 180.0),
            ("text", "Text", 900.0),
        ]
    )
    text_column = table.tableColumnWithIdentifier_("text")
    if text_column is not None:
        text_cell = text_column.dataCell()
        if text_cell is not None:
            # Enable multiline wrapping for transcript text.
            text_cell.setLineBreakMode_(0)  # NSLineBreakByWordWrapping
            text_cell.setUsesSingleLineMode_(False)
            text_cell.setWraps_(True)
            text_cell.setScrollable_(False)

    action_row = make_stack(vertical=False, spacing=theme.SPACE.sm)
    copy_button = make_button("Copy Selected", target, "copySelectedHistory:")
    delete_button = make_button("Delete Selected", target, "deleteSelectedHistory:")
    refresh_button = make_button("Refresh", target, "refreshHistory:")
    action_row.addArrangedSubview_(copy_button)
    action_row.addArrangedSubview_(delete_button)
    action_row.addArrangedSubview_(refresh_button)

    stack.addArrangedSubview_(top_row)
    stack.addArrangedSubview_(scroll)
    stack.addArrangedSubview_(action_row)

    activate(
        [
            search_field.widthAnchor().constraintGreaterThanOrEqualToConstant_(340.0),
            scroll.heightAnchor().constraintGreaterThanOrEqualToConstant_(360.0),
        ]
    )

    return HistoryPageRefs(
        view=root,
        search_field=search_field,
        stats_label=stats_label,
        table=table,
        copy_button=copy_button,
        delete_button=delete_button,
    )
