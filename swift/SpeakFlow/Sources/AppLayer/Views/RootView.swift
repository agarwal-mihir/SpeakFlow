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
        case .home: return "house.fill"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape.fill"
        case .permissions: return "checkmark.shield.fill"
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
        NavigationSplitView {
            sidebar
        } detail: {
            mainContent
        }
        .frame(minWidth: 980, minHeight: 640)
        .onAppear {
            refreshSettingsDraft()
            if runtime.requiresPermissionOnboarding {
                selectedTab = .permissions
            }
        }
        .onChange(of: runtime.requiresPermissionOnboarding) { _, missing in
            if missing { selectedTab = .permissions }
        }
    }

    private var sidebar: some View {
        List(SidebarTab.allCases, selection: $selectedTab) { tab in
            Label(tab.title, systemImage: tab.icon)
                .tag(tab)
        }
        .navigationSplitViewColumnWidth(220)
        .safeAreaInset(edge: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SpeakFlow")
                    .font(.title.bold())
                Text("Local dictation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .safeAreaInset(edge: .bottom) {
            sidebarStatusCard
                .padding(12)
        }
    }

    private var sidebarStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(runtime.state.rawValue, systemImage: "waveform")
                .font(.subheadline.bold())
            Label(
                runtime.permissionState.allGranted ? "Permissions ready" : "Permissions missing",
                systemImage: runtime.permissionState.allGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(runtime.permissionState.allGranted ? .green : .orange)

            Toggle("Service", isOn: Binding(
                get: { runtime.serviceEnabled },
                set: { runtime.setServiceEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    @ViewBuilder
    private var mainContent: some View {
        switch selectedTab {
        case .home:
            HomeView(runtime: runtime, onOpenSettings: { selectedTab = .settings })
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

    private func refreshSettingsDraft() {
        settingsDraft = SettingsDraft(config: runtime.config, hasGroqKey: runtime.hasGroqAPIKey())
    }
}
