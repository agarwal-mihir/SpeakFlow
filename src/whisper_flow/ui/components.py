from __future__ import annotations

from typing import Iterable

from AppKit import (
    NSAttributedString,
    NSBox,
    NSBoxCustom,
    NSButton,
    NSColor,
    NSFontAttributeName,
    NSForegroundColorAttributeName,
    NSImage,
    NSImageLeading,
    NSLayoutAttributeLeading,
    NSLineBorder,
    NSLayoutConstraint,
    NSNoTitle,
    NSPopUpButton,
    NSScrollView,
    NSSearchField,
    NSStackView,
    NSSwitchButton,
    NSTableColumn,
    NSTableView,
    NSTextField,
    NSUserInterfaceLayoutOrientationHorizontal,
    NSUserInterfaceLayoutOrientationVertical,
    NSView,
)

from whisper_flow.ui import theme


def with_autolayout(view):  # type: ignore[no-untyped-def]
    view.setTranslatesAutoresizingMaskIntoConstraints_(False)
    return view


def activate(constraints: Iterable) -> None:  # type: ignore[no-untyped-def]
    NSLayoutConstraint.activateConstraints_(list(constraints))


def pin_edges(view: NSView, parent: NSView, inset: float = 0.0) -> None:
    activate(
        [
            view.leadingAnchor().constraintEqualToAnchor_constant_(parent.leadingAnchor(), inset),
            view.trailingAnchor().constraintEqualToAnchor_constant_(parent.trailingAnchor(), -inset),
            view.topAnchor().constraintEqualToAnchor_constant_(parent.topAnchor(), inset),
            view.bottomAnchor().constraintEqualToAnchor_constant_(parent.bottomAnchor(), -inset),
        ]
    )


def make_stack(vertical: bool = True, spacing: float = theme.SPACE.md) -> NSStackView:
    stack = with_autolayout(NSStackView.alloc().init())
    stack.setOrientation_(
        NSUserInterfaceLayoutOrientationVertical if vertical else NSUserInterfaceLayoutOrientationHorizontal
    )
    stack.setSpacing_(spacing)
    if vertical:
        stack.setAlignment_(NSLayoutAttributeLeading)
    return stack


def make_label(text: str, font=None, color=None) -> NSTextField:  # type: ignore[no-untyped-def]
    label = with_autolayout(NSTextField.labelWithString_(text))
    label.setFont_(font or theme.body_font())
    label.setTextColor_(color or theme.primary_text_color())
    return label


def _styled_title(text: str, font, color) -> NSAttributedString:  # type: ignore[no-untyped-def]
    """Create an NSAttributedString with explicit font and color."""
    attrs = {NSForegroundColorAttributeName: color, NSFontAttributeName: font}
    return NSAttributedString.alloc().initWithString_attributes_(text, attrs)


def set_button_title(button: NSButton, title: str) -> None:
    """Set button title preserving current contentTintColor and font."""
    color = button.contentTintColor() or theme.primary_text_color()
    font = button.font() or theme.body_font()
    button.setAttributedTitle_(_styled_title(title, font, color))


def make_button(title: str, target, action: str, primary: bool = False) -> NSButton:  # type: ignore[no-untyped-def]
    button = with_autolayout(NSButton.buttonWithTitle_target_action_(title, target, action))
    button.setBordered_(False)
    button.setWantsLayer_(True)
    button.layer().setCornerRadius_(6.0)
    if primary:
        button.layer().setBackgroundColor_(theme.accent_color().CGColor())
        color = NSColor.whiteColor()
        font = theme.strong_font()
    else:
        button.layer().setBackgroundColor_(theme.accent_soft_color().CGColor())
        color = theme.primary_text_color()
        font = theme.body_font()
    button.setFont_(font)
    button.setContentTintColor_(color)
    button.setAttributedTitle_(_styled_title(title, font, color))
    return button


def make_switch(title: str, target, action: str) -> NSButton:  # type: ignore[no-untyped-def]
    checkbox = with_autolayout(NSButton.alloc().init())
    checkbox.setButtonType_(NSSwitchButton)
    checkbox.setTitle_(title)
    checkbox.setTarget_(target)
    checkbox.setAction_(action)
    checkbox.setAttributedTitle_(_styled_title(title, theme.body_font(), theme.primary_text_color()))
    return checkbox


def make_popup(items: list[str], target, action: str) -> NSPopUpButton:  # type: ignore[no-untyped-def]
    popup = with_autolayout(NSPopUpButton.alloc().init())
    popup.addItemsWithTitles_(items)
    popup.setTarget_(target)
    popup.setAction_(action)
    return popup


def make_search_field(placeholder: str, target, action: str) -> NSSearchField:  # type: ignore[no-untyped-def]
    field = with_autolayout(NSSearchField.alloc().init())
    field.setPlaceholderString_(placeholder)
    field.setTarget_(target)
    field.setAction_(action)
    return field


