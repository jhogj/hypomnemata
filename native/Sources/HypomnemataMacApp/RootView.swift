import HypomnemataCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.state {
        case .locked:
            VaultLockView()
        case .failed(let message):
            VaultLockView(errorMessage: message)
        case .unlocked:
            LibraryShellView()
                .sheet(isPresented: $model.showCapture) {
                    CaptureSheet()
                }
                .sheet(isPresented: $model.showChangePassword) {
                    ChangePasswordSheet()
                }
                .sheet(item: $model.selectedItem) { item in
                    ItemDetailSheet(item: item)
                }
        }
    }
}

struct VaultLockView: View {
    @EnvironmentObject private var model: AppModel
    @State private var passphrase = ""
    var errorMessage: String?

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Hypomnemata")
                    .font(.system(size: 34, weight: .semibold))
                Text("Vault local criptografado")
                    .foregroundStyle(.secondary)
            }

            SecureField("Senha", text: $passphrase)
                .textFieldStyle(.roundedBorder)
                .frame(width: 360)
                .onSubmit(open)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }

            Button("Abrir ou criar vault") {
                open()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(passphrase.isEmpty)
        }
        .padding(32)
    }

    private func open() {
        model.unlock(passphrase: passphrase)
    }
}

struct LibraryShellView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            VStack(spacing: 0) {
                SearchHeaderView()
                ActiveFilterBar()
                Divider()
                LibraryContentView(items: model.items)
            }
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section {
                SidebarFilterRow(
                    title: "Todos",
                    systemImage: "tray.full",
                    count: model.totalItemCount,
                    isSelected: model.activeKind == nil && model.activeTag == nil && model.activeFolderID == nil
                ) {
                    model.clearFilters()
                }
            }

            Section("Tipos") {
                ForEach(ItemKind.allCases) { kind in
                    SidebarFilterRow(
                        title: kind.displayName,
                        systemImage: kind.systemImage,
                        count: model.count(for: kind),
                        isSelected: model.activeKind == kind
                    ) {
                        model.toggleKindFilter(kind)
                    }
                }
            }

            if !model.tagCounts.isEmpty {
                Section("Tags") {
                    ForEach(model.tagCounts) { tag in
                        SidebarFilterRow(
                            title: "#\(tag.name)",
                            systemImage: "tag",
                            count: tag.count,
                            isSelected: model.activeTag == tag.name
                        ) {
                            model.toggleTagFilter(tag.name)
                        }
                    }
                }
            }

            if !model.folders.isEmpty {
                Section("Pastas") {
                    ForEach(model.folders) { folder in
                        SidebarFilterRow(
                            title: folder.name,
                            systemImage: "folder",
                            count: folder.itemCount,
                            isSelected: model.activeFolderID == folder.id
                        ) {
                            model.toggleFolderFilter(folder.id)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Label(formatBytes(model.storageBytes), systemImage: "externaldrive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button {
                    model.showCapture = true
                } label: {
                    Label("Nova captura", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    model.lock()
                } label: {
                    Label("Bloquear", systemImage: "lock")
                }

                Button {
                    model.showChangePassword = true
                } label: {
                    Label("Trocar senha", systemImage: "key")
                }
            }
            .padding()
        }
    }
}

struct SidebarFilterRow: View {
    var title: String
    var systemImage: String
    var count: Int
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                CountBadge(count: count)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
    }
}

struct CountBadge: View {
    var count: Int

    var body: some View {
        Text(count.formatted())
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }
}

struct ChangePasswordSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassphrase = ""
    @State private var newPassphrase = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Trocar senha")
                .font(.title2.bold())

            SecureField("Senha atual", text: $currentPassphrase)
                .textFieldStyle(.roundedBorder)
            SecureField("Nova senha", text: $newPassphrase)
                .textFieldStyle(.roundedBorder)
            SecureField("Confirmar nova senha", text: $confirmation)
                .textFieldStyle(.roundedBorder)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancelar") {
                    dismiss()
                }
                Button("Salvar") {
                    if let message = model.changePassphrase(
                        currentPassphrase: currentPassphrase,
                        newPassphrase: newPassphrase,
                        confirmation: confirmation
                    ) {
                        errorMessage = message
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(currentPassphrase.isEmpty || newPassphrase.isEmpty || confirmation.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 440)
    }
}

struct SearchHeaderView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            TextField("Buscar", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    model.refreshItems()
                }
            Button {
                model.refreshItems()
            } label: {
                Label("Buscar", systemImage: "magnifyingglass")
            }
            Button {
                model.showCapture = true
            } label: {
                Label("Nova captura", systemImage: "plus")
            }
            .keyboardShortcut("k", modifiers: [.command])

            Picker("Visualização", selection: $model.viewMode) {
                ForEach(LibraryViewMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
        }
        .padding()
    }
}

struct ActiveFilterBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.activeKind != nil || model.activeTag != nil || model.activeFolderID != nil {
            HStack(spacing: 8) {
                if let kind = model.activeKind {
                    FilterChip(title: kind.displayName, systemImage: kind.systemImage) {
                        model.toggleKindFilter(kind)
                    }
                }
                if let tag = model.activeTag {
                    FilterChip(title: "#\(tag)", systemImage: "tag") {
                        model.toggleTagFilter(tag)
                    }
                }
                if let folder = model.activeFolder {
                    FilterChip(title: folder.name, systemImage: "folder") {
                        model.toggleFolderFilter(folder.id)
                    }
                }
                Spacer()
                Button {
                    model.clearFilters()
                } label: {
                    Label("Limpar", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
    }
}

struct FilterChip: View {
    var title: String
    var systemImage: String
    var onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct LibraryContentView: View {
    @EnvironmentObject private var model: AppModel
    var items: [Item]

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "Nada salvo ainda",
                systemImage: "tray",
                description: Text("Crie uma captura por URL, arquivo ou texto.")
            )
        } else {
            switch model.viewMode {
            case .list:
                ItemListView(items: items)
            case .grid:
                ItemGridView(items: items)
            }
        }
    }
}

