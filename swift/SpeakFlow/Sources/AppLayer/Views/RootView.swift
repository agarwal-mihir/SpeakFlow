import Domain
import SwiftUI

private enum SidebarTab: String, CaseIterable, Identifiable {
    case dictation
    case models

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictation: return "Dictation"
        case .models: return "Models"
        }
    }

    var icon: String {
        switch self {
        case .dictation: return "mic.fill"
        case .models: return "cpu.fill"
        }
    }
}

public struct RootView: View {
    @ObservedObject var runtime: AppRuntime
    @State private var selectedTab: SidebarTab = .dictation

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
            if runtime.requiresPermissionOnboarding {
                selectedTab = .dictation
            }
        }
        .onChange(of: runtime.requiresPermissionOnboarding) { _, missing in
            if missing { selectedTab = .dictation }
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
                Text(runtime.config.transcriptionProvider.title)
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
                "\(runtime.config.transcriptionProvider.title) · \(runtime.config.computeBackend.title)",
                systemImage: "cpu"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            Label(
                runtime.permissionState.dictationReady ? "Dictation ready" : "Permissions missing",
                systemImage: runtime.permissionState.dictationReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(runtime.permissionState.dictationReady ? .green : .orange)

            Toggle("Service", isOn: Binding(
                get: { runtime.serviceEnabled },
                set: { runtime.setServiceEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(12)
        .macPanel(cornerRadius: 12)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch selectedTab {
        case .dictation:
            HomeView(runtime: runtime, onOpenModels: { selectedTab = .models })
        case .models:
            ModelsView(runtime: runtime)
        }
    }
}
