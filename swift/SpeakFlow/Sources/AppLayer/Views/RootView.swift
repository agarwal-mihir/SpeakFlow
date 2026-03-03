import Domain
import SwiftUI

private enum SidebarTab: String, CaseIterable, Identifiable {
    case home
    case history
    case settings
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .history: return "History"
        case .settings: return "Settings"
        case .permissions: return "Permissions"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        case .permissions: return "checkmark.shield"
        }
    }
}

public struct RootView: View {
    @ObservedObject var runtime: AppRuntime
    @State private var selectedTab: SidebarTab = .home
    @State private var settingsDraft = SettingsDraft()

    public init(runtime: AppRuntime) {
        self.runtime = runtime
    }

    public var body: some View {
        ZStack {
            HStack(spacing: 0) {
                sidebar
                Divider()
                mainContent
            }
            .frame(minWidth: 980, minHeight: 640)
            .background(Color(nsColor: .windowBackgroundColor))

            if runtime.requiresPermissionOnboarding {
                onboardingOverlay
            }
        }
        .onAppear {
            refreshSettingsDraft()
            if runtime.requiresPermissionOnboarding {
                selectedTab = .permissions
            }
        }
        .onChange(of: runtime.requiresPermissionOnboarding) { _, missing in
            if missing {
                selectedTab = .permissions
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SpeakFlow")
                    .font(.system(size: 30, weight: .bold))
                Text("Local dictation")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)

            VStack(spacing: 8) {
                ForEach(SidebarTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 16)
                            Text(tab.title)
                                .font(.system(size: 14, weight: .semibold))
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedTab == tab ? Color(nsColor: .selectedControlColor).opacity(0.18) : .clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            statusCard
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
        }
        .frame(width: 230)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(runtime.state.rawValue)
                .font(.system(size: 14, weight: .bold))
            Text(runtime.permissionState.allGranted ? "Permissions ready" : "Permissions missing")
                .font(.system(size: 12))
                .foregroundStyle(runtime.permissionState.allGranted ? .green : .orange)
            Toggle("Service", isOn: Binding(
                get: { runtime.serviceEnabled },
                set: { runtime.setServiceEnabled($0) }
            ))
            .toggleStyle(.switch)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        )
    }

    @ViewBuilder
    private var mainContent: some View {
        switch selectedTab {
        case .home:
            HomeView(runtime: runtime, onOpenSettings: {
                selectedTab = .settings
            })
        case .history:
            HistoryView(runtime: runtime)
        case .settings:
            SettingsView(
                runtime: runtime,
                draft: $settingsDraft,
                onRefreshDraft: refreshSettingsDraft
            )
        case .permissions:
            PermissionsView(runtime: runtime)
        }
    }

    private var onboardingOverlay: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text("Permission Setup Required")
                    .font(.system(size: 24, weight: .bold))
                Text("Grant all permissions to enable dictation, global hotkeys, and paste insertion.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                PermissionsSummaryGrid(runtime: runtime)

                HStack {
                    Button("Open Permissions Page") {
                        selectedTab = .permissions
                    }
                    .buttonStyle(.bordered)

                    Button("Re-check") {
                        runtime.refreshPermissions()
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Text(runtime.permissionState.allGranted ? "Ready" : "Blocked until all permissions are granted")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(runtime.permissionState.allGranted ? .green : .orange)
                }
            }
            .padding(22)
            .frame(width: 640)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
            )
        }
    }

    private func refreshSettingsDraft() {
        settingsDraft = SettingsDraft(config: runtime.config, hasGroqKey: runtime.hasGroqAPIKey())
    }
}

