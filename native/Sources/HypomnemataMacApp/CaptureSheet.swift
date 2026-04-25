import HypomnemataCore
import HypomnemataIngestion
import SwiftUI

struct CaptureSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab = 0
    @State private var urlString = ""
    @State private var title = ""
    @State private var note = ""
    @State private var bodyText = ""
    @State private var tags = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nova captura")
                .font(.title2.bold())

            Picker("Tipo", selection: $selectedTab) {
                Text("URL").tag(0)
                Text("Texto").tag(1)
            }
            .pickerStyle(.segmented)

            if selectedTab == 0 {
                TextField("https://...", text: $urlString)
                    .textFieldStyle(.roundedBorder)
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

            HStack {
                Spacer()
                Button("Cancelar") {
                    dismiss()
                }
                Button("Salvar") {
                    model.createCapture(CaptureDraft(
                        sourceURL: urlString.isEmpty ? nil : urlString,
                        title: title.isEmpty ? nil : title,
                        note: note.isEmpty ? nil : note,
                        bodyText: bodyText.isEmpty ? nil : bodyText,
                        tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    ))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedTab == 0 ? urlString.isEmpty : bodyText.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}