def make_card() -> NSBox:
    card = with_autolayout(NSBox.alloc().init())
    card.setBoxType_(NSBoxCustom)
    card.setBorderType_(NSLineBorder)
    card.setTitlePosition_(NSNoTitle)
    card.setBorderWidth_(1.0)
    card.setCornerRadius_(theme.RADIUS.md)
    card.setFillColor_(theme.card_background_color())
    card.setBorderColor_(theme.card_border_color())
    return card


def make_chip(text: str) -> NSBox:
    chip = make_card()
    chip.setCornerRadius_(theme.RADIUS.sm)
    label = make_label(text, font=theme.meta_font(), color=theme.secondary_text_color())
    chip.contentView().addSubview_(label)
    activate(
        [
            label.leadingAnchor().constraintEqualToAnchor_constant_(chip.contentView().leadingAnchor(), theme.SPACE.sm),
            label.trailingAnchor().constraintEqualToAnchor_constant_(chip.contentView().trailingAnchor(), -theme.SPACE.sm),
            label.topAnchor().constraintEqualToAnchor_constant_(chip.contentView().topAnchor(), theme.SPACE.xs),
            label.bottomAnchor().constraintEqualToAnchor_constant_(chip.contentView().bottomAnchor(), -theme.SPACE.xs),
        ]
    )
    return chip


def make_table(columns: list[tuple[str, str, float]]) -> tuple[NSScrollView, NSTableView]:
    scroll = with_autolayout(NSScrollView.alloc().init())
    scroll.setHasVerticalScroller_(True)

    table = NSTableView.alloc().init()
    table.setUsesAlternatingRowBackgroundColors_(False)

    for identifier, title, width in columns:
        column = NSTableColumn.alloc().initWithIdentifier_(identifier)
        column.setTitle_(title)
        column.setWidth_(width)
        table.addTableColumn_(column)

    scroll.setDocumentView_(table)
    return scroll, table


def table_rows_height(table: NSTableView, height: float = 40.0) -> None:
    table.setRowHeight_(height)


def make_content_page(title: str, subtitle: str | None = None) -> tuple[NSView, NSStackView]:
    root = with_autolayout(NSView.alloc().init())
    stack = make_stack(vertical=True, spacing=theme.SPACE.lg)
    root.addSubview_(stack)
    pin_edges(stack, root, inset=theme.SPACE.xl)

    header = make_stack(vertical=True, spacing=theme.SPACE.xs)
    header.addArrangedSubview_(make_label(title, font=theme.section_title_font()))
    if subtitle:
        header.addArrangedSubview_(make_label(subtitle, color=theme.secondary_text_color()))
    stack.addArrangedSubview_(header)

    return root, stack


# ── Modern sidebar button with SF Symbol icon ───────────────────────
def make_sidebar_button(title: str, sf_symbol: str, target, action: str) -> NSButton:  # type: ignore[no-untyped-def]
    display_title = f"  {title}"
    button = with_autolayout(NSButton.buttonWithTitle_target_action_(display_title, target, action))
    button.setBordered_(False)
    button.setFont_(theme.sidebar_item_font())
    button.setContentTintColor_(theme.primary_text_color())
    button.setImagePosition_(NSImageLeading)
    button.setAlignment_(0)  # NSTextAlignmentLeft
    button.setAttributedTitle_(_styled_title(display_title, theme.sidebar_item_font(), theme.primary_text_color()))

    image = NSImage.imageWithSystemSymbolName_accessibilityDescription_(sf_symbol, title)
    if image is not None:
        button.setImage_(image)

    button.setWantsLayer_(True)
    button.layer().setCornerRadius_(theme.RADIUS.sm)

    activate([button.heightAnchor().constraintEqualToConstant_(32.0)])
    return button


def set_sidebar_button_active(button: NSButton, active: bool) -> None:
    if button.layer() is None:
        button.setWantsLayer_(True)
    color = theme.accent_color() if active else theme.primary_text_color()
    if active:
        button.layer().setBackgroundColor_(theme.sidebar_active_bg_color().CGColor())
    else:
        button.layer().setBackgroundColor_(NSColor.clearColor().CGColor())
    button.setContentTintColor_(color)
    title_str = str(button.title())
    button.setAttributedTitle_(_styled_title(title_str, theme.sidebar_item_font(), color))


