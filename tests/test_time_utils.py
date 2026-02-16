from __future__ import annotations

from datetime import datetime, timezone

from whisper_flow.time_utils import (
    format_local_datetime,
    format_local_time_12h,
    local_date_key,
    parse_stored_timestamp,
)


def test_parse_stored_timestamp_handles_utc_offset() -> None:
    value = "2026-02-08T10:11:12+00:00"
    parsed = parse_stored_timestamp(value)

    assert parsed is not None
    expected = datetime(2026, 2, 8, 10, 11, 12, tzinfo=timezone.utc).astimezone()
    assert parsed == expected


def test_parse_stored_timestamp_handles_naive_iso() -> None:
    value = "2026-02-08T10:11:12"
    parsed = parse_stored_timestamp(value)

    assert parsed is not None
    assert parsed.tzinfo is None
    assert parsed.strftime("%Y-%m-%d %H:%M:%S") == "2026-02-08 10:11:12"


def test_format_local_datetime_formats_parsed_value() -> None:
    value = "2026-02-08T10:11:12+00:00"
    expected = datetime(2026, 2, 8, 10, 11, 12, tzinfo=timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M:%S")

    assert format_local_datetime(value) == expected


def test_format_local_time_12h_formats_parsed_value() -> None:
    value = "2026-02-08T10:11:12+00:00"
    expected = datetime(2026, 2, 8, 10, 11, 12, tzinfo=timezone.utc).astimezone().strftime("%I:%M %p")

    assert format_local_time_12h(value) == expected


def test_local_date_key_uses_local_calendar_day() -> None:
    value = "2026-02-08T10:11:12+00:00"
    expected = datetime(2026, 2, 8, 10, 11, 12, tzinfo=timezone.utc).astimezone().strftime("%Y-%m-%d")

    assert local_date_key(value) == expected


def test_invalid_timestamp_falls_back_without_crashing() -> None:
    value = "not-a-time"
    assert parse_stored_timestamp(value) is None
    assert format_local_datetime(value) == "not-a-time"
    assert format_local_time_12h(value) == ""
    assert local_date_key(value) == "not-a-time"
