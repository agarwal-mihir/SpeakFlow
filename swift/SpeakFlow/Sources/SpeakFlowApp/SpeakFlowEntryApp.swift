import AppLayer
import SwiftUI

@main
struct SpeakFlowEntryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var runtime = AppRuntime()

    var body: some Scene {
        WindowGroup("SpeakFlow") {
            RootView(runtime: runtime)
                .background(
                    WindowAccessor { window in
                        appDelegate.runtime = runtime
                        appDelegate.window = window
                        window.delegate = appDelegate
                        runtime.configureStatusBar {
                            appDelegate.openMainWindow()
                        }
                    }
                )
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Open SpeakFlow") {
                    appDelegate.openMainWindow()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}
