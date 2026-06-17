import Domain
import SwiftUI

struct ModelsView: View {
    @ObservedObject var runtime: AppRuntime
    @State private var lmstudioBaseURL = ""
    @State private var groqBaseURL = ""
    @State private var groqModel = ""
    @State private var groqKey = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
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
                Text("Models")
                    .font(.largeTitle.bold())
                Text("Choose the local speech model and where inference runs.")
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

    private var providerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Speech-to-text engine", systemImage: "waveform")
                .font(.title3.bold())

            HStack(spacing: 10) {
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
                Image(systemName: provider == .parakeetMLX ? "bolt.fill" : "waveform.badge.magnifyingglass")
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

            Picker("Provider chain", selection: Binding(
                get: { runtime.config.cleanupProvider },
                set: { runtime.setCleanupProvider($0) }
            )) {
                Text("Groq -> LM Studio -> Deterministic").tag(CleanupProvider.priority)
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

            settingsField(
                label: "LM Studio URL",
                placeholder: "http://127.0.0.1:1234/v1",
                text: $lmstudioBaseURL,
                onApply: { runtime.setLMStudioBaseURL(lmstudioBaseURL) }
            )
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
        lmstudioBaseURL = runtime.config.lmstudioBaseURL
        groqBaseURL = runtime.config.groqBaseURL
        groqModel = runtime.config.groqModel
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
