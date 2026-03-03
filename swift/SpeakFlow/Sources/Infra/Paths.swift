import Foundation

public enum SpeakFlowPaths {
    public static let appSupport = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/SpeakFlow", isDirectory: true)
    public static let configJSON = appSupport.appendingPathComponent("config.json")
    public static let historySQLite = appSupport.appendingPathComponent("history.sqlite3")
    public static let logsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/SpeakFlow", isDirectory: true)
    public static let launchAgents = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    public static let launchAgentPlist = launchAgents.appendingPathComponent("com.speakflow.desktop.plist")
}

public func ensureAppSupportDirectories() throws {
    try FileManager.default.createDirectory(at: SpeakFlowPaths.appSupport, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: SpeakFlowPaths.logsDir, withIntermediateDirectories: true)
}
