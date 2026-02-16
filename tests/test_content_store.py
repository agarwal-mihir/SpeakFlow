from pathlib import Path

from whisper_flow.content_store import ContentStore, DictionaryEntry, NoteEntry, SnippetEntry, StyleProfile


def test_dictionary_crud_and_search(tmp_path: Path) -> None:
    store = ContentStore(db_path=tmp_path / "content.sqlite3")

    entry_id = store.upsert_dictionary(DictionaryEntry(trigger="brb", replacement="be right back"))
    rows = store.list_dictionary("br", limit=20, offset=0)

    assert len(rows) == 1
    assert rows[0].id == entry_id

    store.upsert_dictionary(DictionaryEntry(id=entry_id, trigger="brb", replacement="be right back!"))
    rows = store.list_dictionary("right back!", limit=20, offset=0)
    assert rows[0].replacement == "be right back!"

    store.delete_dictionary(entry_id)
    assert store.list_dictionary("", limit=20, offset=0) == []


def test_snippet_crud_and_shortcut_uniqueness(tmp_path: Path) -> None:
    store = ContentStore(db_path=tmp_path / "content.sqlite3")

    first = store.upsert_snippet(SnippetEntry(title="Greeting", body="Hello there", shortcut="greet"))
    second = store.upsert_snippet(SnippetEntry(title="Intro", body="I am Mihir", shortcut=""))

    rows = store.list_snippets("", limit=20, offset=0)
    assert {row.id for row in rows} == {first, second}

    store.upsert_snippet(SnippetEntry(id=first, title="Greeting", body="Hello there!", shortcut="greet"))
    assert store.list_snippets("there!", limit=20, offset=0)[0].id == first

    store.delete_snippet(second)
    remaining = store.list_snippets("", limit=20, offset=0)
    assert len(remaining) == 1


def test_style_default_invariant(tmp_path: Path) -> None:
    store = ContentStore(db_path=tmp_path / "content.sqlite3")

    formal = store.upsert_style(StyleProfile(name="Formal", instructions="Keep formal", is_default=True))
    casual = store.upsert_style(StyleProfile(name="Casual", instructions="Keep casual", is_default=False))

    rows = store.list_styles("", limit=20, offset=0)
    assert [row.id for row in rows if row.is_default] == [formal]

    store.set_default_style(casual)
    rows = store.list_styles("", limit=20, offset=0)
    assert [row.id for row in rows if row.is_default] == [casual]

    store.delete_style(casual)
    rows = store.list_styles("", limit=20, offset=0)
    assert len(rows) == 1
    assert rows[0].is_default is True


def test_notes_crud_pin_and_stats(tmp_path: Path) -> None:
    store = ContentStore(db_path=tmp_path / "content.sqlite3")

    note_id = store.upsert_note(NoteEntry(title="Plan", body="Ship UI", pinned=False))
    store.upsert_note(NoteEntry(id=note_id, title="Plan", body="Ship modern UI", pinned=True))

    notes = store.list_notes("modern", limit=20, offset=0)
    assert len(notes) == 1
    assert notes[0].pinned is True

    stats = store.stats()
    assert stats["note_count"] == 1
    assert stats["total_count"] == 1

    store.delete_note(note_id)
    assert store.list_notes("", limit=20, offset=0) == []
