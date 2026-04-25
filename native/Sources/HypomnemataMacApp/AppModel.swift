import AppKit
import Foundation
import HypomnemataCore
import HypomnemataData
import HypomnemataIngestion
import HypomnemataMedia
import UniformTypeIdentifiers

enum LibraryViewMode: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .list:
            "Lista"
        case .grid:
            "Grid"
        }
    }

    var systemImage: String {
        switch self {
        case .list:
            "list.bullet"
        case .grid:
            "square.grid.2x2"
        }
    }
}

private struct CaptureFilePayload {
    var data: Data
    var originalFilename: String
    var mimeType: String?
    var defaultTitle: String
}

@MainActor
final class AppModel: ObservableObject {
    enum VaultState: Equatable {
        case locked
        case unlocked
        case failed(String)
    }

    @Published var state: VaultState = .locked
    @Published var items: [Item] = []
    @Published var activeKind: ItemKind?
    @Published var activeTag: String?
    @Published var activeFolderID: String?
    @Published var query = ""
    @Published var viewMode: LibraryViewMode = .list
    @Published var selectedItem: Item?
    @Published var selectionMode = false
    @Published var selectedItemIDs: Set<String> = []
    @Published var showCapture = false
    @Published var showChangePassword = false
    @Published var capturePrefill: CaptureDraft?
    @Published var dependencyStatuses: [DependencyStatus] = []
    @Published var kindCounts: [ItemKind: Int] = Dictionary(uniqueKeysWithValues: ItemKind.allCases.map { ($0, 0) })
    @Published var tagCounts: [TagCount] = []
    @Published var folders: [Folder] = []
    @Published var totalItemCount = 0
    @Published var storageBytes: Int64 = 0

    private var database: NativeDatabase?
    private var repository: SQLiteItemRepository?
    private var assetStore: EncryptedAssetStore?
    private var appPaths: AppPaths?
    private var localEventMonitor: Any?
    private var securityObservers: [NSObjectProtocol] = []
    private var autoLockTimer: Timer?
    private var servicesProvider: CaptureServicesProvider?
    private let autoLockInterval: TimeInterval = 15 * 60

    var isUnlocked: Bool {
        if case .unlocked = state {
            return true
        }
        return false
    }

    var activeFolder: Folder? {
        folders.first { $0.id == activeFolderID }
    }

    var selectedItemCount: Int {
        selectedItemIDs.count
    }

    init() {
        refreshDependencies()
        installActivityMonitor()
        installSecurityObservers()
        installCaptureServicesProvider()
    }

    func refreshDependencies() {
        dependencyStatuses = DependencyDoctor().check()
    }

    func unlock(passphrase: String) {
        guard !passphrase.isEmpty else {
            state = .failed(DataError.emptyPassphrase.localizedDescription)
            return
        }
        discardUnlockedState()
        var databaseExists = false
        do {
            let paths = try AppPaths.production()
            databaseExists = FileManager.default.fileExists(atPath: paths.databaseURL.path)
            let db = try NativeDatabase(
                appPaths: paths,
                passphrase: passphrase,
                requireSQLCipher: true
            )
            let assetKeyData: Data
            let store: EncryptedAssetStore
            do {
                assetKeyData = try db.loadOrCreateAssetKeyData()
                store = try EncryptedAssetStore(
                    rootDirectory: paths.assetsDirectory,
                    cacheDirectory: paths.temporaryCacheDirectory,
                    keyData: assetKeyData
                )
            } catch {
                try? db.close()
                throw error
            }

            database = db
            repository = SQLiteItemRepository(database: db)
            appPaths = paths
            assetStore = store
            state = .unlocked
            resetAutoLockTimer()
            refreshLibrary()
        } catch {
            discardUnlockedState()
            state = .failed(unlockFailureMessage(error, databaseExists: databaseExists))
        }
    }

    func lock() {
        let cacheError = clearTemporaryCache()
        let closeError = closeDatabase()
        discardUnlockedState()

        if let message = [cacheError, closeError].compactMap(\.?.localizedDescription).first {
            state = .failed(message)
        } else {
            state = .locked
        }
    }

