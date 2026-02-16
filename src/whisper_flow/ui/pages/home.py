from __future__ import annotations

from dataclasses import dataclass, field

from AppKit import NSScrollView, NSStackView, NSTextField, NSView

from whisper_flow.ui import theme
from whisper_flow.ui.components import (
    activate,
    make_banner_card,
    make_content_page,
    make_day_header,
    make_history_row,
    make_label,
    make_stack,
    make_stat_chip,
    make_stat_separator,
    with_autolayout,
)


@dataclass
class HomePageRefs:
    view: object
    welcome_label: NSTextField
    status_label: NSTextField
    error_label: NSTextField
    stats_days: NSTextField | None = None
    stats_words: NSTextField | None = None
    stats_wpm: NSTextField | None = None
    transcript_stack: NSStackView | None = None
    recent_label: NSTextField | None = None


def build_home_page(target) -> HomePageRefs:  # type: ignore[no-untyped-def]
    root, stack = make_content_page("Welcome back", None)

    # ── Top row: welcome + stats ────────────────────────────────────
    top_row = make_stack(vertical=False, spacing=theme.SPACE.md)
    welcome_label = make_label("Welcome back", font=theme.title_font())
    top_row.addArrangedSubview_(welcome_label)

    spacer = with_autolayout(NSView.alloc().init())
    top_row.addArrangedSubview_(spacer)

    days_chip = make_stat_chip("\U0001f525", "0 days")
    days_label = days_chip.arrangedSubviews()[1]
    top_row.addArrangedSubview_(days_chip)
    top_row.addArrangedSubview_(make_stat_separator())

    words_chip = make_stat_chip("\U0001f680", "0 words")
    words_label = words_chip.arrangedSubviews()[1]
    top_row.addArrangedSubview_(words_chip)
    top_row.addArrangedSubview_(make_stat_separator())

    wpm_chip = make_stat_chip("\U0001f3c6", "0 WPM")
    wpm_label = wpm_chip.arrangedSubviews()[1]
    top_row.addArrangedSubview_(wpm_chip)

    # Replace the default header with our custom top row
    existing_header = stack.arrangedSubviews()[0]
    stack.removeArrangedSubview_(existing_header)
    existing_header.removeFromSuperview()
    stack.insertArrangedSubview_atIndex_(top_row, 0)

    # ── Banner card ─────────────────────────────────────────────────
    banner = make_banner_card(
        "Hold fn to dictate and let Flow format for you",
        "Press and hold fn to dictate in any app. Flow\u2019s Smart Formatting "
        "and Backtrack will handle punctuation, new lines, lists, and adjust "
        "when you change your mind mid-sentence.",
        button_title="Show me how",
        target=target,
        action="openPermissionWizard:",
    )
    stack.addArrangedSubview_(banner)

    # ── Small status indicator ──────────────────────────────────────
    status_row = make_stack(vertical=False, spacing=theme.SPACE.sm)
    status_label = make_label("Status: Idle", font=theme.meta_font(), color=theme.secondary_text_color())
    error_label = make_label("", font=theme.meta_font(), color=theme.danger_color())
    status_row.addArrangedSubview_(status_label)
    status_row.addArrangedSubview_(error_label)
    stack.addArrangedSubview_(status_row)

    # ── Recent transcripts (grouped by day) ─────────────────────────
    scroll = with_autolayout(NSScrollView.alloc().init())
    scroll.setHasVerticalScroller_(True)
    scroll.setDrawsBackground_(False)
    scroll.setBorderType_(0)  # NSNoBorder

    transcript_stack = make_stack(vertical=True, spacing=theme.SPACE.sm)

    clip = scroll.contentView()
    scroll.setDocumentView_(transcript_stack)

    recent_label = make_label("No dictation yet.", color=theme.secondary_text_color())
    transcript_stack.addArrangedSubview_(recent_label)

    stack.addArrangedSubview_(scroll)

    activate([
        scroll.heightAnchor().constraintGreaterThanOrEqualToConstant_(200.0),
        transcript_stack.leadingAnchor().constraintEqualToAnchor_(clip.leadingAnchor()),
        transcript_stack.trailingAnchor().constraintEqualToAnchor_(clip.trailingAnchor()),
        transcript_stack.topAnchor().constraintEqualToAnchor_(clip.topAnchor()),
    ])

    return HomePageRefs(
        view=root,
        welcome_label=welcome_label,
        status_label=status_label,
        error_label=error_label,
        stats_days=days_label,
        stats_words=words_label,
        stats_wpm=wpm_label,
        transcript_stack=transcript_stack,
        recent_label=recent_label,
    )