private struct HomeView: View {
    @ObservedObject var runtime: AppRuntime
    var onOpenSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Welcome back")
                            .font(.system(size: 34, weight: .bold))
                        Text("Hold Fn to dictate in any app.")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(runtime.state.rawValue, systemImage: "waveform")
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
                }

                quickStatusCard
                controlsCard
                activityCard
            }
            .padding(24)
        }
    }

    private var quickStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dictation Status")
                .font(.system(size: 18, weight: .bold))
            HStack(spacing: 16) {
                statusChip(title: "Service", value: runtime.serviceEnabled ? "On" : "Off", good: runtime.serviceEnabled)
                statusChip(title: "Permissions", value: runtime.permissionState.allGranted ? "Ready" : "Missing", good: runtime.permissionState.allGranted)
                statusChip(title: "History", value: "\(runtime.historyStats.totalCount) saved", good: true)
            }
            if !runtime.lastError.isEmpty {
                Text(runtime.lastError)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
                    .padding(.top, 2)
            }
        }
        .cardStyle()
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Controls")
                .font(.system(size: 18, weight: .bold))
            Toggle("Service enabled", isOn: Binding(
                get: { runtime.serviceEnabled },
                set: { runtime.setServiceEnabled($0) }
            ))
            Toggle("Floating indicator", isOn: Binding(
                get: { runtime.config.floatingIndicatorEnabled },
                set: { runtime.setFloatingIndicatorEnabled($0) }
            ))
            Picker("Hotkey", selection: Binding(
                get: { runtime.config.hotkeyMode },
                set: { runtime.setHotkeyMode($0) }
            )) {
                Text("Fn hold").tag(HotkeyMode.fnHold)
                Text("Fn + Space hold").tag(HotkeyMode.fnSpaceHold)
            }
            .pickerStyle(.segmented)
            Button("Open full settings", action: onOpenSettings)
                .buttonStyle(.borderedProminent)
        }
        .cardStyle()
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Activity")
                .font(.system(size: 18, weight: .bold))
            Text("Latest app: \(runtime.historyStats.latestSourceApp)")
                .font(.system(size: 14))
            Text("Top app: \(runtime.historyStats.topSourceApp) (\(runtime.historyStats.topSourceAppCount))")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private func statusChip(title: String, value: String, good: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(good ? Color.primary : Color.orange)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct HistoryView: View {
    @ObservedObject var runtime: AppRuntime
    @State private var selectedID: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("History")
                        .font(.system(size: 34, weight: .bold))
                    Text("Search and manage past dictations.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Total: \(runtime.historyStats.totalCount)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                TextField("Search transcripts", text: Binding(
                    get: { runtime.historyQuery },
                    set: { runtime.updateHistoryQuery($0) }
                ))
                .textFieldStyle(.roundedBorder)
                Button("Refresh") { runtime.reloadHistory() }
                Button("Copy") {
                    guard let selected = selectedRecord else { return }
                    runtime.copyHistory(selected)
                }
                .disabled(selectedRecord == nil)
                Button("Delete", role: .destructive) {
                    guard let selected = selectedRecord else { return }
                    runtime.deleteHistory(selected)
                    selectedID = nil
                }
                .disabled(selectedRecord == nil)
            }

            HStack(spacing: 18) {
                Text("Latest App: \(runtime.historyStats.latestSourceApp)")
                Text("Top App: \(runtime.historyStats.topSourceApp)")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(spacing: 10) {
                    if runtime.history.isEmpty {
                        Text("No dictations yet.")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.25)))
                    } else {
                        ForEach(runtime.history) { row in
                            HistoryRow(
                                row: row,
                                selected: selectedID == row.id,
                                onSelect: { selectedID = row.id },
                                onCopy: { runtime.copyHistory(row) },
                                onDelete: {
                                    runtime.deleteHistory(row)
                                    if selectedID == row.id {
                                        selectedID = nil
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(24)
    }

    private var selectedRecord: HistoryRecord? {
        runtime.history.first(where: { $0.id == selectedID })
    }
}

private struct HistoryRow: View {
    let row: HistoryRecord
    let selected: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTimestamp(row.createdAt))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(row.sourceApp ?? "Unknown")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 135, alignment: .leading)

                Text(row.finalText)
                    .font(.system(size: 15))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Color(nsColor: .selectedControlColor).opacity(0.12) : Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? Color(nsColor: .selectedControlColor).opacity(0.65) : Color.gray.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy", action: onCopy)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private func displayTimestamp(_ raw: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parserFallback = ISO8601DateFormatter()
        if let date = parser.date(from: raw) ?? parserFallback.date(from: raw) {
            let f = DateFormatter()
            f.locale = .current
            f.timeZone = .current
            f.dateStyle = .medium
            f.timeStyle = .short
            return f.string(from: date)
        }
        return raw
    }
}

