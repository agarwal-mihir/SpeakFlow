import Domain
import SwiftUI

struct HomeView: View {
    @ObservedObject var runtime: AppRuntime
    var onOpenSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if runtime.requiresPermissionOnboarding {
                    permissionBanner
                }
                dictationPanel
                recentPanel
            }
            .padding(28)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dictation")
                    .font(.largeTitle.bold())
                Text("Hold the global hotkey, speak, and paste into the frontmost app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Label(runtime.state.rawValue, systemImage: stateIcon)
                    .font(.subheadline.weight(.semibold))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(.regularMaterial, in: Capsule())
                Text("\(runtime.config.transcriptionProvider.title) · \(activeModelLabel)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
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

    private var activeModelLabel: String {
        switch runtime.config.transcriptionProvider {
        case .whisperKit: return runtime.config.whisperModel.title
        case .parakeetMLX: return runtime.config.parakeetModel.title
        }
    }

    private var permissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Dictation needs permissions")
                    .font(.subheadline.weight(.semibold))
                Text("Grant Microphone and Input Monitoring in Settings to start dictating.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings", action: onOpenSettings)
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.orange.opacity(0.1))
                .stroke(.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private var dictationPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                StatusChip(
                    title: "Service",
                    value: runtime.serviceEnabled ? "On" : "Off",
                    icon: runtime.serviceEnabled ? "power" : "power.circle",
                    tint: runtime.serviceEnabled ? .green : .secondary
                )
                StatusChip(
                    title: "Model",
                    value: activeModelLabel,
                    icon: runtime.config.transcriptionProvider == .parakeetMLX ? "bolt.fill" : "waveform.badge.magnifyingglass",
                    tint: runtime.config.transcriptionProvider == .parakeetMLX ? .orange : .blue
                )
                StatusChip(
                    title: "Device",
                    value: runtime.config.computeBackend.title,
                    icon: "cpu",
                    tint: .purple
                )
            }

            liveStatus

            if !runtime.lastError.isEmpty {
                Label(runtime.lastError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .glassCard()
    }

    @ViewBuilder
    private var liveStatus: some View {
        switch runtime.state {
        case .recording:
            VStack(spacing: 8) {
                AudioVisualizerView(level: runtime.audioLevel, barCount: 32, isActive: true)
                Text("Recording...")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        case .transcribing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Transcribing...")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        default:
            VStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text(idleHint)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        }
    }

    private var idleHint: String {
        guard runtime.serviceEnabled else {
            return "Service is off. Enable it in Settings to dictate."
        }
        switch runtime.config.hotkeyMode {
        case .fnHold: return "Hold Fn and speak to dictate"
        case .fnSpaceHold: return "Hold Fn + Space and speak to dictate"
        }
    }

    private var recentPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Recent Dictations", systemImage: "clock.arrow.circlepath")
                    .font(.title3.bold())
                Spacer()
                Text("\(runtime.historyStats.totalCount) saved")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if runtime.history.isEmpty {
                Text("No dictations yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(runtime.history.prefix(5).enumerated()), id: \.element.id) { index, record in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.finalText)
                                    .font(.subheadline)
                                    .lineLimit(2)
                                Text(record.sourceApp ?? "Unknown app")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                runtime.copyHistory(record)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Copy")
                        }
                        .padding(.vertical, 9)

                        if index < min(runtime.history.count, 5) - 1 {
                            Divider()
                        }
                    }
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
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .macPanel(cornerRadius: 8)
    }
}