    func prepareForQuit() {
        _ = clearTemporaryCache()
    }

    private func closeDatabase() -> Error? {
        do {
            try database?.close()
            return nil
        } catch {
            return error
        }
    }

    private func discardUnlockedState() {
        autoLockTimer?.invalidate()
        autoLockTimer = nil
        database = nil
        repository = nil
        assetStore = nil
        appPaths = nil
        query = ""
        activeKind = nil
        activeTag = nil
        activeFolderID = nil
        items = []
        selectedItem = nil
        selectionMode = false
        selectedItemIDs = []
        viewMode = .list
        kindCounts = Dictionary(uniqueKeysWithValues: ItemKind.allCases.map { ($0, 0) })
        tagCounts = []
        folders = []
        totalItemCount = 0
        storageBytes = 0
        showCapture = false
        showChangePassword = false
        capturePrefill = nil
    }

    func recordUserActivity() {
        guard isUnlocked else {
            return
        }
        resetAutoLockTimer()
    }

    func changePassphrase(
        currentPassphrase: String,
        newPassphrase: String,
        confirmation: String
    ) -> String? {
        guard !currentPassphrase.isEmpty else {
            return "Informe a senha atual."
        }
        guard !newPassphrase.isEmpty else {
            return DataError.emptyPassphrase.localizedDescription
        }
        guard newPassphrase == confirmation else {
            return "A nova senha e a confirmação não conferem."
        }
        guard let database, let appPaths else {
            return "Vault não está desbloqueado."
        }

        do {
            let verifier = try NativeDatabase(
                appPaths: appPaths,
                passphrase: currentPassphrase,
                requireSQLCipher: true
            )
            try verifier.close()
            try database.changePassphrase(to: newPassphrase)
            recordUserActivity()
            return nil
        } catch {
            return "Senha atual inválida ou vault inacessível."
        }
    }

    func refreshLibrary() {
        refreshItems()
        refreshSidebarData()
    }

    func refreshItems() {
        guard let repository else {
            return
        }
        do {
            let filter = ItemListFilter(
                kind: activeKind,
                tag: activeTag,
                folderID: activeFolderID
            )
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items = try repository.listItems(filter: filter)
            } else {
                items = try repository.search(query, filter: filter)
            }
            selectedItemIDs.formIntersection(Set(items.map(\.id)))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func clearFilters() {
        activeKind = nil
        activeTag = nil
        activeFolderID = nil
        recordUserActivity()
        refreshItems()
    }

    func toggleKindFilter(_ kind: ItemKind) {
        activeKind = activeKind == kind ? nil : kind
        recordUserActivity()
        refreshItems()
    }

    func toggleTagFilter(_ tag: String) {
        activeTag = activeTag == tag ? nil : tag
        recordUserActivity()
        refreshItems()
    }

    func toggleFolderFilter(_ folderID: String) {
        activeFolderID = activeFolderID == folderID ? nil : folderID
        recordUserActivity()
        refreshItems()
    }

    func count(for kind: ItemKind) -> Int {
        kindCounts[kind, default: 0]
    }

    func openDetail(_ item: Item) {
        guard !selectionMode else {
            toggleItemSelection(item)
            return
        }
        selectedItem = item
        recordUserActivity()
    }

    func toggleSelectionMode() {
        selectionMode.toggle()
        if !selectionMode {
            selectedItemIDs = []
        }
        recordUserActivity()
    }

    func toggleItemSelection(_ item: Item) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
        recordUserActivity()
    }

    func isSelected(_ item: Item) -> Bool {
        selectedItemIDs.contains(item.id)
    }

    func selectVisibleItems() {
        selectedItemIDs = Set(items.map(\.id))
        selectionMode = true
        recordUserActivity()
    }

    func clearSelection() {
        selectedItemIDs = []
        recordUserActivity()
    }

    func openCapture(prefill: CaptureDraft? = nil) {
        capturePrefill = prefill
        showCapture = true
        recordUserActivity()
    }

