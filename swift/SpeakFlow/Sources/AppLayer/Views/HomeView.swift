import Domain
import SwiftUI

struct HomeView: View {
    @ObservedObject var runtime: AppRuntime
    var onOpenSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statusRow
                controlsCard
                activityCard
            }
            .padding(28)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome back")
                    .font(.largeTitle.bold())
                Text("Hold Fn to dictate in any app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(runtime.state.rawValue, systemImage: stateIcon)
                .font(.subheadline.weight(.semibold))
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .glassEffect(.regular, in: .capsule)
        }
    }

    private var stateIcon: String {
        switch runtime.state {
        case .idle: return "waveform"
        case .recording: return "mic.fill"
        case .transcribing: return "brain.head.profile"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var statusRow: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatusChip(
                    title: "Service",
                    value: runtime.serviceEnabled ? "On" : "Off",
                    icon: runtime.serviceEnabled ? "power" : "power.circle",
                    tint: runtime.serviceEnabled ? .green : .secondary
                )
                StatusChip(
                    title: "Permissions",
                    value: runtime.permissionState.allGranted ? "Ready" : "Missing",
                    icon: runtime.permissionState.allGranted ? "checkmark.shield.fill" : "exclamationmark.shield",
                    tint: runtime.permissionState.allGranted ? .green : .orange
                )
                StatusChip(
                    title: "History",
                    value: "\(runtime.historyStats.totalCount) saved",
                    icon: "clock.arrow.circlepath",
                    tint: .blue
                )
            }

            if !runtime.lastError.isEmpty {
                Text(runtime.lastError)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Quick Controls", systemImage: "slider.horizontal.3")
                .font(.title3.bold())

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
                .buttonStyle(.glass)
        }
        .glassCard()
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Recent Activity", systemImage: "chart.bar.fill")
                .font(.title3.bold())

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Latest App")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(runtime.historyStats.latestSourceApp)
                        .font(.body.weight(.medium))
                }

                Divider().frame(height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Top App")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(runtime.historyStats.topSourceApp) (\(runtime.historyStats.topSourceAppCount))")
                        .font(.body.weight(.medium))
                }
            }
        }
        .glassCard()
    }
}

private struct StatusChip: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)

            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}
