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
                ItemListView(items: model.items)
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

struct ItemListView: View {
    var items: [Item]

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "Nada salvo ainda",
                systemImage: "tray",
                description: Text("Crie uma captura por URL, arquivo ou texto.")
            )
        } else {
            List(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.title ?? item.sourceURL ?? item.kind.rawValue)
                            .font(.headline)
                        Spacer()
                        Text(item.kind.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let sourceURL = item.sourceURL, !sourceURL.isEmpty {
                        Text(sourceURL)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    if let note = item.note, !note.isEmpty {
                        Text(note)
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                    }
                    if !item.tags.isEmpty {
                        Text(item.tags.map { "#\($0)" }.joined(separator: " "))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 5)
            }
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
