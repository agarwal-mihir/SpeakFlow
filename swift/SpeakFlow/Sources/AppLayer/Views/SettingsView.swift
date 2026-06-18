import Domain
import SwiftUI

struct SettingsView: View {
    @ObservedObject var runtime: AppRuntime
    @State private var mlxBaseURL = ""
    @State private var groqBaseURL = ""
    @State private var groqModel = ""
    @State private var groqKey = ""
    @State private var cleanupSystemPrompt = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                behaviorPanel
                permissionPanel
                providerPanel
                computePanel
                activeModelPanel
                cleanupPanel
            }
            .padding(28)
        }
        .onAppear(perform: refreshDraft)
        .onAppear {
            runtime.refreshModelStatus()
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.largeTitle.bold())
                Text("Configure dictation behavior, permissions, speech models, and cleanup.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(
                "\(runtime.config.transcriptionProvider.title) · \(runtime.config.computeBackend.title)",
                systemImage: "cpu"
            )
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(.regularMaterial, in: Capsule())
        }
    }

    private var behaviorPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Dictation behavior", systemImage: "slider.horizontal.3")
                .font(.title3.bold())

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

            Toggle("Keep text in clipboard if paste fails", isOn: Binding(
                get: { runtime.config.pasteFailureKeepDictationInClipboard },
                set: { runtime.setPasteFailureKeepDictationInClipboard($0) }
            ))
            .toggleStyle(.checkbox)
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

    private var providerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Speech-to-text engine", systemImage: "waveform")
                .font(.title3.bold())

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(TranscriptionProvider.allCases, id: \.self) { provider in
                    providerButton(provider)
                }
            }
        }
        .glassCard()
    }

    private func providerButton(_ provider: TranscriptionProvider) -> some View {
        Button {
            runtime.setTranscriptionProvider(provider)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: provider.systemImage)
                    .foregroundStyle(runtime.config.transcriptionProvider == provider ? .blue : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.title)
                        .font(.subheadline.weight(.semibold))
                    Text(provider.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if runtime.config.transcriptionProvider == provider {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .macPanel(cornerRadius: 8)
        }
        .buttonStyle(.plain)
    }

    private var computePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Device", systemImage: "cpu")
                .font(.title3.bold())

            Picker("Device", selection: Binding(
                get: { runtime.config.computeBackend },
                set: { runtime.setComputeBackend($0) }
            )) {
                ForEach(ComputeBackend.allCases, id: \.self) { backend in
                    Text(backend.title).tag(backend)
                }
            }
            .pickerStyle(.segmented)

            Text(deviceDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .glassCard()
    }

    private var deviceDescription: String {
        switch runtime.config.computeBackend {
        case .automatic:
            return "WhisperKit chooses the best Core ML compute units for this Mac."
        case .cpu:
            return "Forces supported speech models onto CPU-only inference."
        case .gpu:
            return "Prefers GPU-backed inference for supported speech models."
        }
    }

    @ViewBuilder
    private var activeModelPanel: some View {
        switch runtime.config.transcriptionProvider {
        case .whisperKit:
            modelList(
                title: "WhisperKit models",
                subtitle: "Core ML Whisper models download on demand through WhisperKit.",
                models: WhisperModel.allCases.map { model in
                    ModelOption(
                        id: model.rawValue,
                        title: model.title,
                        detail: model.qualityLabel,
                        size: model.sizeLabel,
                        selected: runtime.config.whisperModel == model,
                        recommended: model == .largeV3Turbo,
                        action: { runtime.setWhisperModel(model) }
                    )
                }
            )
        case .parakeetMLX:
            VStack(alignment: .leading, spacing: 12) {
                modelList(
                    title: "NVIDIA Parakeet models",
                    subtitle: "Parakeet choices are aligned with OpenWhispr and run through a local MLX runner executable.",
                    models: ParakeetModel.allCases.map { model in
                        ModelOption(
                            id: model.rawValue,
                            title: model.title,
                            detail: model.languageLabel,
                            size: model.sizeLabel,
                            selected: runtime.config.parakeetModel == model,
                            recommended: model == .tdt06BV3,
                            action: { runtime.setParakeetModel(model) }
                        )
                    }
                )

                parakeetRunnerStatus
            }
        case .appleSpeech:
            modelList(
                title: "Apple Dictation",
                subtitle: "Uses Apple's built-in Speech Recognition service for the selected language mode.",
                models: [
                    ModelOption(
                        id: "apple-speech",
                        title: "Apple Speech Recognition",
                        detail: "Built into macOS",
                        size: "System",
                        selected: true,
                        recommended: false,
                        action: { runtime.setTranscriptionProvider(.appleSpeech) }
                    )
                ]
            )
        case .groqCloud:
            VStack(alignment: .leading, spacing: 12) {
                modelList(
                    title: "Groq transcription models",
                    subtitle: "Cloud transcription through Groq's OpenAI-compatible audio API.",
                    models: GroqTranscriptionModel.allCases.map { model in
                        ModelOption(
                            id: model.rawValue,
                            title: model.title,
                            detail: model.detail,
                            size: model.priceLabel,
                            selected: runtime.config.groqTranscriptionModel == model,
                            recommended: model == .whisperLargeV3Turbo,
                            action: { runtime.setGroqTranscriptionModel(model) }
                        )
                    }
                )

                groqKeyStatus
            }
        }
    }

    private var parakeetRunnerStatus: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: runtime.parakeetRunnerStatus.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(runtime.parakeetRunnerStatus.isAvailable ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(runtime.parakeetRunnerStatus.isAvailable ? "MLX runner detected" : "MLX runner required")
                    .font(.caption.weight(.semibold))
                Text(runtime.parakeetRunnerStatus.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
    }

    private func modelList(title: String, subtitle: String, models: [ModelOption]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: "square.stack.3d.up.fill")
                    .font(.title3.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(models) { model in
                    Button(action: model.action) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(model.selected ? Color.green : Color.secondary.opacity(0.25))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(model.title)
                                        .font(.subheadline.weight(.semibold))
                                    if model.recommended {
                                        Text("Recommended")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.blue.opacity(0.12), in: Capsule())
                                    }
                                }
                                Text(model.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(model.size)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            if model.selected {
                                Text("Active")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(12)
                        .macPanel(cornerRadius: 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .glassCard()
    }

    private var cleanupPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Text cleanup", systemImage: "wand.and.stars")
                .font(.title3.bold())

            Picker("Cleanup engine", selection: Binding(
                get: { runtime.config.cleanupProvider },
                set: { runtime.setCleanupProvider($0) }
            )) {
                ForEach(CleanupProvider.allCases, id: \.self) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .pickerStyle(.segmented)

            cleanupEngineDetails
            cleanupPromptEditor
        }
        .glassCard()
    }

    @ViewBuilder
    private var cleanupEngineDetails: some View {
        switch runtime.config.cleanupProvider {
        case .groqCloud:
            settingsField(
                label: "Groq URL",
                placeholder: "https://api.groq.com/openai/v1",
                text: $groqBaseURL,
                onApply: { runtime.setGroqBaseURL(groqBaseURL) }
            )
            settingsField(
                label: "Groq model",
                placeholder: "meta-llama/llama-4-maverick-17b-128e-instruct",
                text: $groqModel,
                onApply: { runtime.setGroqModel(groqModel) }
            )

            groqModelPicker
            groqKeyEditor
        case .mlxLocal:
            Toggle("Auto-start MLX server if unavailable", isOn: Binding(
                get: { runtime.config.mlxAutoStart },
                set: { runtime.setMLXAutoStart($0) }
            ))
            settingsField(
                label: "MLX URL",
                placeholder: "http://127.0.0.1:8080/v1",
                text: $mlxBaseURL,
                onApply: { runtime.setMLXBaseURL(mlxBaseURL) }
            )
            mlxModelPicker
        case .deterministic:
            Label("AI cleanup is disabled. SpeakFlow will only normalize spacing, punctuation, and capitalization locally.", systemImage: "text.badge.checkmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var groqKeyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField(runtime.hasGroqAPIKey() ? "Saved in Keychain" : "Groq API key", text: $groqKey)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                Button {
                    runtime.setGroqKey(groqKey)
                    groqKey = ""
                } label: {
                    Label("Save key", systemImage: "key.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(groqKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    runtime.clearGroqKey()
                } label: {
                    Label("Clear key", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var cleanupPromptEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("System prompt", systemImage: "text.quote")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    runtime.resetCleanupSystemPrompt()
                    cleanupSystemPrompt = runtime.config.cleanupSystemPrompt
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                Button {
                    runtime.setCleanupSystemPrompt(cleanupSystemPrompt)
                } label: {
                    Label("Apply", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            }

            TextEditor(text: $cleanupSystemPrompt)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 180)
                .padding(8)
                .macPanel(cornerRadius: 8)
        }
    }

    private var groqModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Groq models", systemImage: "list.bullet.rectangle")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(runtime.groqModelStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await runtime.refreshGroqModels() }
                } label: {
                    Label(runtime.isLoadingGroqModels ? "Loading" : "Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(runtime.isLoadingGroqModels)
            }

            VStack(spacing: 8) {
                ForEach(runtime.groqModels) { model in
                    Button {
                        groqModel = model.id
                        runtime.setGroqModel(model.id)
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(runtime.config.groqModel == model.id ? Color.green : Color.secondary.opacity(0.25))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(model.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(model.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if runtime.config.groqModel == model.id {
                                Text("Active")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(12)
                        .macPanel(cornerRadius: 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var mlxModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Local MLX models", systemImage: "memorychip")
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 8) {
                ForEach(MLXTextModel.allCases, id: \.self) { model in
                    Button {
                        runtime.setMLXModel(model)
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(runtime.config.mlxModel == model ? Color.green : Color.secondary.opacity(0.25))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(model.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(model.sizeLabel)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            if runtime.config.mlxModel == model {
                                Text("Active")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(12)
                        .macPanel(cornerRadius: 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var groqKeyStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: runtime.hasGroqAPIKey() ? "checkmark.circle.fill" : "key.fill")
                .foregroundStyle(runtime.hasGroqAPIKey() ? .green : .orange)
            Text(runtime.hasGroqAPIKey() ? "Groq API key saved" : "Save a Groq API key in Text cleanup before using Groq transcription.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
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
                .frame(width: 130, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
            Button(action: onApply) {
                Label("Apply", systemImage: "checkmark")
            }
            .buttonStyle(.bordered)
        }
    }

    private func refreshDraft() {
        mlxBaseURL = runtime.config.mlxBaseURL
        groqBaseURL = runtime.config.groqBaseURL
        groqModel = runtime.config.groqModel
        cleanupSystemPrompt = runtime.config.cleanupSystemPrompt
    }
}

private struct ModelOption: Identifiable {
    let id: String
    let title: String
    let detail: String
    let size: String
    let selected: Bool
    let recommended: Bool
    let action: () -> Void
}
