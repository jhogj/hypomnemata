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
                Divider()
                ItemListView(items: model.items)
            }
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: $model.activeKind) {
            Section("Tipos") {
                Button("Recentes") {
                    model.activeKind = nil
                    model.refreshItems()
                }
                ForEach(ItemKind.allCases) { kind in
                    Button(kind.displayName) {
                        model.activeKind = kind
                        model.refreshItems()
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Button("Nova captura") {
                    model.showCapture = true
                }
                .buttonStyle(.borderedProminent)
                Button("Bloquear") {
                    model.lock()
                }
                Button("Trocar senha") {
                    model.showChangePassword = true
                }
            }
            .padding()
        }
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
            Button("Buscar") {
                model.refreshItems()
            }
            Button("Nova captura") {
                model.showCapture = true
            }
            .keyboardShortcut("k", modifiers: [.command])
        }
        .padding()
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
