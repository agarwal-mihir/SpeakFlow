import Domain
import SwiftUI

struct HomeView: View {
    @ObservedObject var runtime: AppRuntime
    var onOpenModels: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                dictationPanel
                permissionPanel
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

            if runtime.state == .recording {
                VStack(spacing: 6) {
                    AudioVisualizerView(level: runtime.audioLevel, barCount: 32, isActive: true)
                    Text("Recording...")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
                .padding(.vertical, 4)
            } else if runtime.state == .transcribing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Transcribing...")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                .padding(.vertical, 4)
            }

            if !runtime.lastError.isEmpty {
                Label(runtime.lastError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                GridRow {
                    settingToggle(
                        "Service",
                        systemImage: "power",
                        isOn: Binding(
                            get: { runtime.serviceEnabled },
                            set: { runtime.setServiceEnabled($0) }
                        )
                    )
                    settingToggle(
                        "Floating indicator",
                        systemImage: "rectangle.inset.filled.and.person.filled",
                        isOn: Binding(
                            get: { runtime.config.floatingIndicatorEnabled },
                            set: { runtime.setFloatingIndicatorEnabled($0) }
                        )
                    )
                }
                GridRow {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Hotkey", systemImage: "keyboard")
                            .font(.subheadline.weight(.semibold))
                        Picker("Hotkey", selection: Binding(
                            get: { runtime.config.hotkeyMode },
                            set: { runtime.setHotkeyMode($0) }
                        )) {
                            Text("Fn hold").tag(HotkeyMode.fnHold)
                            Text("Fn + Space hold").tag(HotkeyMode.fnSpaceHold)
                        }
                        .pickerStyle(.segmented)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Language", systemImage: "textformat")
                            .font(.subheadline.weight(.semibold))
                        Picker("Language", selection: Binding(
                            get: { runtime.config.languageMode },
                            set: { runtime.setLanguageMode($0) }
                        )) {
                            Text("Auto").tag(LanguageMode.auto)
                            Text("English").tag(LanguageMode.english)
                            Text("Hinglish").tag(LanguageMode.hinglishRoman)
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }

            HStack(spacing: 12) {
                Button(action: onOpenModels) {
                    Label("Choose model", systemImage: "cpu")
                }
                .buttonStyle(.borderedProminent)

                Toggle("Keep text in clipboard if paste fails", isOn: Binding(
                    get: { runtime.config.pasteFailureKeepDictationInClipboard },
                    set: { runtime.setPasteFailureKeepDictationInClipboard($0) }
                ))
                .toggleStyle(.checkbox)
            }
        }
        .glassCard()
    }

    private var permissionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Permissions", systemImage: "checkmark.shield.fill")
                .font(.title3.bold())

            HStack(spacing: 10) {
                permissionItem(
                    "Microphone",
                    granted: runtime.permissionState.microphone,
                    action: { runtime.requestPermission(.microphone) }
                )
                permissionItem(
                    "Input Monitoring",
                    granted: runtime.permissionState.inputMonitoring,
                    action: { runtime.requestPermission(.inputMonitoring) }
                )
                permissionItem(
                    "Auto-paste",
                    granted: runtime.permissionState.accessibility,
                    optional: true,
                    action: { runtime.requestPermission(.accessibility) }
                )
            }
        }
        .glassCard()
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

    private func settingToggle(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .frame(maxWidth: .infinity)
    }

    private func permissionItem(_ title: String, granted: Bool, optional: Bool = false, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : (optional ? .secondary : .orange))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(granted ? "Granted" : optional ? "Optional" : "Required")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button(action: action) {
                    Label("Grant", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .macPanel(cornerRadius: 8)
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
