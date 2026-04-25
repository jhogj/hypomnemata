import HypomnemataAI
import HypomnemataData
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    @State private var llmURL: String = ""
    @State private var llmModel: String = ""
    @State private var llmContextLimit: String = ""
    @State private var llmStatusMessage: String?
    @State private var llmIsError = false
    @State private var resolvedSummary: String = ""
    @State private var loaded = false

    private let environment = ProcessInfo.processInfo.environment

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                dependenciesSection
                llmSection
            }
            .padding(20)
        }
        .frame(width: 600, height: 520)
        .onAppear {
            if !loaded {
                loadSettings()
                loaded = true
            }
        }
    }

    private var dependenciesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Dependências")
                    .font(.title3.weight(.semibold))
                ForEach(model.dependencyStatuses) { status in
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: status.isInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(status.isInstalled ? .green : .orange)
                        VStack(alignment: .leading) {
                            Text(status.requirement.executable)
                                .font(.headline)
                            Text(status.requirement.purpose)
                                .foregroundStyle(.secondary)
                            if let path = status.path {
                                Text(path)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            } else {
                                Text(status.requirement.installCommand)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Button("Reverificar") {
                    model.refreshDependencies()
                }
            }
        }
    }

    private var llmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("IA local")
                .font(.title3.weight(.semibold))
            Text("Configurações ficam dentro do vault criptografado. Variáveis de ambiente HYPO_LLM_URL, HYPO_LLM_MODEL e HYPO_LLM_CONTEXT_LIMIT são usadas como fallback quando o campo está vazio.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            llmField(
                title: "URL do servidor",
                placeholder: placeholderURL,
                text: $llmURL
            )
            llmField(
                title: "Modelo",
                placeholder: placeholderModel,
                text: $llmModel
            )
            llmField(
                title: "Limite de contexto (caracteres)",
                placeholder: placeholderContextLimit,
                text: $llmContextLimit
            )

            if !resolvedSummary.isEmpty {
                Text(resolvedSummary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                Button("Salvar") {
                    saveLLMSettings()
                }
                .keyboardShortcut(.defaultAction)
                Button("Limpar overrides") {
                    clearLLMSettings()
                }
                Spacer()
            }

            if let llmStatusMessage {
                Text(llmStatusMessage)
                    .font(.callout)
                    .foregroundStyle(llmIsError ? Color.red : Color.green)
            }
        }
    }

    private func llmField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout.weight(.medium))
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var placeholderURL: String {
        environment["HYPO_LLM_URL"] ?? "http://localhost:8080"
    }

    private var placeholderModel: String {
        environment["HYPO_LLM_MODEL"] ?? "mlx-community/gemma-4-e2b-it-4bit"
    }

    private var placeholderContextLimit: String {
        environment["HYPO_LLM_CONTEXT_LIMIT"] ?? "6000"
    }

    private func loadSettings() {
        let record = model.currentLLMSettings()
        llmURL = record.url ?? ""
        llmModel = record.model ?? ""
        llmContextLimit = record.contextLimit ?? ""
        refreshResolvedSummary()
    }

    private func saveLLMSettings() {
        if let message = model.saveLLMSettings(
            url: llmURL,
            model: llmModel,
            contextLimit: llmContextLimit
        ) {
            llmStatusMessage = message
            llmIsError = true
        } else {
            llmStatusMessage = "Configurações salvas."
            llmIsError = false
        }
        refreshResolvedSummary()
    }

    private func clearLLMSettings() {
        if let message = model.clearLLMSettings() {
            llmStatusMessage = message
            llmIsError = true
        } else {
            llmURL = ""
            llmModel = ""
            llmContextLimit = ""
            llmStatusMessage = "Overrides removidos. Voltando para variáveis de ambiente / padrão."
            llmIsError = false
        }
        refreshResolvedSummary()
    }

    private func refreshResolvedSummary() {
        let result = model.resolvedLLMConfiguration()
        if let configuration = result.0 {
            resolvedSummary = "Em uso: \(configuration.baseURL.absoluteString) · \(configuration.model) · \(configuration.contextCharacterLimit) caracteres"
        } else if let error = result.1 {
            resolvedSummary = "Configuração inválida: \(error)"
        } else {
            resolvedSummary = ""
        }
    }
}