private struct SettingsDraft {
    var lmstudioBaseURL = ""
    var lmstudioAutoStart = true
    var lmstudioStartTimeoutMs = "8000"
    var groqBaseURL = ""
    var groqModel = ""
    var floatingIndicatorHideDelayMs = "1000"
    var groqKeyMaskedState = "Not set"

    init() {}

    init(config: AppConfig, hasGroqKey: Bool) {
        lmstudioBaseURL = config.lmstudioBaseURL
        lmstudioAutoStart = config.lmstudioAutoStart
        lmstudioStartTimeoutMs = "\(config.lmstudioStartTimeoutMs)"
        groqBaseURL = config.groqBaseURL
        groqModel = config.groqModel
        floatingIndicatorHideDelayMs = "\(config.floatingIndicatorHideDelayMs)"
        groqKeyMaskedState = hasGroqKey ? "Saved in Keychain" : "Not set"
    }
}

private struct SettingsView: View {
    @ObservedObject var runtime: AppRuntime
    @Binding var draft: SettingsDraft
    @State private var groqKey = ""
    var onRefreshDraft: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.system(size: 34, weight: .bold))

                serviceSection
                cleanupSection
                fallbackSection
                startupSection
            }
            .padding(24)
        }
        .onAppear {
            onRefreshDraft()
        }
    }

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Service")
                .font(.system(size: 18, weight: .bold))
            Toggle("Enable service", isOn: Binding(
                get: { runtime.serviceEnabled },
                set: { runtime.setServiceEnabled($0) }
            ))
            Picker("Hotkey", selection: Binding(
                get: { runtime.config.hotkeyMode },
                set: { runtime.setHotkeyMode($0) }
            )) {
                Text("Fn hold").tag(HotkeyMode.fnHold)
                Text("Fn + Space hold").tag(HotkeyMode.fnSpaceHold)
            }
            .pickerStyle(.segmented)

            Picker("Language mode", selection: Binding(
                get: { runtime.config.languageMode },
                set: { runtime.setLanguageMode($0) }
            )) {
                Text("Auto").tag(LanguageMode.auto)
                Text("English").tag(LanguageMode.english)
                Text("Hinglish Roman").tag(LanguageMode.hinglishRoman)
            }
            .pickerStyle(.segmented)
        }
        .cardStyle()
    }

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cleanup Providers")
                .font(.system(size: 18, weight: .bold))

            Picker("Provider chain", selection: Binding(
                get: { runtime.config.cleanupProvider },
                set: { runtime.setCleanupProvider($0) }
            )) {
                Text("Groq -> LM Studio -> deterministic").tag(CleanupProvider.priority)
                Text("Deterministic only").tag(CleanupProvider.deterministic)
            }
            .pickerStyle(.segmented)

            Toggle("Enable LM Studio fallback", isOn: Binding(
                get: { runtime.config.lmstudioEnabled },
                set: { runtime.setLMStudioEnabled($0) }
            ))
            Toggle("Auto-start LM Studio if unavailable", isOn: Binding(
                get: { runtime.config.lmstudioAutoStart },
                set: { runtime.setLMStudioAutoStart($0) }
            ))

            HStack {
                Text("LM Studio base URL")
                    .frame(width: 170, alignment: .leading)
                TextField("http://127.0.0.1:1234/v1", text: $draft.lmstudioBaseURL)
                Button("Apply") { runtime.setLMStudioBaseURL(draft.lmstudioBaseURL) }
            }
            HStack {
                Text("LM Studio start timeout (ms)")
                    .frame(width: 170, alignment: .leading)
                TextField("8000", text: $draft.lmstudioStartTimeoutMs)
                Button("Apply") {
                    runtime.setLMStudioStartTimeoutMs(Int(draft.lmstudioStartTimeoutMs) ?? runtime.config.lmstudioStartTimeoutMs)
                }
            }
            HStack {
                Text("Groq base URL")
                    .frame(width: 170, alignment: .leading)
                TextField("https://api.groq.com/openai/v1", text: $draft.groqBaseURL)
                Button("Apply") { runtime.setGroqBaseURL(draft.groqBaseURL) }
            }
            HStack {
                Text("Groq model")
                    .frame(width: 170, alignment: .leading)
                TextField("meta-llama/llama-4-maverick-17b-128e-instruct", text: $draft.groqModel)
                Button("Apply") { runtime.setGroqModel(draft.groqModel) }
            }

            Divider().padding(.vertical, 4)
            Text("Groq API key: \(draft.groqKeyMaskedState)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            SecureField("gsk_...", text: $groqKey)
            HStack {
                Button("Save key") {
                    runtime.setGroqKey(groqKey)
                    groqKey = ""
                    onRefreshDraft()
                }
                .buttonStyle(.borderedProminent)
                Button("Clear key") {
                    runtime.clearGroqKey()
                    onRefreshDraft()
                }
                .buttonStyle(.bordered)
            }
        }
        .cardStyle()
    }

    private var fallbackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Indicator & Paste Fallback")
                .font(.system(size: 18, weight: .bold))
            Toggle("Floating indicator", isOn: Binding(
                get: { runtime.config.floatingIndicatorEnabled },
                set: { runtime.setFloatingIndicatorEnabled($0) }
            ))
            HStack {
                Text("Indicator hide delay (ms)")
                    .frame(width: 170, alignment: .leading)
                TextField("1000", text: $draft.floatingIndicatorHideDelayMs)
                Button("Apply") {
                    runtime.setFloatingIndicatorHideDelayMs(
                        Int(draft.floatingIndicatorHideDelayMs) ?? runtime.config.floatingIndicatorHideDelayMs
                    )
                }
            }
            Toggle("Option+Cmd+V paste-last shortcut", isOn: Binding(
                get: { runtime.config.pasteLastShortcutEnabled },
                set: { runtime.setPasteLastShortcutEnabled($0) }
            ))
            Toggle("Keep dictation in clipboard if paste fails", isOn: Binding(
                get: { runtime.config.pasteFailureKeepDictationInClipboard },
                set: { runtime.setPasteFailureKeepDictationInClipboard($0) }
            ))
        }
        .cardStyle()
    }

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Startup")
                .font(.system(size: 18, weight: .bold))
            HStack {
                Button("Install auto-start") { runtime.installAutostart() }
                Button("Uninstall auto-start") { runtime.uninstallAutostart() }
            }
        }
        .cardStyle()
    }
}

