from pathlib import Path

from whisper_flow.history import TranscriptHistoryStore


def test_history_store_persists_and_reads(tmp_path: Path) -> None:
    db_path = tmp_path / "history.sqlite3"
    store = TranscriptHistoryStore(db_path=db_path)

    store.add(
        raw_text="bhai kya haal",
        final_text="bhai kya haal.",
        detected_language="hi",
        confidence=0.88,
        output_mode="hinglish_roman",
        source_app="ChatGPT",
    )

    assert store.total_count() == 1
    recent = store.recent(limit=5)
    assert len(recent) == 1
    assert recent[0].id > 0
    assert recent[0].final_text == "bhai kya haal."
    assert recent[0].source_app == "ChatGPT"

    searched = store.search("kya haal", limit=5, offset=0)
    assert len(searched) == 1
    assert searched[0].id == recent[0].id

    stats = store.stats()
    assert stats["total_count"] == 1
    assert stats["latest_source_app"] == "ChatGPT"
    assert stats["top_source_app"] == "ChatGPT"

    store.delete(recent[0].id)
    assert store.total_count() == 0


def test_search_supports_offset_and_source_app_query(tmp_path: Path) -> None:
    store = TranscriptHistoryStore(db_path=tmp_path / "history.sqlite3")

    store.add("one", "one.", "en", 0.9, "english", "Slack")
    store.add("two", "two.", "en", 0.9, "english", "Discord")
    store.add("three", "three.", "en", 0.9, "english", "Slack")

    page = store.search("", limit=1, offset=1)
    assert len(page) == 1
    assert page[0].raw_text == "two"

    source_match = store.search("Slack", limit=10, offset=0)
    assert len(source_match) == 2


def test_stats_for_empty_db_returns_unknowns(tmp_path: Path) -> None:
    store = TranscriptHistoryStore(db_path=tmp_path / "history.sqlite3")

    stats = store.stats()

    assert stats["total_count"] == 0
    assert stats["latest_created_at"] == ""
    assert stats["latest_source_app"] == "Unknown"
    assert stats["top_source_app"] == "Unknown"
    assert stats["top_source_app_count"] == 0


def test_delete_missing_id_is_safe(tmp_path: Path) -> None:
    store = TranscriptHistoryStore(db_path=tmp_path / "history.sqlite3")
    store.add("raw", "final", "en", 0.5, "english", None)

    store.delete(999999)

    assert store.total_count() == 1
