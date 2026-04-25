import HypomnemataCore
import HypomnemataIngestion
import SwiftUI
import UniformTypeIdentifiers

struct CaptureSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab = 0
    @State private var urlString = ""
    @State private var title = ""
    @State private var note = ""
    @State private var bodyText = ""
    @State private var tags = ""
    @State private var selectedFileURL: URL?
    @State private var showingFileImporter = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nova captura")
                .font(.title2.bold())

            Picker("Tipo", selection: $selectedTab) {
                Text("URL").tag(0)
                Text("Arquivo").tag(1)
                Text("Texto").tag(2)
            }
            .pickerStyle(.segmented)

            if selectedTab == 0 {
                TextField("https://...", text: $urlString)
                    .textFieldStyle(.roundedBorder)
            } else if selectedTab == 1 {
                HStack(spacing: 10) {
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Escolher arquivo", systemImage: "paperclip")
                    }
                    if let selectedFileURL {
                        Text(selectedFileURL.lastPathComponent)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Nenhum arquivo selecionado")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                TextEditor(text: $bodyText)
                    .frame(minHeight: 140)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6).stroke(.quaternary)
                    }
            }

            TextField("Título", text: $title)
                .textFieldStyle(.roundedBorder)
            TextField("Etiquetas separadas por vírgula", text: $tags)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $note)
                .frame(minHeight: 90)
                .overlay {
                    RoundedRectangle(cornerRadius: 6).stroke(.quaternary)
                }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancelar") {
                    dismiss()
                }
                Button("Salvar") {
                    let message = model.createCapture(CaptureDraft(
                        sourceURL: selectedTab == 0 ? urlString.trimmedNonEmpty : nil,
                        title: title.trimmedNonEmpty,
                        note: note.trimmedNonEmpty,
                        bodyText: selectedTab == 2 ? bodyText.trimmedNonEmpty : nil,
                        fileURL: selectedTab == 1 ? selectedFileURL : nil,
                        tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    ))
                    errorMessage = message
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 560)
        .onChange(of: selectedTab) { _, _ in
            errorMessage = nil
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                selectedFileURL = urls.first
                if title.trimmedNonEmpty == nil {
                    title = urls.first?.deletingPathExtension().lastPathComponent ?? ""
                }
                errorMessage = nil
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private var canSave: Bool {
        switch selectedTab {
        case 0:
            urlString.trimmedNonEmpty != nil
        case 1:
            selectedFileURL != nil
        default:
            bodyText.trimmedNonEmpty != nil
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
