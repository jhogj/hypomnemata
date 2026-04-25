import HypomnemataCore
import AVKit
import PDFKit
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
            .safeAreaInset(edge: .bottom) {
                if model.selectionMode {
                    SelectionToolbar()
                }
            }
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingCreateFolder = false
    @State private var editingFolder: Folder?
    @State private var deletingFolder: Folder?
    @State private var folderError: String?

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

            Section {
                if model.folders.isEmpty {
                    Text("Nenhuma pasta")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.folders) { folder in
                        FolderSidebarRow(
                            folder: folder,
                            title: folder.name,
                            systemImage: "folder",
                            count: folder.itemCount,
                            isSelected: model.activeFolderID == folder.id
                        ) {
                            model.toggleFolderFilter(folder.id)
                        } onRename: {
                            editingFolder = folder
                        } onDelete: {
                            deletingFolder = folder
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Pastas")
                    Spacer()
                    Button {
                        showingCreateFolder = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Criar pasta")
                }
            }
        }
        .sheet(isPresented: $showingCreateFolder) {
            FolderNameSheet(title: "Nova pasta", initialName: "") { name in
                let result = model.createFolder(name: name)
                folderError = result.1
                return result.1
            }
        }
        .sheet(item: $editingFolder) { folder in
            FolderNameSheet(title: "Renomear pasta", initialName: folder.name) { name in
                let message = model.renameFolder(folder, name: name)
                folderError = message
                return message
            }
        }
        .confirmationDialog(
            "Excluir pasta?",
            isPresented: Binding(
                get: { deletingFolder != nil },
                set: { if !$0 { deletingFolder = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Excluir", role: .destructive) {
                if let folder = deletingFolder {
                    folderError = model.deleteFolder(folder)
                }
                deletingFolder = nil
            }
            Button("Cancelar", role: .cancel) {
                deletingFolder = nil
            }
        } message: {
            Text("Os itens não serão apagados, apenas removidos desta pasta.")
        }
        .alert(
            "Pasta",
            isPresented: Binding(
                get: { folderError != nil },
                set: { if !$0 { folderError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                folderError = nil
            }
        } message: {
            Text(folderError ?? "")
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Label(formatBytes(model.storageBytes), systemImage: "externaldrive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button {
                    model.openCapture()
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

struct FolderSidebarRow: View {
    var folder: Folder
    var title: String
    var systemImage: String
    var count: Int
    var isSelected: Bool
    var action: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void

    var body: some View {
        SidebarFilterRow(
            title: title,
            systemImage: systemImage,
            count: count,
            isSelected: isSelected,
            action: action
        )
        .contextMenu {
            Button {
                onRename()
            } label: {
                Label("Renomear", systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Excluir", systemImage: "trash")
            }
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

struct FolderNameSheet: View {
    @Environment(\.dismiss) private var dismiss

    var title: String
    var initialName: String
    var onSave: (String) -> String?

    @State private var name: String
    @State private var errorMessage: String?

    init(title: String, initialName: String, onSave: @escaping (String) -> String?) {
        self.title = title
        self.initialName = initialName
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.bold())

            TextField("Nome", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

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
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
    }

    private func save() {
        let message = onSave(name)
        if let message {
            errorMessage = message
        } else {
            dismiss()
        }
    }
}

struct FolderPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var title: String
    var emptyMessage: String
    var folders: [Folder]
    var allowsCreate: Bool
    var onSelect: (Folder) -> Void
    var onCreate: (String) -> String?

    @State private var newFolderName = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title2.bold())

            if folders.isEmpty {
                ContentUnavailableView(
                    "Nenhuma pasta disponível",
                    systemImage: "folder",
                    description: Text(emptyMessage)
                )
                .frame(minHeight: 120)
            } else {
                List(folders) { folder in
                    Button {
                        onSelect(folder)
                    } label: {
                        HStack {
                            Label(folder.name, systemImage: "folder")
                            Spacer()
                            CountBadge(count: folder.itemCount)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 180)
            }

            if allowsCreate {
                Divider()
                HStack(spacing: 8) {
                    TextField("Nova pasta", text: $newFolderName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(create)
                    Button {
                        create()
                    } label: {
                        Label("Criar", systemImage: "plus")
                    }
                    .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Fechar") {
                    dismiss()
                }
            }
        }
        .padding(22)
        .frame(width: 460, height: 380)
    }

    private func create() {
        let message = onCreate(newFolderName)
        if let message {
            errorMessage = message
        } else {
            dismiss()
        }
    }
}

struct LinkPickerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var currentItemID: String
    var onSelect: (ItemSummary) -> Void

    @State private var query = ""
    @State private var candidates: [ItemSummary] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Inserir link")
                .font(.title2.bold())

            TextField("Buscar item", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit(loadCandidates)

            if candidates.isEmpty {
                ContentUnavailableView(
                    "Nenhum item encontrado",
                    systemImage: "link",
                    description: Text("Busque pelo título, nota ou texto do item.")
                )
                .frame(minHeight: 150)
            } else {
                List(candidates) { summary in
                    Button {
                        onSelect(summary)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            KindIcon(kind: summary.kind)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(summary.displayTitle)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text(summary.id)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 220)
            }

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
            }
        }
        .padding(22)
        .frame(width: 560, height: 440)
        .onAppear(perform: loadCandidates)
        .onChange(of: query) { _, _ in
            loadCandidates()
        }
    }

    private func loadCandidates() {
        let result = model.linkCandidates(query: query, excluding: currentItemID)
        candidates = result.0
        errorMessage = result.1
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
                model.openCapture()
            } label: {
                Label("Nova captura", systemImage: "plus")
            }
            .keyboardShortcut("k", modifiers: [.command])

            Button {
                model.toggleSelectionMode()
            } label: {
                Label(
                    model.selectionMode ? "Cancelar seleção" : "Selecionar",
                    systemImage: model.selectionMode ? "xmark.circle" : "checkmark.circle"
                )
            }

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

    @State private var player: AVPlayer?
    @State private var videoError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if model.selectionMode {
                    SelectionIndicator(isSelected: model.isSelected(item))
                }
                ThumbnailOrKindView(item: item, size: CGSize(width: 64, height: 48))
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
                if item.kind == .video {
                    Button {
                        toggleInlinePlayback()
                    } label: {
                        Image(systemName: player == nil ? "play.circle.fill" : "stop.circle")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .help(player == nil ? "Reproduzir vídeo" : "Parar vídeo")
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                openDetail()
            }

            if let player {
                VideoPlayer(player: player)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if let videoError {
                Text(videoError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .listRowBackground(model.isSelected(item) ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    private func toggleInlinePlayback() {
        if let player {
            player.pause()
            self.player = nil
            return
        }
        let result = model.playableVideoURL(for: item)
        if let url = result.0 {
            let player = AVPlayer(url: url)
            self.player = player
            videoError = nil
            player.play()
        } else {
            videoError = result.1
        }
    }

    private func openDetail() {
        let seconds = player?.currentTime().seconds
        player?.pause()
        model.openDetail(item, videoStartTime: seconds?.isFinite == true ? seconds : nil)
    }
}

struct ItemGridCardView: View {
    @EnvironmentObject private var model: AppModel
    var item: Item

    @State private var player: AVPlayer?
    @State private var videoError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if model.thumbnailURL(for: item) != nil {
                ThumbnailOrKindView(item: item, size: CGSize(width: 0, height: 160))
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if model.selectionMode {
                        SelectionIndicator(isSelected: model.isSelected(item))
                    }
                    KindIcon(kind: item.kind)
                    Spacer()
                    Text(item.kind.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if item.kind == .video {
                        Button {
                            toggleInlinePlayback()
                        } label: {
                            Image(systemName: player == nil ? "play.circle.fill" : "stop.circle")
                                .font(.title3)
                        }
                        .buttonStyle(.borderless)
                        .help(player == nil ? "Reproduzir vídeo" : "Parar vídeo")
                    }
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
                if let videoError {
                    Text(videoError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .padding(12)
        }
        .frame(minHeight: 170, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(model.isSelected(item) ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: model.isSelected(item) ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            openDetail()
        }
    }

    private func toggleInlinePlayback() {
        if let player {
            player.pause()
            self.player = nil
            return
        }
        let result = model.playableVideoURL(for: item)
        if let url = result.0 {
            let player = AVPlayer(url: url)
            self.player = player
            videoError = nil
            player.play()
        } else {
            videoError = result.1
        }
    }

    private func openDetail() {
        let seconds = player?.currentTime().seconds
        player?.pause()
        model.openDetail(item, videoStartTime: seconds?.isFinite == true ? seconds : nil)
    }
}

struct ThumbnailOrKindView: View {
    @EnvironmentObject private var model: AppModel
    var item: Item
    var size: CGSize

    var body: some View {
        if
            let url = model.thumbnailURL(for: item),
            let image = NSImage(contentsOf: url)
        {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width > 0 ? size.width : nil, height: size.height)
                .frame(maxWidth: size.width > 0 ? size.width : .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary)
                }
        } else {
            KindIcon(kind: item.kind)
        }
    }
}

struct SelectionIndicator: View {
    var isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(width: 22, height: 22)
            .accessibilityLabel(isSelected ? "Selecionado" : "Não selecionado")
    }
}

struct SelectionToolbar: View {
    @EnvironmentObject private var model: AppModel
    @State private var showDeleteConfirmation = false
    @State private var showFolderPicker = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 6) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack(spacing: 12) {
                Text("\(model.selectedItemCount) selecionado\(model.selectedItemCount == 1 ? "" : "s")")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()

                Spacer()

                Button {
                    model.selectVisibleItems()
                } label: {
                    Label("Selecionar visíveis", systemImage: "checklist")
                }
                .disabled(model.items.isEmpty)

                Button {
                    model.clearSelection()
                } label: {
                    Label("Limpar", systemImage: "xmark")
                }
                .disabled(model.selectedItemCount == 0)

                Button {
                    showFolderPicker = true
                } label: {
                    Label("Adicionar à pasta", systemImage: "folder.badge.plus")
                }
                .disabled(model.selectedItemCount == 0)

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Excluir", systemImage: "trash")
                }
                .disabled(model.selectedItemCount == 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerSheet(
                title: "Adicionar à pasta",
                emptyMessage: "Crie uma pasta para organizar os itens selecionados.",
                folders: model.folders,
                allowsCreate: true
            ) { folder in
                errorMessage = model.addSelectedItems(to: folder)
                if errorMessage == nil {
                    showFolderPicker = false
                }
            } onCreate: { name in
                let result = model.createFolder(name: name)
                if let folder = result.0 {
                    errorMessage = model.addSelectedItems(to: folder)
                    if errorMessage == nil {
                        showFolderPicker = false
                    }
                    return errorMessage
                }
                errorMessage = result.1
                return result.1
            }
        }
        .confirmationDialog(
            "Excluir itens selecionados?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Excluir", role: .destructive) {
                if let message = model.deleteSelectedItems() {
                    errorMessage = message
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Esta ação remove os itens e seus assets criptografados.")
        }
    }
}

struct ItemDetailSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var item: Item

    @State private var title: String
    @State private var summary: String
    @State private var note: String
    @State private var bodyText: String
    @State private var tags: String
    @State private var itemFolders: [Folder] = []
    @State private var linkedItems: [ItemSummary] = []
    @State private var backlinks: [ItemSummary] = []
    @State private var assetPreviews: [AssetPreview] = []
    @State private var selectedAssetPreviewID: String?
    @State private var detailVideoStartTime: Double?
    @State private var showFolderPicker = false
    @State private var linkPickerTarget: LinkInsertionTarget?
    @State private var errorMessage: String?
    @State private var aiBusy = false
    @State private var showDeleteConfirmation = false
    @State private var itemJobs: [Job] = []
    @State private var jobRefreshTimer: Timer?
    @State private var chatMode = false
    @State private var chatMessages: [ChatMessage] = []
    @State private var chatInput = ""
    @State private var chatStreamingText = ""
    @State private var chatBusy = false
    @State private var showClearChatConfirmation = false

    init(item: Item) {
        self.item = item
        _title = State(initialValue: item.title ?? "")
        _summary = State(initialValue: item.summary ?? "")
        _note = State(initialValue: item.note ?? "")
        _bodyText = State(initialValue: item.bodyText ?? "")
        _tags = State(initialValue: item.tags.joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                KindIcon(kind: item.kind)
                VStack(alignment: .leading, spacing: 2) {
                    Text(chatMode ? "Chat com documento" : "Detalhe")
                        .font(.title2.bold())
                    Text(item.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.chatAvailable(for: item) {
                    Button {
                        toggleChatMode()
                    } label: {
                        Label(
                            chatMode ? "Voltar à edição" : "Chat com documento",
                            systemImage: chatMode ? "doc.text" : "bubble.left.and.bubble.right"
                        )
                        .labelStyle(.iconOnly)
                    }
                    .help(chatMode ? "Voltar à edição" : "Chat com documento")
                    .buttonStyle(.borderless)
                    .controlSize(.large)
                }
            }
            .padding([.horizontal, .top], 22)
            .padding(.bottom, 14)

            Divider()

            if chatMode {
                ChatPanel(
                    messages: chatMessages,
                    streamingText: chatStreamingText,
                    input: $chatInput,
                    busy: chatBusy,
                    onSend: { sendChatMessage() },
                    onClear: { showClearChatConfirmation = true }
                )
            } else {
                detailScrollView
            }

            Divider()

            HStack {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Excluir", systemImage: "trash")
                }

                Spacer()

                Button("Fechar") {
                    dismiss()
                }
                if !chatMode {
                    Button {
                        save()
                    } label: {
                        Label("Salvar", systemImage: "checkmark")
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 680, height: 640)
        .onAppear {
            detailVideoStartTime = model.consumeDetailVideoStartTime(for: item)
            loadOrganization()
            loadChatHistory()
            startJobRefreshIfNeeded()
        }
        .onDisappear {
            stopJobRefresh()
        }
        .onChange(of: itemJobs) { _, jobs in
            if jobs.contains(where: { $0.status == .running || $0.status == .pending }) {
                startJobRefreshIfNeeded()
            } else {
                stopJobRefresh()
            }
        }
        .onChange(of: model.runningJobIDs) { _, _ in
            loadJobs()
        }
        .confirmationDialog(
            "Limpar a conversa deste item?",
            isPresented: $showClearChatConfirmation,
            titleVisibility: .visible
        ) {
            Button("Limpar", role: .destructive) {
                clearChat()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Todas as mensagens trocadas serão removidas.")
        }
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerSheet(
                title: "Adicionar a pasta",
                emptyMessage: "Crie uma pasta para organizar este item.",
                folders: model.folders.filter { folder in
                    !itemFolders.contains(where: { $0.id == folder.id })
                },
                allowsCreate: true
            ) { folder in
                if let message = model.addItem(item, to: folder) {
                    errorMessage = message
                } else {
                    loadFolders()
                    showFolderPicker = false
                }
            } onCreate: { name in
                let result = model.createFolder(name: name)
                guard let folder = result.0 else {
                    errorMessage = result.1
                    return result.1
                }
                if let message = model.addItem(item, to: folder) {
                    errorMessage = message
                    return message
                }
                loadFolders()
                showFolderPicker = false
                return nil
            }
        }
        .sheet(item: $linkPickerTarget) { target in
            LinkPickerSheet(currentItemID: item.id) { summary in
                insertLink(to: summary, target: target)
                linkPickerTarget = nil
            }
        }
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

    private var detailScrollView: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !assetPreviews.isEmpty {
                        AssetPreviewPanel(
                            previews: assetPreviews,
                            selectedID: $selectedAssetPreviewID,
                            videoStartTime: detailVideoStartTime
                        )
                    }

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

                    HStack {
                        DetailFieldLabel("Resumo")
                        Spacer()
                        if aiBusy {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button {
                            generateSummary()
                        } label: {
                            Label("Gerar resumo", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderless)
                        .disabled(aiBusy)
                    }
                    TextEditor(text: $summary)
                        .frame(minHeight: 90)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6).stroke(.quaternary)
                        }

                    HStack {
                        DetailFieldLabel("Pastas")
                        Spacer()
                        Button {
                            showFolderPicker = true
                        } label: {
                            Label("Adicionar", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.borderless)
                    }
                    FolderChipLine(folders: itemFolders) { folder in
                        if let message = model.removeItem(item, from: folder) {
                            errorMessage = message
                        } else {
                            loadFolders()
                        }
                    }

                    DetailFieldLabel("Links")
                    RelatedItemLine(
                        emptyText: "Nenhum link saindo deste item",
                        items: linkedItems
                    ) { summary in
                        openRelated(summary)
                    }

                    DetailFieldLabel("Backlinks")
                    RelatedItemLine(
                        emptyText: "Nenhum item aponta para este",
                        items: backlinks
                    ) { summary in
                        openRelated(summary)
                    }

                    DetailFieldLabel("Etiquetas")
                    HStack(spacing: 8) {
                        TextField("separadas por vírgula", text: $tags)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            generateAutotags()
                        } label: {
                            Label("Sugerir tags", systemImage: "tag")
                        }
                        .buttonStyle(.borderless)
                        .disabled(aiBusy)
                    }

                    if !itemJobs.isEmpty {
                        DetailFieldLabel("Tarefas")
                        JobStatusList(
                            jobs: itemJobs,
                            runningJobIDs: model.runningJobIDs
                        ) { job in
                            retryJob(job)
                        }
                    }

                    HStack {
                        DetailFieldLabel("Nota")
                        Spacer()
                        Button {
                            linkPickerTarget = .note
                        } label: {
                            Label("Inserir link", systemImage: "link.badge.plus")
                        }
                        .buttonStyle(.borderless)
                    }
                    TextEditor(text: $note)
                        .frame(minHeight: 110)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6).stroke(.quaternary)
                        }

                    HStack {
                        DetailFieldLabel("Texto")
                        Spacer()
                        Button {
                            linkPickerTarget = .bodyText
                        } label: {
                            Label("Inserir link", systemImage: "link.badge.plus")
                        }
                        .buttonStyle(.borderless)
                    }
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
    }

    private func save() {
        if let message = model.saveItem(
            id: item.id,
            title: title,
            summary: summary,
            note: note,
            bodyText: bodyText,
            tags: parsedTags()
        ) {
            errorMessage = message
        } else {
            loadOrganization()
            dismiss()
        }
    }

    private func generateSummary() {
        aiBusy = true
        errorMessage = nil
        Task {
            let result = await model.generateSummary(title: title, note: note, bodyText: bodyText)
            if let generated = result.0 {
                summary = generated
            }
            errorMessage = result.1
            aiBusy = false
        }
    }

    private func generateAutotags() {
        aiBusy = true
        errorMessage = nil
        let currentTags = parsedTags()
        Task {
            let result = await model.generateAutotags(
                title: title,
                note: note,
                bodyText: bodyText,
                existingTags: currentTags
            )
            tags = result.0.joined(separator: ", ")
            errorMessage = result.1
            aiBusy = false
        }
    }

    private func parsedTags() -> [String] {
        tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func delete() {
        if let message = model.deleteItem(item) {
            errorMessage = message
        } else {
            dismiss()
        }
    }

    private func loadFolders() {
        let result = model.foldersForItem(item)
        itemFolders = result.0
        if let message = result.1 {
            errorMessage = message
        }
    }

    private func loadOrganization() {
        loadAssetPreviews()
        loadFolders()
        let linkedResult = model.linkedItems(from: item)
        linkedItems = linkedResult.0
        if let message = linkedResult.1 {
            errorMessage = message
        }
        let backlinkResult = model.backlinks(to: item)
        backlinks = backlinkResult.0
        if let message = backlinkResult.1 {
            errorMessage = message
        }
        loadJobs()
    }

    private func loadJobs() {
        let result = model.jobs(for: item)
        itemJobs = result.0
        if let message = result.1 {
            errorMessage = message
        }
    }

    private func retryJob(_ job: Job) {
        if let message = model.retryJob(job) {
            errorMessage = message
        }
        loadJobs()
        startJobRefreshIfNeeded()
    }

    private func toggleChatMode() {
        chatMode.toggle()
        if chatMode {
            loadChatHistory()
        }
    }

    private func loadChatHistory() {
        let result = model.chatHistory(for: item)
        chatMessages = result.0
        if let message = result.1 {
            errorMessage = message
        }
    }

    private func sendChatMessage() {
        let trimmed = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !chatBusy else {
            return
        }
        chatInput = ""
        chatStreamingText = ""
        chatBusy = true
        errorMessage = nil
        let snapshot = item
        Task {
            let message = await model.sendChatMessage(item: snapshot, userContent: trimmed) { chunk in
                chatStreamingText += chunk
            }
            if let message {
                errorMessage = message
            }
            chatStreamingText = ""
            chatBusy = false
            loadChatHistory()
        }
    }

    private func clearChat() {
        if let message = model.clearChatHistory(for: item) {
            errorMessage = message
        }
        loadChatHistory()
    }

    private func startJobRefreshIfNeeded() {
        guard jobRefreshTimer == nil else {
            return
        }
        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                loadJobs()
            }
        }
        jobRefreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopJobRefresh() {
        jobRefreshTimer?.invalidate()
        jobRefreshTimer = nil
    }

    private func loadAssetPreviews() {
        let result = model.assetPreviews(for: item)
        assetPreviews = result.0
        if selectedAssetPreviewID == nil {
            selectedAssetPreviewID = assetPreviews.first?.id
        }
        if let message = result.1 {
            errorMessage = message
        }
    }

    private func insertLink(to summary: ItemSummary, target: LinkInsertionTarget) {
        let link = "[[\(summary.id)|\(summary.displayTitle)]]"
        switch target {
        case .note:
            note = note.appendingLink(link)
        case .bodyText:
            bodyText = bodyText.appendingLink(link)
        }
    }

    private func openRelated(_ summary: ItemSummary) {
        if let message = model.openItem(id: summary.id) {
            errorMessage = message
        }
    }
}

enum LinkInsertionTarget: String, Identifiable {
    case note
    case bodyText

    var id: String { rawValue }
}

struct ChatPanel: View {
    var messages: [ChatMessage]
    var streamingText: String
    @Binding var input: String
    var busy: Bool
    var onSend: () -> Void
    var onClear: () -> Void

    @State private var cursorVisible = true
    private let cursorTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty && streamingText.isEmpty {
                            Text("Faça uma pergunta sobre este item. As respostas usam apenas o conteúdo armazenado.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.top, 12)
                        }
                        ForEach(messages) { message in
                            ChatBubble(role: message.role, content: message.content)
                                .id(message.id)
                        }
                        if !streamingText.isEmpty || busy {
                            ChatBubble(
                                role: .assistant,
                                content: displayedStreamingText
                            )
                            .id("streaming")
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToEnd(proxy)
                }
                .onChange(of: streamingText) { _, _ in
                    scrollToEnd(proxy)
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Pergunte algo sobre o documento", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .disabled(busy)
                    .onSubmit { onSend() }
                Button {
                    onSend()
                } label: {
                    Label("Enviar", systemImage: "paperplane.fill")
                        .labelStyle(.iconOnly)
                }
                .keyboardShortcut(.return)
                .disabled(busy || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(role: .destructive) {
                    onClear()
                } label: {
                    Label("Limpar", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .help("Limpar conversa")
                .disabled(busy || (messages.isEmpty && streamingText.isEmpty))
            }
            .padding(12)
        }
        .onReceive(cursorTimer) { _ in
            cursorVisible.toggle()
        }
    }

    private var displayedStreamingText: String {
        if streamingText.isEmpty {
            return cursorVisible ? "▌" : " "
        }
        return streamingText + (cursorVisible ? "▌" : " ")
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if !streamingText.isEmpty || busy {
            proxy.scrollTo("streaming", anchor: .bottom)
        } else if let last = messages.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}

struct ChatBubble: View {
    var role: ChatMessage.Role
    var content: String

    var body: some View {
        HStack(alignment: .top) {
            if role == .user {
                Spacer(minLength: 40)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(role == .user ? "Você" : "Assistente")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(content)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(role == .user ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.18))
            )
            if role == .assistant {
                Spacer(minLength: 40)
            }
        }
    }
}

struct JobStatusList: View {
    var jobs: [Job]
    var runningJobIDs: Set<String>
    var onRetry: (Job) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(jobs) { job in
                JobStatusRow(
                    job: effectiveJob(for: job),
                    onRetry: onRetry
                )
            }
        }
    }

    private func effectiveJob(for job: Job) -> Job {
        if runningJobIDs.contains(job.id), job.status != .running {
            var copy = job
            copy.status = .running
            return copy
        }
        return job
    }
}

struct JobStatusRow: View {
    var job: Job
    var onRetry: (Job) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            statusIcon
                .frame(width: 16, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayName(for: job.kind))
                        .font(.callout.weight(.medium))
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text(displayStatus(for: job.status))
                        .font(.caption)
                        .foregroundStyle(statusColor)
                    if job.attempts > 0 {
                        Text("· tentativas: \(job.attempts)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = job.error, job.status == .failed {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if job.status == .failed {
                Button {
                    onRetry(job)
                } label: {
                    Label("Tentar novamente", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary.opacity(0.4))
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .pending:
            .secondary
        case .running:
            .blue
        case .done:
            .green
        case .failed:
            .orange
        }
    }

    private func displayName(for kind: JobKind) -> String {
        switch kind {
        case .scrapeArticle: "Extrair artigo"
        case .downloadMedia: "Baixar mídia"
        case .generateThumbnail: "Gerar miniatura"
        case .runOCR: "Extrair texto (OCR)"
        case .summarize: "Gerar resumo (IA)"
        case .autotag: "Sugerir etiquetas (IA)"
        }
    }

    private func displayStatus(for status: JobStatus) -> String {
        switch status {
        case .pending: "pendente"
        case .running: "em execução"
        case .done: "concluída"
        case .failed: "falhou"
        }
    }
}

struct AssetPreviewPanel: View {
    var previews: [AssetPreview]
    @Binding var selectedID: String?
    var videoStartTime: Double?

    private var selectedPreview: AssetPreview? {
        previews.first { $0.id == selectedID } ?? previews.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DetailFieldLabel("Preview")

            if previews.count > 1 {
                Picker("Asset", selection: Binding(
                    get: { selectedPreview?.id ?? previews[0].id },
                    set: { selectedID = $0 }
                )) {
                    ForEach(previews) { preview in
                        Text(preview.displayName).tag(preview.id)
                    }
                }
                .pickerStyle(.menu)
            }

            if let selectedPreview {
                AssetPreviewView(preview: selectedPreview, videoStartTime: videoStartTime)
                    .id(selectedPreview.id)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct AssetPreviewView: View {
    var preview: AssetPreview
    var videoStartTime: Double?

    var body: some View {
        switch preview.kind {
        case .image:
            ImagePreview(url: preview.temporaryURL, displayName: preview.displayName)
        case .pdf:
            PDFPreview(url: preview.temporaryURL)
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary)
                }
        case .video:
            VideoAssetPreview(url: preview.temporaryURL, startTime: videoStartTime)
        case .file:
            FilePreview(preview: preview)
        }
    }
}

struct VideoAssetPreview: View {
    var url: URL
    var startTime: Double?

    @State private var player: AVPlayer
    @State private var didApplyStartTime = false

    init(url: URL, startTime: Double?) {
        self.url = url
        self.startTime = startTime
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary)
            }
            .onAppear {
                guard !didApplyStartTime, let startTime, startTime > 0 else {
                    return
                }
                didApplyStartTime = true
                player.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
                player.play()
            }
    }
}

struct ImagePreview: View {
    var url: URL
    var displayName: String

    var body: some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 360)
                .frame(maxWidth: .infinity)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        } else {
            HStack {
                Image(systemName: "photo")
                Text(displayName)
                    .lineLimit(1)
                Spacer()
            }
            .padding(12)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct PDFPreview: NSViewRepresentable {
    var url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = PDFDocument(url: url)
    }
}

struct FilePreview: View {
    var preview: AssetPreview

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(preview.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(preview.record.mimeType ?? "Arquivo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ByteCountFormatter.string(fromByteCount: preview.record.byteCount, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
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

struct FolderChipLine: View {
    var folders: [Folder]
    var onRemove: (Folder) -> Void

    var body: some View {
        if folders.isEmpty {
            Text("Nenhuma pasta")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            FlowLayout(spacing: 8) {
                ForEach(folders) { folder in
                    Button {
                        onRemove(folder)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                            Text(folder.name)
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
                    .help("Remover desta pasta")
                }
            }
        }
    }
}

struct RelatedItemLine: View {
    var emptyText: String
    var items: [ItemSummary]
    var onOpen: (ItemSummary) -> Void

    var body: some View {
        if items.isEmpty {
            Text(emptyText)
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items) { summary in
                    Button {
                        onOpen(summary)
                    } label: {
                        HStack(spacing: 8) {
                            KindIcon(kind: summary.kind)
                            Text(summary.displayTitle)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 480
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
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

private extension ItemSummary {
    var displayTitle: String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return kind.rawValue
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func appendingLink(_ link: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return link
        }
        return self + "\n" + link
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
