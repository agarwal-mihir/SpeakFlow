import Domain
import Foundation
import SQLite3

public final class SQLiteHistoryStore: HistoryStoreProtocol {
    private let dbURL: URL
    private let queue = DispatchQueue(label: "com.speakflow.history", qos: .userInitiated)

    public init(dbURL: URL = SpeakFlowPaths.historySQLite) throws {
        self.dbURL = dbURL
        try ensureAppSupportDirectories()
        try initializeSchema()
    }

    public func add(rawText: String, finalText: String, detectedLanguage: String?, confidence: Double?, outputMode: String, sourceApp: String?) throws {
        try queue.sync {
            let sql = """
            INSERT INTO transcripts (
              created_at, raw_text, final_text, detected_language, confidence, output_mode, source_app
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """
            let now = ISO8601DateFormatter().string(from: Date())
            try withDB { db in
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    throw SpeakFlowError.storageFailure("prepare insert failed")
                }
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, (now as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, (rawText as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, (finalText as NSString).utf8String, -1, SQLITE_TRANSIENT)
                if let detectedLanguage {
                    sqlite3_bind_text(stmt, 4, (detectedLanguage as NSString).utf8String, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 4)
                }
                if let confidence {
                    sqlite3_bind_double(stmt, 5, confidence)
                } else {
                    sqlite3_bind_null(stmt, 5)
                }
                sqlite3_bind_text(stmt, 6, (outputMode as NSString).utf8String, -1, SQLITE_TRANSIENT)
                if let sourceApp {
                    sqlite3_bind_text(stmt, 7, (sourceApp as NSString).utf8String, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 7)
                }
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw SpeakFlowError.storageFailure("insert failed")
                }
            }
        }
    }

    public func search(query: String, limit: Int, offset: Int) throws -> [HistoryRecord] {
        try queue.sync {
            var records: [HistoryRecord] = []
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let sql: String
            if trimmed.isEmpty {
                sql = """
                SELECT id, created_at, raw_text, final_text, detected_language, confidence, output_mode, source_app
                FROM transcripts ORDER BY id DESC LIMIT ? OFFSET ?
                """
            } else {
                sql = """
                SELECT id, created_at, raw_text, final_text, detected_language, confidence, output_mode, source_app
                FROM transcripts
                WHERE raw_text LIKE ? OR final_text LIKE ? OR COALESCE(source_app, '') LIKE ?
                ORDER BY id DESC LIMIT ? OFFSET ?
                """
            }

            try withDB { db in
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    throw SpeakFlowError.storageFailure("prepare search failed")
                }
                defer { sqlite3_finalize(stmt) }

                if trimmed.isEmpty {
                    sqlite3_bind_int(stmt, 1, Int32(limit))
                    sqlite3_bind_int(stmt, 2, Int32(offset))
                } else {
                    let like = "%\(trimmed)%"
                    sqlite3_bind_text(stmt, 1, (like as NSString).utf8String, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 2, (like as NSString).utf8String, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 3, (like as NSString).utf8String, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int(stmt, 4, Int32(limit))
                    sqlite3_bind_int(stmt, 5, Int32(offset))
                }

                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = Int(sqlite3_column_int(stmt, 0))
                    let createdAt = stringColumn(stmt, 1)
                    let rawText = stringColumn(stmt, 2)
                    let finalText = stringColumn(stmt, 3)
                    let detectedLanguage = optionalStringColumn(stmt, 4)
                    let confidence = sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 5)
                    let outputMode = stringColumn(stmt, 6)
                    let sourceApp = optionalStringColumn(stmt, 7)
                    records.append(
                        HistoryRecord(
                            id: id,
                            createdAt: createdAt,
                            rawText: rawText,
                            finalText: finalText,
                            detectedLanguage: detectedLanguage,
                            confidence: confidence,
                            outputMode: outputMode,
                            sourceApp: sourceApp
                        )
                    )
                }
            }
            return records
        }
    }

    public func delete(id: Int) throws {
        try queue.sync {
            try withDB { db in
                var stmt: OpaquePointer?
                let sql = "DELETE FROM transcripts WHERE id = ?"
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    throw SpeakFlowError.storageFailure("prepare delete failed")
                }
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_int(stmt, 1, Int32(id))
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw SpeakFlowError.storageFailure("delete failed")
                }
            }
        }
    }

    public func stats() throws -> HistoryStats {
        try queue.sync {
            var total = 0
            var latestCreated = ""
            var latestApp = "Unknown"
            var topApp = "Unknown"
            var topCount = 0

            try withDB { db in
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM transcripts", -1, &stmt, nil) == SQLITE_OK else {
                    throw SpeakFlowError.storageFailure("prepare total failed")
                }
                defer { sqlite3_finalize(stmt) }
                if sqlite3_step(stmt) == SQLITE_ROW {
                    total = Int(sqlite3_column_int(stmt, 0))
                }

                var latest: OpaquePointer?
                guard sqlite3_prepare_v2(db, "SELECT created_at, COALESCE(source_app, 'Unknown') FROM transcripts ORDER BY id DESC LIMIT 1", -1, &latest, nil) == SQLITE_OK else {
                    throw SpeakFlowError.storageFailure("prepare latest failed")
                }
                defer { sqlite3_finalize(latest) }
                if sqlite3_step(latest) == SQLITE_ROW {
                    latestCreated = stringColumn(latest, 0)
                    latestApp = stringColumn(latest, 1)
                }

                var top: OpaquePointer?
                guard sqlite3_prepare_v2(db, "SELECT COALESCE(source_app, 'Unknown') as app_name, COUNT(*) as c FROM transcripts GROUP BY app_name ORDER BY c DESC LIMIT 1", -1, &top, nil) == SQLITE_OK else {
                    throw SpeakFlowError.storageFailure("prepare top app failed")
                }
                defer { sqlite3_finalize(top) }
                if sqlite3_step(top) == SQLITE_ROW {
                    topApp = stringColumn(top, 0)
                    topCount = Int(sqlite3_column_int(top, 1))
                }
            }

            return HistoryStats(
                totalCount: total,
                latestCreatedAt: latestCreated,
                latestSourceApp: latestApp,
                topSourceApp: topApp,
                topSourceAppCount: topCount
            )
        }
    }

    private func initializeSchema() throws {
        try withDB { db in
            let schema = """
            CREATE TABLE IF NOT EXISTS transcripts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at TEXT NOT NULL,
                raw_text TEXT NOT NULL,
                final_text TEXT NOT NULL,
                detected_language TEXT,
                confidence REAL,
                output_mode TEXT NOT NULL,
                source_app TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_transcripts_created_at ON transcripts(created_at DESC);
            """
            guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else {
                throw SpeakFlowError.storageFailure("schema init failed")
            }
        }
    }

    private func withDB<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let db else {
            throw SpeakFlowError.storageFailure("open sqlite failed")
        }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA busy_timeout=5000;", nil, nil, nil)
        return try body(db)
    }
}

private func stringColumn(_ stmt: OpaquePointer?, _ index: Int32) -> String {
    guard let c = sqlite3_column_text(stmt, index) else { return "" }
    return String(cString: c)
}

private func optionalStringColumn(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
    guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
    return stringColumn(stmt, index)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