struct ItemListView: View {
    var items: [Item]

    var body: some View {
        List(items) { item in
            ItemRowView(item: item)
        }
    }
}

struct ItemGridView: View {
    var items: [Item]

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 340), spacing: 12, alignment: .top),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(items) { item in
                    ItemGridCardView(item: item)
                }
            }
            .padding(14)
        }
    }
}

struct ItemRowView: View {
    @EnvironmentObject private var model: AppModel
    var item: Item

    var body: some View {
        Button {
            model.openDetail(item)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                KindIcon(kind: item.kind)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.displayTitle)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text(item.kind.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let sourceURL = item.nonEmptySourceURL {
                        Text(sourceURL)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    if let note = item.nonEmptyNote {
                        Text(note)
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                    } else if let bodyText = item.nonEmptyBodyText {
                        Text(bodyText)
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                    }
                    TagLine(tags: item.tags)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ItemGridCardView: View {
    @EnvironmentObject private var model: AppModel
    var item: Item

    var body: some View {
        Button {
            model.openDetail(item)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    KindIcon(kind: item.kind)
                    Spacer()
                    Text(item.kind.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(item.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let note = item.nonEmptyNote {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                } else if let bodyText = item.nonEmptyBodyText {
                    Text(bodyText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                } else if let sourceURL = item.nonEmptySourceURL {
                    Text(sourceURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
                TagLine(tags: item.tags)
            }
            .padding(12)
            .frame(minHeight: 150, alignment: .topLeading)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct ItemDetailSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var item: Item

    @State private var title: String
    @State private var note: String
    @State private var bodyText: String
    @State private var tags: String
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false

    init(item: Item) {
        self.item = item
        _title = State(initialValue: item.title ?? "")
        _note = State(initialValue: item.note ?? "")
        _bodyText = State(initialValue: item.bodyText ?? "")
        _tags = State(initialValue: item.tags.joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                KindIcon(kind: item.kind)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Detalhe")
                        .font(.title2.bold())
                    Text(item.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding([.horizontal, .top], 22)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    DetailFieldLabel("Título")
                    TextField("Sem título", text: $title)
                        .textFieldStyle(.roundedBorder)

                    if let sourceURL = item.nonEmptySourceURL {
                        DetailFieldLabel("Fonte")
                        Text(sourceURL)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    DetailFieldLabel("Etiquetas")
                    TextField("separadas por vírgula", text: $tags)
                        .textFieldStyle(.roundedBorder)

                    DetailFieldLabel("Nota")
                    TextEditor(text: $note)
                        .frame(minHeight: 110)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6).stroke(.quaternary)
                        }

                    DetailFieldLabel("Texto")
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 170)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6).stroke(.quaternary)
                        }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .padding(22)
            }

            Divider()

            HStack {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Excluir", systemImage: "trash")
                }

                Spacer()

                Button("Cancelar") {
                    dismiss()
                }
                Button {
                    save()
                } label: {
                    Label("Salvar", systemImage: "checkmark")
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 680, height: 640)
        .confirmationDialog(
            "Excluir este item?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Excluir", role: .destructive) {
                delete()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Esta ação remove o item da biblioteca.")
        }
    }

    private func save() {
        let parsedTags = tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let message = model.saveItem(
            id: item.id,
            title: title,
            note: note,
            bodyText: bodyText,
            tags: parsedTags
        ) {
            errorMessage = message
        } else {
            dismiss()
        }
    }

    private func delete() {
        if let message = model.deleteItem(item) {
            errorMessage = message
        } else {
            dismiss()
        }
    }
}

struct DetailFieldLabel: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct KindIcon: View {
    var kind: ItemKind

    var body: some View {
        Image(systemName: kind.systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct TagLine: View {
    var tags: [String]

    var body: some View {
        if !tags.isEmpty {
            Text(tags.map { "#\($0)" }.joined(separator: " "))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
    }
}

private func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    formatter.countStyle = .file
    formatter.includesUnit = true
    formatter.includesCount = true
    return formatter.string(fromByteCount: bytes)
}

private extension Item {
    var displayTitle: String {
        for candidate in [title, sourceURL, note, bodyText] {
            if let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return kind.rawValue
    }

    var nonEmptySourceURL: String? {
        sourceURL?.trimmedNonEmpty
    }

    var nonEmptyNote: String? {
        note?.trimmedNonEmpty
    }

    var nonEmptyBodyText: String? {
        bodyText?.trimmedNonEmpty
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension ItemKind {
    var systemImage: String {
        switch self {
        case .image:
            "photo"
        case .article:
            "doc.text"
        case .video:
            "play.rectangle"
        case .tweet:
            "quote.bubble"
        case .bookmark:
            "bookmark"
        case .note:
            "note.text"
        case .pdf:
            "doc.richtext"
        }
    }
}