    func clearCapturePrefill() {
        capturePrefill = nil
    }

    func saveItem(
        id: String,
        title: String,
        note: String,
        bodyText: String,
        tags: [String]
    ) -> String? {
        guard let repository else {
            return "Vault não está desbloqueado."
        }
        do {
            let updated = try repository.patchItem(
                id: id,
                patch: ItemPatch(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                    bodyText: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
                    tags: tags
                )
            )
            selectedItem = updated
            refreshLibrary()
            recordUserActivity()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func deleteItem(_ item: Item) -> String? {
        deleteItems(ids: [item.id])
    }

    func deleteSelectedItems() -> String? {
        deleteItems(ids: Array(selectedItemIDs))
    }

    private func deleteItems(ids: [String]) -> String? {
        guard let repository else {
            return "Vault não está desbloqueado."
        }
        guard !ids.isEmpty else {
            return nil
        }
        do {
            let assets = try repository.assets(forItemIDs: ids)
            try repository.deleteItems(ids: ids)
            for asset in assets {
                try assetStore?.remove(record: asset)
            }
            if let selectedItem, ids.contains(selectedItem.id) {
                self.selectedItem = nil
            }
            selectedItemIDs.subtract(Set(ids))
            if selectedItemIDs.isEmpty {
                selectionMode = false
            }
            refreshLibrary()
            recordUserActivity()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    @discardableResult
    func createCapture(_ draft: CaptureDraft) -> String? {
        guard let repository else {
            return "Vault não está desbloqueado."
        }
        do {
            let (validatedDraft, plan) = try CapturePlanner.validateAndPlan(draft)
            let filePayload = try validatedDraft.fileURL.map(readCaptureFile)
            let createdItem = try repository.createItem(
                kind: plan.kind,
                sourceURL: validatedDraft.sourceURL,
                title: validatedDraft.title ?? filePayload?.defaultTitle,
                note: validatedDraft.note,
                bodyText: validatedDraft.bodyText,
                summary: nil,
                metadataJSON: nil,
                tags: validatedDraft.tags
            )
            var assetID: String?
            if let filePayload {
                guard let assetStore else {
                    try? repository.deleteItems(ids: [createdItem.id])
                    throw DataError.assetStoreUnavailable
                }
                let stored = try assetStore.write(
                    data: filePayload.data,
                    itemID: createdItem.id,
                    role: .original,
                    originalFilename: filePayload.originalFilename,
                    mimeType: filePayload.mimeType
                )
                do {
                    try repository.insertAsset(stored.record)
                    assetID = stored.record.id
                } catch {
                    try? assetStore.remove(record: stored.record)
                    try? repository.deleteItems(ids: [createdItem.id])
                    throw error
                }
            }
            let jobs = try makeJobs(
                kinds: plan.jobs,
                itemID: createdItem.id,
                sourceURL: validatedDraft.sourceURL,
                assetID: assetID
            )
            try repository.insertJobs(jobs)
            capturePrefill = nil
            showCapture = false
            refreshLibrary()
            recordUserActivity()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func makeJobs(kinds: [JobKind], itemID: String, sourceURL: String?, assetID: String?) throws -> [Job] {
        let resolver = JobDependencyResolver()
        return try kinds.map { kind in
            let missingDependencyError = resolver.missingDependencyError(for: kind)
            return Job(
                itemID: itemID,
                kind: kind,
                status: missingDependencyError == nil ? .pending : .failed,
                error: missingDependencyError,
                payloadJSON: try jobPayloadJSON(sourceURL: sourceURL, assetID: assetID)
            )
        }
    }

    @discardableResult
    func openExternalCapture(_ url: URL) -> Bool {
        guard isUnlocked else {
            state = .failed("Desbloqueie o vault antes de receber uma captura externa.")
            return false
        }
        guard let draft = captureDraft(from: url) else {
            return false
        }
        openCapture(prefill: draft)
        return true
    }

    func openExternalCaptureText(_ text: String) -> Bool {
        guard isUnlocked else {
            state = .failed("Desbloqueie o vault antes de receber uma captura externa.")
            return false
        }
        guard let bodyText = text.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return false
        }
        openCapture(prefill: CaptureDraft(bodyText: bodyText))
        return true
    }

    private func captureDraft(from url: URL) -> CaptureDraft? {
        if url.scheme == "http" || url.scheme == "https" {
            return CaptureDraft(sourceURL: url.absoluteString)
        }

        guard url.scheme == "hypomnemata", url.host == "capture" else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        func value(_ name: String) -> String? {
            queryItems.first(where: { $0.name == name })?.value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }

        let tags = value("tags")?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? []

        if let sourceURL = value("url") {
            return CaptureDraft(
                sourceURL: sourceURL,
                title: value("title"),
                note: value("note"),
                tags: tags
            )
        }
        if let bodyText = value("text") {
            return CaptureDraft(
                title: value("title"),
                note: value("note"),
                bodyText: bodyText,
                tags: tags
            )
        }
        return nil
    }

    private func jobPayloadJSON(sourceURL: String?, assetID: String?) throws -> String? {
        var payload: [String: String] = [:]
        if let sourceURL {
            payload["source_url"] = sourceURL
        }
        if let assetID {
            payload["asset_id"] = assetID
        }
        guard !payload.isEmpty else {
            return nil
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)
    }

    private func refreshSidebarData() {
        guard let repository else {
            return
        }
        do {
            totalItemCount = try repository.totalItemCount()
            kindCounts = try repository.itemCountsByKind()
            tagCounts = try repository.tagCounts()
            folders = try repository.listFolders()
            if let appPaths {
                storageBytes = try storageByteCount(at: appPaths.assetsDirectory)
            } else {
                storageBytes = 0
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func storageByteCount(at directory: URL) throws -> Int64 {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return 0
        }
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }

    private func readCaptureFile(_ fileURL: URL) throws -> CaptureFilePayload {
        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: fileURL)
        let extensionName = fileURL.pathExtension
        let mimeType = UTType(filenameExtension: extensionName)?.preferredMIMEType
        return CaptureFilePayload(
            data: data,
            originalFilename: fileURL.lastPathComponent,
            mimeType: mimeType,
            defaultTitle: fileURL.deletingPathExtension().lastPathComponent
        )
    }

    private func clearTemporaryCache() -> Error? {
        do {
            if let assetStore {
                try assetStore.clearTemporaryCache()
            } else if let appPaths {
                try FileManager.default.removeItemIfExists(at: appPaths.temporaryCacheDirectory)
                try FileManager.default.createDirectory(
                    at: appPaths.temporaryCacheDirectory,
                    withIntermediateDirectories: true
                )
            }
            return nil
        } catch {
            return error
        }
    }

    private func installActivityMonitor() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .flagsChanged]
        ) { [weak self] event in
            Task { @MainActor in
                self?.recordUserActivity()
            }
            return event
        }
    }

    private func installSecurityObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ]
        securityObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    if self?.isUnlocked == true {
                        self?.lock()
                    }
                }
            }
        }
    }

    private func installCaptureServicesProvider() {
        let provider = CaptureServicesProvider(model: self)
        NSApplication.shared.servicesProvider = provider
        NSUpdateDynamicServices()
        servicesProvider = provider
    }

    private func resetAutoLockTimer() {
        autoLockTimer?.invalidate()
        guard isUnlocked else {
            autoLockTimer = nil
            return
        }
        let timer = Timer(timeInterval: autoLockInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if self?.isUnlocked == true {
                    self?.lock()
                }
            }
        }
        autoLockTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func unlockFailureMessage(_ error: Error, databaseExists: Bool) -> String {
        if let dataError = error as? DataError {
            return dataError.localizedDescription
        }
        if databaseExists {
            return "Não foi possível abrir o vault existente. Verifique a senha; se ela estiver correta, o banco pode estar corrompido ou inacessível."
        }
        return error.localizedDescription
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        guard fileExists(atPath: url.path) else {
            return
        }
        try removeItem(at: url)
    }
}
