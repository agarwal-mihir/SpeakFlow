import AppKit
import Foundation

@MainActor
final class StatusBarController {
    private let item: NSStatusItem
    private weak var runtime: AppRuntime?
    private let onOpen: () -> Void

    init(runtime: AppRuntime, onOpen: @escaping () -> Void) {
        self.runtime = runtime
        self.onOpen = onOpen
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "SF"
        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu(title: "SpeakFlow")

        let open = NSMenuItem(title: "Open SpeakFlow", action: #selector(openMain), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let runtimeState = runtime?.state.rawValue ?? "Idle"
        let status = NSMenuItem(title: "Status: \(runtimeState)", action: nil, keyEquivalent: "")
        menu.addItem(status)

        let perms = NSMenuItem(
            title: (runtime?.permissionState.allGranted ?? false) ? "Permissions: Ready" : "Permissions: Missing",
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(perms)

        let toggleTitle = (runtime?.serviceEnabled ?? false) ? "Stop Service" : "Start Service"
        let toggle = NSMenuItem(title: toggleTitle, action: #selector(toggleService), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
    }

    @objc private func openMain() {
        onOpen()
    }

    @objc private func toggleService() {
        guard let runtime else { return }
        runtime.setServiceEnabled(!runtime.serviceEnabled)
        rebuildMenu()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
