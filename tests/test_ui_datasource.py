from whisper_flow.history import HistoryRecord
from whisper_flow.ui import HistoryTableDataSource


class FakeColumn:
    def __init__(self, identifier: str) -> None:
        self._identifier = identifier

    def identifier(self) -> str:
        return self._identifier


def test_history_table_data_source_maps_record_fields() -> None:
    data_source = HistoryTableDataSource.alloc().init()
    record = HistoryRecord(
        id=1,
        created_at="2026-02-08T10:11:12",
        raw_text="hello",
        final_text="Hello.",
        detected_language="en",
        confidence=0.9,
        output_mode="english",
        source_app=None,
    )
    data_source.set_records([record])

    assert data_source.numberOfRowsInTableView_(None) == 1
    assert data_source.tableView_objectValueForTableColumn_row_(None, FakeColumn("time"), 0) == "2026-02-08 10:11:12"
    assert data_source.tableView_objectValueForTableColumn_row_(None, FakeColumn("app"), 0) == "Unknown"
    assert data_source.tableView_objectValueForTableColumn_row_(None, FakeColumn("text"), 0) == "Hello."


def test_history_table_data_source_handles_out_of_bounds_row() -> None:
    data_source = HistoryTableDataSource.alloc().init()
    data_source.set_records([])

    assert data_source.tableView_objectValueForTableColumn_row_(None, FakeColumn("text"), 0) == ""
