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
    @State private var selectedFileURL: URL?
    @State private var urlAsAudio = false
    @State private var showingFileImporter = false
    @State private var errorMessage: String?
    @State private var didApplyPrefill = false

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
                VStack(alignment: .leading, spacing: 8) {
                    TextField("https://...", text: $urlString)
                        .textFieldStyle(.roundedBorder)
                    Toggle("Salvar mídia como áudio", isOn: $urlAsAudio)
                }
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
                    model.clearCapturePrefill()
                    dismiss()
                }
                Button("Salvar") {
                    let message = model.createCapture(CaptureDraft(
                        explicitKind: selectedTab == 0 && urlAsAudio ? .audio : nil,
                        sourceURL: selectedTab == 0 ? urlString.trimmedNonEmpty : nil,
                        title: title.trimmedNonEmpty,
                        note: note.trimmedNonEmpty,
                        bodyText: selectedTab == 2 ? bodyText.trimmedNonEmpty : nil,
                        fileURL: selectedTab == 1 ? selectedFileURL : nil,
                        tags: []
                    ))
                    errorMessage = message
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 560)
        .onAppear(perform: applyPrefillIfNeeded)
        .onChange(of: selectedTab) { _, _ in
            errorMessage = nil
            if selectedTab != 0 {
                urlAsAudio = false
            }
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

    private func applyPrefillIfNeeded() {
        guard !didApplyPrefill, let draft = model.capturePrefill else {
            return
        }
        didApplyPrefill = true
        title = draft.title ?? ""
        note = draft.note ?? ""
        if let sourceURL = draft.sourceURL {
            selectedTab = 0
            urlString = sourceURL
        } else if let fileURL = draft.fileURL {
            selectedTab = 1
            selectedFileURL = fileURL
        } else if let text = draft.bodyText {
            selectedTab = 2
            bodyText = text
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