private struct PermissionsView: View {
    @ObservedObject var runtime: AppRuntime

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Permissions")
                    .font(.system(size: 34, weight: .bold))
                Text("Grant all permissions for reliable dictation and insertion.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)

                PermissionCard(
                    title: "Microphone",
                    subtitle: "System Settings -> Privacy & Security -> Microphone",
                    granted: runtime.permissionState.microphone
                ) { runtime.requestPermission(.microphone) }
                PermissionCard(
                    title: "Accessibility",
                    subtitle: "System Settings -> Privacy & Security -> Accessibility",
                    granted: runtime.permissionState.accessibility
                ) { runtime.requestPermission(.accessibility) }
                PermissionCard(
                    title: "Input Monitoring",
                    subtitle: "System Settings -> Privacy & Security -> Input Monitoring",
                    granted: runtime.permissionState.inputMonitoring
                ) { runtime.requestPermission(.inputMonitoring) }
                PermissionCard(
                    title: "Automation",
                    subtitle: "System Settings -> Privacy & Security -> Automation",
                    granted: runtime.permissionState.automation
                ) { runtime.requestPermission(.automation) }

                HStack {
                    Button("Re-check") { runtime.refreshPermissions() }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                    Text(runtime.permissionState.allGranted ? "All permissions granted" : "Missing required permissions")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(runtime.permissionState.allGranted ? .green : .orange)
                }
            }
            .padding(24)
        }
    }
}

private struct PermissionsSummaryGrid: View {
    @ObservedObject var runtime: AppRuntime

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                summaryCell("Microphone", runtime.permissionState.microphone)
                summaryCell("Accessibility", runtime.permissionState.accessibility)
            }
            GridRow {
                summaryCell("Input Monitoring", runtime.permissionState.inputMonitoring)
                summaryCell("Automation", runtime.permissionState.automation)
            }
        }
    }

    private func summaryCell(_ title: String, _ granted: Bool) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

private struct PermissionCard: View {
    let title: String
    let subtitle: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                    Text(granted ? "Granted" : "Missing")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(granted ? .green : .red)
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(granted ? "Open Settings" : "Grant Access", action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            )
    }
}
