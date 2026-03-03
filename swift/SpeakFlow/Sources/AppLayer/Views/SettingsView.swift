import Domain
import SwiftUI

struct SettingsDraft {
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

struct SettingsView: View {
    @ObservedObject var runtime: AppRuntime
    @Binding var draft: SettingsDraft
    @State private var groqKey = ""
    var onRefreshDraft: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(.largeTitle.bold())

                serviceSection
                cleanupSection
                indicatorSection
                startupSection
            }
            .padding(28)
        }
        .onAppear { onRefreshDraft() }
    }

    private var serviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Service", systemImage: "power")
                .font(.title3.bold())

            Toggle("Enable service", isOn: Binding(
                get: { runtime.serviceEnabled },
                set: { runtime.setServiceEnabled($0) }
            ))

            VStack(alignment: .leading, spacing: 6) {
                Text("Hotkey mode")
                    .font(.subheadline.weight(.medium))
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
                Text("Language mode")
                    .font(.subheadline.weight(.medium))
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
        }
        .glassCard()
    }

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Cleanup Providers", systemImage: "wand.and.stars")
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("Provider chain")
                    .font(.subheadline.weight(.medium))
                Picker("Provider chain", selection: Binding(
                    get: { runtime.config.cleanupProvider },
                    set: { runtime.setCleanupProvider($0) }
                )) {
                    Text("Groq → LM Studio → Deterministic").tag(CleanupProvider.priority)
                    Text("Deterministic only").tag(CleanupProvider.deterministic)
                }
                .pickerStyle(.segmented)
            }

            Toggle("Enable LM Studio fallback", isOn: Binding(
                get: { runtime.config.lmstudioEnabled },
                set: { runtime.setLMStudioEnabled($0) }
            ))
            Toggle("Auto-start LM Studio if unavailable", isOn: Binding(
                get: { runtime.config.lmstudioAutoStart },
                set: { runtime.setLMStudioAutoStart($0) }
            ))

            settingsField(
                label: "LM Studio base URL",
                placeholder: "http://127.0.0.1:1234/v1",
                text: $draft.lmstudioBaseURL,
                onApply: { runtime.setLMStudioBaseURL(draft.lmstudioBaseURL) }
            )
            settingsField(
                label: "Start timeout (ms)",
                placeholder: "8000",
                text: $draft.lmstudioStartTimeoutMs,
                onApply: {
                    runtime.setLMStudioStartTimeoutMs(
                        Int(draft.lmstudioStartTimeoutMs) ?? runtime.config.lmstudioStartTimeoutMs
                    )
                }
            )
            settingsField(
                label: "Groq base URL",
                placeholder: "https://api.groq.com/openai/v1",
                text: $draft.groqBaseURL,
                onApply: { runtime.setGroqBaseURL(draft.groqBaseURL) }
            )
            settingsField(
                label: "Groq model",
                placeholder: "meta-llama/llama-4-maverick-17b-128e-instruct",
                text: $draft.groqModel,
                onApply: { runtime.setGroqModel(draft.groqModel) }
            )

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.secondary)
                    Text("Groq API key:")
                        .font(.subheadline.weight(.semibold))
                    Text(draft.groqKeyMaskedState)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                SecureField("gsk_...", text: $groqKey)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button("Save key") {
                        runtime.setGroqKey(groqKey)
                        groqKey = ""
                        onRefreshDraft()
                    }
                    .buttonStyle(.glassProminent)

                    Button("Clear key") {
                        runtime.clearGroqKey()
                        onRefreshDraft()
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .glassCard()
    }

    private var indicatorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Indicator & Paste", systemImage: "rectangle.inset.filled.and.person.filled")
                .font(.title3.bold())

            Toggle("Floating indicator", isOn: Binding(
                get: { runtime.config.floatingIndicatorEnabled },
                set: { runtime.setFloatingIndicatorEnabled($0) }
            ))

            settingsField(
                label: "Hide delay (ms)",
                placeholder: "1000",
                text: $draft.floatingIndicatorHideDelayMs,
                onApply: {
                    runtime.setFloatingIndicatorHideDelayMs(
                        Int(draft.floatingIndicatorHideDelayMs) ?? runtime.config.floatingIndicatorHideDelayMs
                    )
                }
            )

            Toggle("Option+Cmd+V paste-last shortcut", isOn: Binding(
                get: { runtime.config.pasteLastShortcutEnabled },
                set: { runtime.setPasteLastShortcutEnabled($0) }
            ))
            Toggle("Keep dictation in clipboard if paste fails", isOn: Binding(
                get: { runtime.config.pasteFailureKeepDictationInClipboard },
                set: { runtime.setPasteFailureKeepDictationInClipboard($0) }
            ))
        }
        .glassCard()
    }

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Startup", systemImage: "arrow.up.circle")
                .font(.title3.bold())

            HStack(spacing: 10) {
                Button("Install auto-start") { runtime.installAutostart() }
                    .buttonStyle(.glass)
                Button("Uninstall auto-start") { runtime.uninstallAutostart() }
                    .buttonStyle(.glass)
            }
        }
        .glassCard()
    }

    private func settingsField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        onApply: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .frame(width: 160, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
            Button("Apply", action: onApply)
                .buttonStyle(.glass)
        }
    }
}
