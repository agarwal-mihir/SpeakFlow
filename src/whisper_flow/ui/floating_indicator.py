from __future__ import annotations

from enum import Enum
from typing import Callable

import objc
from AppKit import (
    NSBackingStoreBuffered,
    NSColor,
    NSFloatingWindowLevel,
    NSPanel,
    NSScreen,
    NSTextField,
    NSView,
    NSWindowCollectionBehaviorCanJoinAllSpaces,
    NSWindowCollectionBehaviorFullScreenAuxiliary,
    NSWindowStyleMaskBorderless,
    NSWindowStyleMaskNonactivatingPanel,
)
from Foundation import NSObject, NSTimer

from whisper_flow.ui import theme
from whisper_flow.ui.components import activate, pin_edges, with_autolayout


class IndicatorState(str, Enum):
    HIDDEN = "hidden"
    RECORDING = "recording"
    TRANSCRIBING = "transcribing"
    DONE = "done"
    ERROR = "error"


class FloatingIndicatorController(NSObject):
    def initWithHideDelayMs_enabled_onMove_(  # type: ignore[no-untyped-def]
        self,
        hide_delay_ms: int,
        enabled: bool,
        on_move: Callable[[float, float], None] | None,
    ):
        self = objc.super(FloatingIndicatorController, self).init()
        if self is None:
            return None

        self._hide_delay_ms = max(200, int(hide_delay_ms))
        self._enabled = bool(enabled)
        self._on_move = on_move

        self._panel = None
        self._status_label: NSTextField | None = None
        self._meter_track: NSView | None = None
        self._meter_fill: NSView | None = None
        self._meter_fill_width = None

        self._state = IndicatorState.HIDDEN
        self._hide_timer = None
        self._origin_x: float | None = None
        self._origin_y: float | None = None
        self._setting_origin = False
        self._last_level = 0.0
        return self

    @property
    def state(self) -> IndicatorState:
        return self._state

    def set_enabled(self, enabled: bool) -> None:
        self._enabled = bool(enabled)
        if not self._enabled:
            self.hide()

    def set_hide_delay_ms(self, hide_delay_ms: int) -> None:
        self._hide_delay_ms = max(200, int(hide_delay_ms))

    def set_origin(self, x: float | None, y: float | None) -> None:
        if x is None or y is None:
            self._origin_x = None
            self._origin_y = None
            return

        self._origin_x = float(x)
        self._origin_y = float(y)
        if self._panel is not None:
            self._setting_origin = True
            try:
                self._panel.setFrameOrigin_((self._origin_x, self._origin_y))
            finally:
                self._setting_origin = False

    def current_origin(self) -> tuple[float, float] | None:
        if self._panel is None:
            if self._origin_x is None or self._origin_y is None:
                return None
            return (self._origin_x, self._origin_y)

        frame = self._panel.frame()
        return (float(frame.origin.x), float(frame.origin.y))

    def show_recording(self, level: float = 0.0) -> None:
        if not self._enabled:
            return
        self._ensure_panel()
        self._cancel_hide_timer()
        self._state = IndicatorState.RECORDING
        self._set_status("Recording", theme.danger_color())
        self.update_meter(level)
        self._show_panel()

    def show_transcribing(self) -> None:
        if not self._enabled:
            return
        self._ensure_panel()
        self._cancel_hide_timer()
        self._state = IndicatorState.TRANSCRIBING
        self._set_status("Transcribing", theme.secondary_text_color())
        self.update_meter(0.0)
        self._show_panel()

    def show_done(self, message: str = "Done") -> None:
        if not self._enabled:
            return
        self._ensure_panel()
        self._cancel_hide_timer()
        self._state = IndicatorState.DONE
        self._set_status(message, theme.success_color())
        self.update_meter(0.0)
        self._show_panel()
        self._schedule_hide()

    def show_error(self, message: str) -> None:
        if not self._enabled:
            return
        self._ensure_panel()
        self._cancel_hide_timer()
        self._state = IndicatorState.ERROR
        text = message.strip() or "Error"
        if len(text) > 72:
            text = f"{text[:69]}..."
        self._set_status(text, theme.danger_color())
        self.update_meter(0.0)
        self._show_panel()
        self._schedule_hide()

    def hide(self) -> None:
        self._cancel_hide_timer()
        if self._panel is not None:
            self._panel.orderOut_(None)
        self._state = IndicatorState.HIDDEN

    def update_meter(self, level: float) -> None:
        if self._meter_fill_width is None or self._meter_track is None:
            return

        bounded = max(0.0, min(1.0, float(level)))
        self._last_level = bounded
        if self._state != IndicatorState.RECORDING:
            bounded = 0.0

        self._meter_track.layoutSubtreeIfNeeded()
        track_width = float(self._meter_track.frame().size.width) if self._meter_track.frame().size.width else 240.0
        min_width = 3.0
        width = min_width + ((track_width - min_width) * bounded)
        self._meter_fill_width.setConstant_(width)

    def hideTimerFired_(self, _timer):  # type: ignore[no-untyped-def]
        self._hide_timer = None
        self.hide()

    def windowDidMove_(self, _notification):  # type: ignore[no-untyped-def]
        if self._panel is None or self._setting_origin:
            return
        if self._on_move is None:
            return
        frame = self._panel.frame()
        x = float(frame.origin.x)
        y = float(frame.origin.y)
        self._origin_x = x
        self._origin_y = y
        self._on_move(x, y)

    def _schedule_hide(self) -> None:
        self._cancel_hide_timer()
        self._hide_timer = NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            max(0.2, self._hide_delay_ms / 1000.0),
            self,
            "hideTimerFired:",
            None,
            False,
        )

    def _cancel_hide_timer(self) -> None:
        if self._hide_timer is not None:
            self._hide_timer.invalidate()
            self._hide_timer = None

    def _show_panel(self) -> None:
        if self._panel is None:
            return
        if self._origin_x is None or self._origin_y is None:
            self._position_default()
        else:
            self._setting_origin = True
            try:
                self._panel.setFrameOrigin_((self._origin_x, self._origin_y))
            finally:
                self._setting_origin = False
        self._panel.orderFrontRegardless()

    def _set_status(self, text: str, color: NSColor) -> None:
        if self._status_label is None:
            return
        self._status_label.setStringValue_(text)
        self._status_label.setTextColor_(color)

    def _position_default(self) -> None:
        if self._panel is None:
            return
        screen = NSScreen.mainScreen()
        if screen is None:
            self._origin_x = 40.0
            self._origin_y = 40.0
        else:
            visible = screen.visibleFrame()
            panel_frame = self._panel.frame()
            self._origin_x = float(visible.origin.x) + ((float(visible.size.width) - float(panel_frame.size.width)) / 2.0)
            self._origin_y = float(visible.origin.y) + 60.0

        self._setting_origin = True
        try:
            self._panel.setFrameOrigin_((self._origin_x, self._origin_y))
        finally:
            self._setting_origin = False

    def _ensure_panel(self) -> None:
        if self._panel is not None:
            return

        frame = ((0.0, 0.0), (320.0, 68.0))
        mask = NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
        panel = NSPanel.alloc().initWithContentRect_styleMask_backing_defer_(
            frame,
            mask,
            NSBackingStoreBuffered,
            False,
        )
        panel.setFloatingPanel_(True)
        panel.setHidesOnDeactivate_(False)
        panel.setReleasedWhenClosed_(False)
        panel.setOpaque_(False)
        panel.setBackgroundColor_(NSColor.clearColor())
        panel.setHasShadow_(True)
        panel.setMovableByWindowBackground_(True)
        panel.setLevel_(NSFloatingWindowLevel)
        panel.setCollectionBehavior_(
            NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary
        )
        panel.setDelegate_(self)

        content = panel.contentView()
        root = with_autolayout(NSView.alloc().init())
        root.setWantsLayer_(True)
        root.layer().setCornerRadius_(22.0)
        root.layer().setBackgroundColor_(NSColor.colorWithCalibratedRed_green_blue_alpha_(0.08, 0.08, 0.10, 0.94).CGColor())
        content.addSubview_(root)
        pin_edges(root, content, inset=0.0)

        status_label = with_autolayout(NSTextField.labelWithString_("Recording"))
        status_label.setFont_(theme.strong_font())
        status_label.setTextColor_(theme.danger_color())

        meter_track = with_autolayout(NSView.alloc().init())
        meter_track.setWantsLayer_(True)
        meter_track.layer().setCornerRadius_(3.0)
        meter_track.layer().setBackgroundColor_(NSColor.colorWithCalibratedRed_green_blue_alpha_(0.22, 0.22, 0.25, 1.0).CGColor())

        meter_fill = with_autolayout(NSView.alloc().init())
        meter_fill.setWantsLayer_(True)
        meter_fill.layer().setCornerRadius_(3.0)
        meter_fill.layer().setBackgroundColor_(NSColor.colorWithCalibratedRed_green_blue_alpha_(0.96, 0.28, 0.28, 1.0).CGColor())

        root.addSubview_(status_label)
        root.addSubview_(meter_track)
        meter_track.addSubview_(meter_fill)

        meter_fill_width = meter_fill.widthAnchor().constraintEqualToConstant_(3.0)
        activate(
            [
                status_label.leadingAnchor().constraintEqualToAnchor_constant_(root.leadingAnchor(), 16.0),
                status_label.trailingAnchor().constraintEqualToAnchor_constant_(root.trailingAnchor(), -16.0),
                status_label.topAnchor().constraintEqualToAnchor_constant_(root.topAnchor(), 12.0),
                meter_track.leadingAnchor().constraintEqualToAnchor_constant_(root.leadingAnchor(), 16.0),
                meter_track.trailingAnchor().constraintEqualToAnchor_constant_(root.trailingAnchor(), -16.0),
                meter_track.topAnchor().constraintEqualToAnchor_constant_(status_label.bottomAnchor(), 10.0),
                meter_track.heightAnchor().constraintEqualToConstant_(8.0),
                meter_track.bottomAnchor().constraintEqualToAnchor_constant_(root.bottomAnchor(), -12.0),
                meter_fill.leadingAnchor().constraintEqualToAnchor_(meter_track.leadingAnchor()),
                meter_fill.topAnchor().constraintEqualToAnchor_(meter_track.topAnchor()),
                meter_fill.bottomAnchor().constraintEqualToAnchor_(meter_track.bottomAnchor()),
                meter_fill_width,
            ]
        )

        self._panel = panel
        self._status_label = status_label
        self._meter_track = meter_track
        self._meter_fill = meter_fill
        self._meter_fill_width = meter_fill_width


__all__ = ["FloatingIndicatorController", "IndicatorState"]
