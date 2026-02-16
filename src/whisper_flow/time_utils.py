from __future__ import annotations

from datetime import datetime


def parse_stored_timestamp(value: str) -> datetime | None:
    if not value:
        return None

    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        try:
            parsed = datetime.strptime(value, "%Y-%m-%d %H:%M:%S")
        except ValueError:
            return None

    if parsed.tzinfo is not None:
        return parsed.astimezone()
    return parsed


def format_local_datetime(value: str, fmt: str = "%Y-%m-%d %H:%M:%S") -> str:
    parsed = parse_stored_timestamp(value)
    if parsed is None:
        return value.replace("T", " ")[:19]
    return parsed.strftime(fmt)


def format_local_time_12h(value: str) -> str:
    parsed = parse_stored_timestamp(value)
    if parsed is None:
        return value[11:16]
    return parsed.strftime("%I:%M %p")


def local_date_key(value: str) -> str:
    parsed = parse_stored_timestamp(value)
    if parsed is None:
        return value[:10]
    return parsed.strftime("%Y-%m-%d")
