import Foundation
import Infra
import Testing

struct HistoryStoreTests {
    @Test func historyCRUDAndStats() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = dir.appendingPathComponent("history.sqlite3")

        let store = try SQLiteHistoryStore(dbURL: db)
        try store.add(rawText: "hello", finalText: "Hello.", detectedLanguage: "en", confidence: 0.9, outputMode: "english", sourceApp: "Notes")
        try store.add(rawText: "bhai kya", finalText: "Bhai kya?", detectedLanguage: "hi", confidence: 0.8, outputMode: "hinglish_roman", sourceApp: "Slack")

        let rows = try store.search(query: "bhai", limit: 10, offset: 0)
        #expect(rows.count == 1)
        #expect(rows[0].sourceApp == "Slack")

        let stats = try store.stats()
        #expect(stats.totalCount == 2)
        #expect(!stats.topSourceApp.isEmpty)

        try store.delete(id: rows[0].id)
        let afterDelete = try store.search(query: "", limit: 10, offset: 0)
        #expect(afterDelete.count == 1)
    }
}
