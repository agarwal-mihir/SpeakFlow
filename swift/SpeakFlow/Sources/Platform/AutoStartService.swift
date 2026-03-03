import Domain
import Foundation
import Infra

public final class AutoStartService: AutoStartServiceProtocol {
    private let label = "com.speakflow.desktop"

    public init() {}

    public func installLaunchAgent() throws {
        try ensureAppSupportDirectories()
        try FileManager.default.createDirectory(at: SpeakFlowPaths.launchAgents, withIntermediateDirectories: true)

        let executable = Bundle.main.bundlePath + "/Contents/MacOS/" + (Bundle.main.executableURL?.lastPathComponent ?? "SpeakFlowApp")
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: SpeakFlowPaths.launchAgentPlist)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootstrap", "gui/\(getuid())", SpeakFlowPaths.launchAgentPlist.path]
        try? process.run()
        process.waitUntilExit()
    }

    public func uninstallLaunchAgent() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())", SpeakFlowPaths.launchAgentPlist.path]
        try? process.run()
        process.waitUntilExit()
        try? FileManager.default.removeItem(at: SpeakFlowPaths.launchAgentPlist)
    }
}