# ── Warm banner card (cream/yellow like Flow) ────────────────────────
def make_banner_card(title: str, body: str, button_title: str | None = None, target=None, action: str | None = None) -> NSBox:  # type: ignore[no-untyped-def]
    card = with_autolayout(NSBox.alloc().init())
    card.setBoxType_(NSBoxCustom)
    card.setBorderType_(NSLineBorder)
    card.setTitlePosition_(NSNoTitle)
    card.setBorderWidth_(1.0)
    card.setCornerRadius_(theme.RADIUS.md)
    card.setFillColor_(theme.banner_bg_color())
    card.setBorderColor_(theme.banner_border_color())

    stack = make_stack(vertical=True, spacing=theme.SPACE.md)
    card.contentView().addSubview_(stack)

    title_label = make_label(title, font=theme.banner_title_font())
    body_label = make_label(body, color=theme.secondary_text_color())
    body_label.setPreferredMaxLayoutWidth_(600.0)

    stack.addArrangedSubview_(title_label)
    stack.addArrangedSubview_(body_label)

    if button_title and target and action:
        btn = make_button(button_title, target, action, primary=True)
        btn_row = make_stack(vertical=False, spacing=0)
        btn_row.addArrangedSubview_(btn)
        # Push button left by adding a flexible spacer
        spacer = with_autolayout(NSView.alloc().init())
        btn_row.addArrangedSubview_(spacer)
        stack.addArrangedSubview_(btn_row)

    activate([
        stack.leadingAnchor().constraintEqualToAnchor_constant_(card.contentView().leadingAnchor(), theme.SPACE.lg),
        stack.trailingAnchor().constraintEqualToAnchor_constant_(card.contentView().trailingAnchor(), -theme.SPACE.lg),
        stack.topAnchor().constraintEqualToAnchor_constant_(card.contentView().topAnchor(), theme.SPACE.lg),
        stack.bottomAnchor().constraintEqualToAnchor_constant_(card.contentView().bottomAnchor(), -theme.SPACE.lg),
    ])

    return card


# ── Stat chip (emoji + text) ─────────────────────────────────────────
def make_stat_chip(emoji: str, text: str) -> NSView:
    row = make_stack(vertical=False, spacing=theme.SPACE.xs)
    emoji_label = make_label(emoji, font=theme.stat_chip_font())
    text_label = make_label(text, font=theme.stat_chip_font(), color=theme.secondary_text_color())
    row.addArrangedSubview_(emoji_label)
    row.addArrangedSubview_(text_label)
    return row


def make_stat_separator() -> NSTextField:
    sep = make_label("|", font=theme.stat_chip_font(), color=theme.separator_color())
    return sep


# ── Day header for grouped history ──────────────────────────────────
def make_day_header(text: str) -> NSTextField:
    label = make_label(text, font=theme.day_header_font(), color=theme.secondary_text_color())
    label.setStringValue_(text.upper())
    return label


# ── History row for Home dashboard ──────────────────────────────────
def make_history_row(timestamp: str, text: str) -> NSView:
    row = make_stack(vertical=False, spacing=theme.SPACE.lg)
    time_label = make_label(timestamp, font=theme.timestamp_font(), color=theme.secondary_text_color())
    activate([time_label.widthAnchor().constraintEqualToConstant_(80.0)])
    text_label = make_label(text, font=theme.body_font())
    text_label.setLineBreakMode_(4)  # NSLineBreakByTruncatingTail
    row.addArrangedSubview_(time_label)
    row.addArrangedSubview_(text_label)
    return row


# ── Sidebar info card (version + status) ────────────────────────────
def make_sidebar_info_card(version: str = "v0.1.0") -> tuple[NSBox, NSTextField]:
    card = with_autolayout(NSBox.alloc().init())
    card.setBoxType_(NSBoxCustom)
    card.setBorderType_(NSLineBorder)
    card.setTitlePosition_(NSNoTitle)
    card.setBorderWidth_(1.0)
    card.setCornerRadius_(theme.RADIUS.sm)
    card.setFillColor_(theme.card_background_color())
    card.setBorderColor_(theme.card_border_color())

    stack = make_stack(vertical=True, spacing=theme.SPACE.xs)
    card.contentView().addSubview_(stack)

    version_label = make_label(f"SpeakFlow {version}", font=theme.strong_font())
    status_label = make_label("Running in background", font=theme.meta_font(), color=theme.secondary_text_color())

    stack.addArrangedSubview_(version_label)
    stack.addArrangedSubview_(status_label)

    activate([
        stack.leadingAnchor().constraintEqualToAnchor_constant_(card.contentView().leadingAnchor(), theme.SPACE.sm),
        stack.trailingAnchor().constraintEqualToAnchor_constant_(card.contentView().trailingAnchor(), -theme.SPACE.sm),
        stack.topAnchor().constraintEqualToAnchor_constant_(card.contentView().topAnchor(), theme.SPACE.sm),
        stack.bottomAnchor().constraintEqualToAnchor_constant_(card.contentView().bottomAnchor(), -theme.SPACE.sm),
    ])

    return card, status_label
