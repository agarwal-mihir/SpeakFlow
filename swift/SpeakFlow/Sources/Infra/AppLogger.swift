import Foundation

public enum AppLogger {
    private static let queue = DispatchQueue(label: "com.speakflow.logger", qos: .utility)

    public static func info(_ message: String) {
        write(level: "INFO", message: message)
    }

    public static func error(_ message: String) {
        write(level: "ERROR", message: message)
    }

    private static func write(level: String, message: String) {
        queue.async {
            do {
                try ensureAppSupportDirectories()
                let logFile = SpeakFlowPaths.logsDir.appendingPathComponent("app.log")
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let timestamp = formatter.string(from: Date())
                let line = "\(timestamp) [\(level)] \(message)\n"
                let data = Data(line.utf8)
                if FileManager.default.fileExists(atPath: logFile.path) {
                    let handle = try FileHandle(forWritingTo: logFile)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } else {
                    try data.write(to: logFile, options: .atomic)
                }
            } catch {
                // Never crash logging path.
            }
        }
    }
}
