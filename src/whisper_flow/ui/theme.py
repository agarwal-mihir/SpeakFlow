from __future__ import annotations

from dataclasses import dataclass

from AppKit import NSColor, NSFont


@dataclass(frozen=True)
class Spacing:
    xs: float = 4.0
    sm: float = 8.0
    md: float = 14.0
    lg: float = 20.0
    xl: float = 28.0
    xxl: float = 36.0


@dataclass(frozen=True)
class Radius:
    sm: float = 8.0
    md: float = 12.0
    lg: float = 16.0


SPACE = Spacing()
RADIUS = Radius()

SIDEBAR_WIDTH: float = 220.0


def app_background_color() -> NSColor:
    return NSColor.colorWithCalibratedRed_green_blue_alpha_(0.98, 0.98, 0.98, 1.0)


def sidebar_background_color() -> NSColor:
    return NSColor.colorWithCalibratedRed_green_blue_alpha_(0.965, 0.965, 0.97, 1.0)


def sidebar_active_bg_color() -> NSColor:
    return NSColor.colorWithCalibratedRed_green_blue_alpha_(0.92, 0.92, 0.94, 1.0)


def card_background_color() -> NSColor:
    return NSColor.colorWithCalibratedRed_green_blue_alpha_(1.0, 1.0, 1.0, 1.0)


def card_border_color() -> NSColor:
    return NSColor.colorWithCalibratedRed_green_blue_alpha_(0.90, 0.90, 0.92, 1.0)


def banner_bg_color() -> NSColor:
    return NSColor.colorWithCalibratedRed_green_blue_alpha_(0.99, 0.97, 0.90, 1.0)


def banner_border_color() -> NSColor:
    return NSColor.colorWithCalibratedRed_green_blue_alpha_(0.94, 0.91, 0.82, 1.0)


def separator_color() -> NSColor:
    return NSColor.colorWithCalibratedRed_green_blue_alpha_(0.88, 0.88, 0.90, 1.0)


def primary_text_color() -> NSColor:
    return NSColor.colorWithCalibratedRed_green_blue_alpha_(0.12, 0.12, 0.14, 1.0)


def secondary_text_color() -> NSColor:
    return NSColor.colorWithCalibratedRed_green_blue_alpha_(0.44, 0.44, 0.50, 1.0)


def accent_color() -> NSColor:
    return NSColor.colorWithCalibratedRed_green_blue_alpha_(0.16, 0.18, 0.30, 1.0)


def accent_soft_color() -> NSColor:
    return NSColor.colorWithCalibratedRed_green_blue_alpha_(0.92, 0.93, 0.98, 1.0)


def success_color() -> NSColor:
    return NSColor.colorWithCalibratedRed_green_blue_alpha_(0.16, 0.56, 0.28, 1.0)


def danger_color() -> NSColor:
    return NSColor.colorWithCalibratedRed_green_blue_alpha_(0.78, 0.20, 0.20, 1.0)


def title_font() -> NSFont:
    return NSFont.systemFontOfSize_weight_(28.0, 0.56)


def section_title_font() -> NSFont:
    return NSFont.systemFontOfSize_weight_(22.0, 0.52)


def body_font() -> NSFont:
    return NSFont.systemFontOfSize_(14.0)


def strong_font() -> NSFont:
    return NSFont.systemFontOfSize_weight_(14.0, 0.56)


def meta_font() -> NSFont:
    return NSFont.systemFontOfSize_(12.0)


def sidebar_item_font() -> NSFont:
    return NSFont.systemFontOfSize_weight_(13.5, 0.40)


def sidebar_brand_font() -> NSFont:
    return NSFont.systemFontOfSize_weight_(22.0, 0.70)


def stat_chip_font() -> NSFont:
    return NSFont.systemFontOfSize_weight_(13.0, 0.48)


def banner_title_font() -> NSFont:
    return NSFont.systemFontOfSize_weight_(20.0, 0.56)


def day_header_font() -> NSFont:
    return NSFont.systemFontOfSize_weight_(11.0, 0.62)


def timestamp_font() -> NSFont:
    return NSFont.systemFontOfSize_(13.0)
