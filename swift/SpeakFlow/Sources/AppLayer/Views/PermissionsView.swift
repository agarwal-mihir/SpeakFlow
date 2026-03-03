import Domain
import SwiftUI

struct PermissionsView: View {
    @ObservedObject var runtime: AppRuntime

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Permissions")
                        .font(.largeTitle.bold())
                    Text("Grant all permissions for reliable dictation and insertion.")
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
                PermissionCard(
                    title: "Automation",
                    subtitle: "System Settings → Privacy & Security → Automation",
                    icon: "gearshape.2.fill",
                    granted: runtime.permissionState.automation,
                    action: { runtime.requestPermission(.automation) }
                )

                HStack {
                    Button("Re-check") { runtime.refreshPermissions() }
                        .buttonStyle(.glassProminent)
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
                ? "All permissions granted"
                : "Missing required permissions",
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
                summaryCell("Automation", "gearshape.2.fill", runtime.permissionState.automation)
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
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
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
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}
