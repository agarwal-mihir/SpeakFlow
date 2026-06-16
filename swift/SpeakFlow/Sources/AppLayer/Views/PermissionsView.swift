import Domain
import SwiftUI

struct PermissionsView: View {
    @ObservedObject var runtime: AppRuntime

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if runtime.requiresPermissionOnboarding {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Permission Setup Required")
                                .font(.headline)
                            Text("Grant Microphone and Input Monitoring to enable dictation. Accessibility enables auto-paste.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.orange.opacity(0.1))
                            .stroke(.orange.opacity(0.3), lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Permissions")
                        .font(.largeTitle.bold())
                    Text("Microphone and Input Monitoring are required. Accessibility is optional for automatic paste.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                PermissionCard(
                    title: "Microphone",
                    subtitle: "System Settings → Privacy & Security → Microphone",
                    icon: "mic.fill",
                    granted: runtime.permissionState.microphone,
                    action: { runtime.requestPermission(.microphone) }
                )
                PermissionCard(
                    title: "Accessibility",
                    subtitle: "System Settings → Privacy & Security → Accessibility",
                    icon: "accessibility",
                    granted: runtime.permissionState.accessibility,
                    action: { runtime.requestPermission(.accessibility) }
                )
                PermissionCard(
                    title: "Input Monitoring",
                    subtitle: "System Settings → Privacy & Security → Input Monitoring",
                    icon: "keyboard",
                    granted: runtime.permissionState.inputMonitoring,
                    action: { runtime.requestPermission(.inputMonitoring) }
                )
                HStack {
                    Button("Re-check") { runtime.refreshPermissions() }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                    statusLabel
                }
            }
            .padding(28)
        }
    }

    private var statusLabel: some View {
        Label(
            runtime.permissionState.allGranted
                ? "Auto-paste ready"
                : runtime.permissionState.dictationReady ? "Dictation ready, auto-paste optional" : "Missing required permissions",
            systemImage: runtime.permissionState.allGranted
                ? "checkmark.seal.fill"
                : "exclamationmark.triangle.fill"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(runtime.permissionState.allGranted ? .green : .orange)
    }
}

struct PermissionsSummaryGrid: View {
    @ObservedObject var runtime: AppRuntime

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                summaryCell("Microphone", "mic.fill", runtime.permissionState.microphone)
                summaryCell("Accessibility", "accessibility", runtime.permissionState.accessibility)
            }
            GridRow {
                summaryCell("Input Monitoring", "keyboard", runtime.permissionState.inputMonitoring)
                summaryCell("Auto-paste", "text.cursor", runtime.permissionState.accessibility)
            }
        }
    }

    private func summaryCell(_ title: String, _ icon: String, _ granted: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .macPanel(cornerRadius: 10)
    }
}

private struct PermissionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(granted ? .green : .orange)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    Text(granted ? "Granted" : "Missing")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(granted ? .green : .red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                (granted ? Color.green : Color.red).opacity(0.12)
                            )
                        )
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(granted ? "Open Settings" : "Grant Access", action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .macPanel(cornerRadius: 12)
    }
}
