import AppKit
import Foundation
import HypomnemataAI
import HypomnemataCore
import HypomnemataData
import HypomnemataIngestion
import HypomnemataMedia
import os
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

struct AssetPreview: Identifiable, Equatable {
    enum Kind: Equatable {
        case image
        case pdf
        case video
        case file
    }

    var id: String { record.id }
    var record: AssetRecord
    var temporaryURL: URL
    var kind: Kind
    var displayName: String
}

final class OptimizationCancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

private final class LockedDateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date?

    func shouldLog(now: Date, interval: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let value, now.timeIntervalSince(value) < interval else {
            value = now
            return true
        }
        return false
    }
}

enum OptimizationState {
    case idle
    case running(progress: VideoOptimizationProgress, startedAt: Date, cancelToken: OptimizationCancelToken)
    case succeeded(beforeBytes: Int64, afterBytes: Int64)
    case alreadyOptimized(bytes: Int64)
    case failed(message: String)
}

@MainActor
final class AppModel: ObservableObject, @unchecked Sendable {
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
    @Published var itemThumbnailURLs: [String: URL] = [:]
    @Published var runningJobIDs: Set<String> = []
    @Published var optimizationState: [String: OptimizationState] = [:]

    private var database: NativeDatabase?
    private var repository: SQLiteItemRepository?
    private var assetStore: EncryptedAssetStore?
    private var llmSettingsStore: LLMSettingsStore?
    private var appPaths: AppPaths?
    private var localEventMonitor: Any?
    private var securityObservers: [NSObjectProtocol] = []
    private var autoLockTimer: Timer?
    private var servicesProvider: CaptureServicesProvider?
    private var detailVideoStartTimes: [String: Double] = [:]
    private var videoPosterURLs: [String: URL] = [:]
    private let autoLockInterval: TimeInterval = 15 * 60
    private let optimizationLogger = Logger(subsystem: "Hypomnemata", category: "optimizeVideo")

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

            let repo = SQLiteItemRepository(database: db)
            database = db
            repository = repo
            llmSettingsStore = LLMSettingsStore(database: db)
            appPaths = paths
            assetStore = store
            runStartupRecovery(repository: repo, assetStore: store)
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
        llmSettingsStore = nil
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
        itemThumbnailURLs = [:]
        runningJobIDs = []
        optimizationState = [:]
        detailVideoStartTimes = [:]
        videoPosterURLs = [:]
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
            refreshItemThumbnails(for: items)
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

    func openDetail(_ item: Item, videoStartTime: Double? = nil) {
        guard !selectionMode else {
            toggleItemSelection(item)
            return
        }
        if let videoStartTime, videoStartTime > 0 {
            detailVideoStartTimes[item.id] = videoStartTime
        } else {
            detailVideoStartTimes[item.id] = nil
        }
        selectedItem = item
        recordUserActivity()
    }

    func openItem(id: String) -> String? {
        guard let repository else {
            return "Vault não está desbloqueado."
        }
        do {
            selectedItem = try repository.item(id: id)
            detailVideoStartTimes[id] = nil
            recordUserActivity()
            return nil
        } catch {
            return error.localizedDescription
        }
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

    func createFolder(name: String) -> (Folder?, String?) {
        guard let repository else {
            return (nil, "Vault não está desbloqueado.")
        }
        do {
            let folder = try repository.createFolder(name: name)
            refreshSidebarData()
            recordUserActivity()
            return (folder, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    func renameFolder(_ folder: Folder, name: String) -> String? {
        guard let repository else {
            return "Vault não está desbloqueado."
        }
        do {
            _ = try repository.renameFolder(id: folder.id, name: name)
            refreshLibrary()
            recordUserActivity()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func deleteFolder(_ folder: Folder) -> String? {
        guard let repository else {
            return "Vault não está desbloqueado."
        }
        do {
            try repository.deleteFolder(id: folder.id)
            if activeFolderID == folder.id {
                activeFolderID = nil
            }
            refreshLibrary()
            recordUserActivity()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func addSelectedItems(to folder: Folder) -> String? {
        guard let repository else {
            return "Vault não está desbloqueado."
        }
        let ids = Array(selectedItemIDs)
        guard !ids.isEmpty else {
            return nil
        }
        do {
            try repository.addItems(ids, toFolder: folder.id)
            refreshLibrary()
            recordUserActivity()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func foldersForItem(_ item: Item) -> ([Folder], String?) {
        guard let repository else {
            return ([], "Vault não está desbloqueado.")
        }
        do {
            return (try repository.folders(forItemID: item.id), nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }

    func addItem(_ item: Item, to folder: Folder) -> String? {
        guard let repository else {
            return "Vault não está desbloqueado."
        }
        do {
            try repository.addItems([item.id], toFolder: folder.id)
            refreshLibrary()
            recordUserActivity()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func removeItem(_ item: Item, from folder: Folder) -> String? {
        guard let repository else {
            return "Vault não está desbloqueado."
        }
        do {
            try repository.removeItems([item.id], fromFolder: folder.id)
            refreshLibrary()
            recordUserActivity()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func assetPreviews(for item: Item) -> ([AssetPreview], String?) {
        guard let repository, let assetStore else {
            return ([], "Vault não está desbloqueado.")
        }
        do {
            let records = try repository.assets(forItemID: item.id)
            let previews = try records.filter { $0.role != .thumbnail }.map { record in
                let url = try assetStore.decryptToTemporaryFile(record: record)
                return AssetPreview(
                    record: record,
                    temporaryURL: url,
                    kind: previewKind(for: record, url: url),
                    displayName: record.originalFilename?.isEmpty == false ? record.originalFilename! : record.id
                )
            }
            return (previews, nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }

    func thumbnailURL(for item: Item) -> URL? {
        itemThumbnailURLs[item.id]
    }

    func videoPosterURL(for item: Item) -> URL? {
        if let cached = videoPosterURLs[item.id] {
            return cached
        }
        guard let repository, let assetStore else {
            return nil
        }
        do {
            let records = try repository.assets(forItemID: item.id)
            guard let record = records.first(where: { $0.role == .thumbnail })
                ?? records.first(where: { $0.role == .heroImage })
            else {
                return nil
            }
            let url = try assetStore.decryptToTemporaryFile(record: record)
            videoPosterURLs[item.id] = url
            return url
        } catch {
            return nil
        }
    }

    func playableVideoURL(for item: Item) -> (URL?, String?) {
        guard let repository, let assetStore else {
            return (nil, "Vault não está desbloqueado.")
        }
        do {
            guard let record = try repository.assets(forItemID: item.id).first(where: isPlayableMediaAsset) else {
                return (nil, "Este item não tem mídia local para reproduzir.")
            }
            return (try assetStore.decryptToTemporaryFile(record: record), nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    func consumeDetailVideoStartTime(for item: Item) -> Double? {
        detailVideoStartTimes.removeValue(forKey: item.id)
    }

    func optimizableVideoAsset(for item: Item) -> (AssetRecord?, String?) {
        guard let repository else {
            return (nil, "Vault não está desbloqueado.")
        }
        do {
            let records = try repository.assets(forItemID: item.id)
            guard item.kind == .video || item.kind == .tweet else {
                return (nil, nil)
            }
            return (records.first { VideoOptimizationService.isVideoAsset($0) && $0.optimizedAt == nil }, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    func startVideoOptimization(for item: Item, assetID: String) -> String? {
        guard let repository else {
            return "Vault não está desbloqueado."
        }
        guard !isOptimizationRunning(for: item.id) else {
            return nil
        }
        do {
            guard let record = try repository.assets(forItemID: item.id).first(where: { $0.id == assetID }) else {
                return "Asset de vídeo não encontrado para otimização."
            }
            if let dependencyMessage = videoOptimizationDependencyMessage() {
                return dependencyMessage
            }
            if let spaceMessage = insufficientDiskSpaceMessage(for: record) {
                return spaceMessage
            }
            guard record.optimizedAt == nil else {
                return "Este vídeo já foi otimizado."
            }
            let job = Job(
                itemID: item.id,
                kind: .optimizeVideo,
                payloadJSON: try Self.assetPayloadJSON(assetID: record.id)
            )
            try repository.insertJobs([job])
            recordUserActivity()
            runVideoOptimization(item: item, record: record, job: job)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func videoOptimizationDependencyMessage() -> String? {
        VideoOptimizationRequirements.missingDependencyMessage()
    }

    func cancelVideoOptimization(for itemID: String) {
        guard case let .running(_, _, token) = optimizationState[itemID] else {
            return
        }
        token.cancel()
    }

    func linkedItems(from item: Item) -> ([ItemSummary], String?) {
        guard let repository else {
            return ([], "Vault não está desbloqueado.")
        }
        do {
            return (try repository.linkedItems(from: item.id), nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }

    func backlinks(to item: Item) -> ([ItemSummary], String?) {
        guard let repository else {
            return ([], "Vault não está desbloqueado.")
        }
        do {
            return (try repository.backlinks(to: item.id), nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }

    func linkCandidates(query: String, excluding itemID: String) -> ([ItemSummary], String?) {
        guard let repository else {
            return ([], "Vault não está desbloqueado.")
        }
        do {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceItems: [Item]
            if trimmed.isEmpty {
                sourceItems = try repository.listItems(filter: ItemListFilter(limit: 50))
            } else {
                sourceItems = try repository.search(trimmed, filter: ItemListFilter(limit: 50))
            }
            let summaries = sourceItems
                .filter { $0.id != itemID }
                .map { ItemSummary(id: $0.id, title: $0.title, kind: $0.kind, capturedAt: $0.capturedAt) }
            return (summaries, nil)
        } catch {
            return ([], error.localizedDescription)
        }
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
        summary: String,
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
                    summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
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

    func generateSummary(title: String, note: String, bodyText: String) async -> (String?, String?) {
        do {
            let service = try makeItemAIService()
            let summary = try await service.summarize(context: LLMItemContext(
                title: title,
                note: note,
                bodyText: bodyText
            ))
            recordUserActivity()
            return (summary, nil)
        } catch {
            return (nil, LLMRecoverableErrorMapper().jobErrorMessage(for: error))
        }
    }

    func streamSummary(
        title: String,
        note: String,
        bodyText: String,
        onChunk: @escaping @MainActor (String) -> Void
    ) async -> (String?, String?) {
        let service: ItemAIService
        let stream: AsyncThrowingStream<String, Error>
        do {
            service = try makeItemAIService()
            stream = try service.streamSummary(context: LLMItemContext(
                title: title,
                note: note,
                bodyText: bodyText
            ))
        } catch {
            return (nil, LLMRecoverableErrorMapper().jobErrorMessage(for: error))
        }

        var collected = ""
        do {
            for try await chunk in stream {
                collected += chunk
                onChunk(chunk)
            }
        } catch {
            return (nil, LLMRecoverableErrorMapper().jobErrorMessage(for: error))
        }

        let final = collected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !final.isEmpty else {
            return (nil, "Resposta vazia do provider de IA.")
        }
        recordUserActivity()
        return (final, nil)
    }

    func generateAutotags(title: String, note: String, bodyText: String, existingTags: [String]) async -> ([String], String?) {
        do {
            let service = try makeItemAIService()
            let tags = try await service.autotags(
                context: LLMItemContext(title: title, note: note, bodyText: bodyText),
                existingTags: existingTags
            )
            recordUserActivity()
            return (tags, nil)
        } catch {
            return (existingTags, LLMRecoverableErrorMapper().jobErrorMessage(for: error))
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
            var completedJobKinds = Set<JobKind>()
            var synchronousJobs: [Job] = []
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
                    if try createThumbnailIfSupported(
                        for: stored.record,
                        itemID: createdItem.id,
                        originalFilename: filePayload.originalFilename
                    ) != nil {
                        completedJobKinds.insert(.generateThumbnail)
                    }
                    if plan.jobs.contains(.runOCR) {
                        _ = try runOCRIfSupported(
                            for: stored.record,
                            itemID: createdItem.id,
                            originalFilename: filePayload.originalFilename
                        )
                        completedJobKinds.insert(.runOCR)
                        synchronousJobs.append(Job(
                            itemID: createdItem.id,
                            kind: .runOCR,
                            status: .done,
                            payloadJSON: try jobPayloadJSON(sourceURL: validatedDraft.sourceURL, assetID: stored.record.id)
                        ))
                    }
                } catch {
                    try? assetStore.remove(record: stored.record)
                    try? repository.deleteItems(ids: [createdItem.id])
                    throw error
                }
            }
            let jobs = try makeJobs(
                kinds: plan.jobs.filter { !completedJobKinds.contains($0) },
                itemID: createdItem.id,
                sourceURL: validatedDraft.sourceURL,
                assetID: assetID
            )
            try repository.insertJobs(synchronousJobs + jobs)
            capturePrefill = nil
            showCapture = false
            refreshLibrary()
            recordUserActivity()
            scheduleAutomatedJobs(for: createdItem.id)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func jobs(for item: Item) -> ([Job], String?) {
        guard let repository else {
            return ([], "Vault não está desbloqueado.")
        }
        do {
            return (try repository.jobs(forItemID: item.id), nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }

    func retryJob(_ job: Job) -> String? {
        guard let repository, let itemID = job.itemID else {
            return "Vault não está desbloqueado."
        }
        if job.kind == .optimizeVideo {
            guard let assetID = Self.assetID(fromPayload: job.payloadJSON) else {
                return "Tarefa de otimização sem asset associado."
            }
            do {
                let item = try repository.item(id: itemID)
                guard let record = try repository.assets(forItemID: itemID).first(where: { $0.id == assetID }) else {
                    return "Asset de vídeo não encontrado para otimização."
                }
                try repository.incrementJobAttempts(id: job.id)
                try repository.updateJobStatus(id: job.id, status: .pending, error: nil)
                recordUserActivity()
                runVideoOptimization(item: item, record: record, job: job)
                return nil
            } catch {
                return error.localizedDescription
            }
        }
        guard JobAutomation.canRun(job.kind) || job.kind == .optimizeVideo else {
            return "Esta tarefa não tem executor disponível ainda."
        }
        guard !runningJobIDs.contains(job.id) else {
            return nil
        }
        do {
            try repository.incrementJobAttempts(id: job.id)
            try repository.updateJobStatus(id: job.id, status: .pending, error: nil)
            recordUserActivity()
            scheduleAutomatedJobs(for: itemID)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func scheduleAutomatedJobs(for itemID: String) {
        Task { [weak self] in
            await self?.runAutomatedJobs(for: itemID)
        }
    }

    private func runAutomatedJobs(for itemID: String) async {
        guard let repository else {
            return
        }
        let pendingJobs: [Job]
        do {
            pendingJobs = try repository.jobs(forItemID: itemID).filter { job in
                job.status == .pending
                    && Self.isAutomatedJobKind(job.kind)
                    && JobAutomation.canRun(job.kind)
                    && !runningJobIDs.contains(job.id)
            }
        } catch {
            return
        }
        guard !pendingJobs.isEmpty else {
            return
        }

        var runnableJobs = pendingJobs
        var service: ItemAIService?
        do {
            service = pendingJobs.contains(where: { Self.requiresLLM($0.kind) })
                ? try makeItemAIService()
                : nil
        } catch {
            let message = LLMRecoverableErrorMapper().jobErrorMessage(for: error)
            for job in pendingJobs where Self.requiresLLM(job.kind) {
                try? repository.updateJobStatus(id: job.id, status: .failed, error: message)
            }
            runnableJobs.removeAll { Self.requiresLLM($0.kind) }
            guard !runnableJobs.isEmpty else {
                refreshOpenedItemIfMatches(itemID)
                return
            }
        }

        let automation = JobAutomation(
            service: service,
            articleScraper: TrafilaturaArticleScraper(renderer: WKWebViewPageRenderer()),
            mediaDownloader: YTDLPMediaDownloader(),
            remoteThumbnailFetcher: GalleryDLThumbnailFetcher()
        )

        for job in runnableJobs {
            await runSingleJob(job, itemID: itemID, automation: automation)
        }
    }

    private static func requiresLLM(_ kind: JobKind) -> Bool {
        switch kind {
        case .summarize, .autotag:
            true
        case .scrapeArticle, .downloadMedia, .generateThumbnail, .optimizeVideo, .runOCR:
            false
        }
    }

    private static func isAutomatedJobKind(_ kind: JobKind) -> Bool {
        switch kind {
        case .summarize, .autotag, .scrapeArticle, .downloadMedia, .generateThumbnail:
            true
        case .optimizeVideo, .runOCR:
            false
        }
    }

    private func runSingleJob(_ job: Job, itemID: String, automation: JobAutomation) async {
        guard let repository else {
            return
        }
        runningJobIDs.insert(job.id)
        defer {
            runningJobIDs.remove(job.id)
        }
        do {
            try repository.updateJobStatus(id: job.id, status: .running, error: nil)
        } catch {
            return
        }
        refreshOpenedItemIfMatches(itemID)

        let snapshot: Item
        do {
            snapshot = try repository.item(id: itemID)
        } catch {
            try? repository.updateJobStatus(id: job.id, status: .failed, error: error.localizedDescription)
            refreshOpenedItemIfMatches(itemID)
            return
        }

        do {
            let outcome = try await automation.run(job.kind, on: snapshot)
            try applyOutcome(outcome, to: snapshot)
            try repository.updateJobStatus(id: job.id, status: .done, error: nil)
        } catch {
            let message = LLMRecoverableErrorMapper().jobErrorMessage(for: error)
            try? repository.updateJobStatus(id: job.id, status: .failed, error: message)
        }
        refreshOpenedItemIfMatches(itemID)
        refreshStorageUsage()
    }

    private func runVideoOptimization(item: Item, record: AssetRecord, job: Job) {
        guard let repository, let assetStore else {
            optimizationState[item.id] = .failed(message: "Vault não está desbloqueado.")
            return
        }
        guard !isOptimizationRunning(for: item.id) else {
            return
        }
        let token = OptimizationCancelToken()
        let itemID = item.id
        let jobID = job.id
        let startedAt = Date()
        let logger = optimizationLogger
        let lastProgressLog = LockedDateBox()
        let updateProgress: @Sendable (VideoOptimizationProgress) -> Void = { [weak self, token, itemID, logger, lastProgressLog] progress in
            if lastProgressLog.shouldLog(now: Date(), interval: 5) {
                logger.debug("optimizeVideo progress item_id=\(itemID, privacy: .public) percent=\(progress.percent, privacy: .public)")
            }
            Task { @MainActor [weak self, token, itemID] in
                guard case let .running(_, runningStartedAt, currentToken) = self?.optimizationState[itemID],
                      currentToken === token else {
                    return
                }
                self?.optimizationState[itemID] = .running(
                    progress: progress,
                    startedAt: runningStartedAt,
                    cancelToken: currentToken
                )
            }
        }
        optimizationState[item.id] = .running(
            progress: VideoOptimizationProgress(percent: 0),
            startedAt: startedAt,
            cancelToken: token
        )
        runningJobIDs.insert(jobID)
        refreshOpenedItemIfMatches(itemID)

        Task { [weak self, repository, assetStore] in
            do {
                try repository.updateJobStatus(id: jobID, status: .running, error: nil)
                let service = VideoOptimizationService(repository: repository, assetStore: assetStore)
                let outcome = try await service.optimizeVideoAsset(
                    record: record,
                    optimizer: FFmpegVideoOptimizer(),
                    progress: updateProgress,
                    isCancelled: { token.isCancelled }
                )
                let ffmpegSeconds = Date().timeIntervalSince(startedAt)
                try repository.updateJobStatus(id: jobID, status: .done, error: nil)
                await MainActor.run {
                    self?.logOptimizationOutcome(outcome, itemID: itemID, ffmpegSeconds: ffmpegSeconds)
                    self?.applyOptimizationOutcome(outcome, itemID: itemID, jobID: jobID)
                }
            } catch VideoOptimizationError.cancelled {
                try? repository.updateJobStatus(id: jobID, status: .failed, error: "Otimização cancelada.")
                await MainActor.run {
                    self?.optimizationState[itemID] = .idle
                    self?.runningJobIDs.remove(jobID)
                    self?.refreshOpenedItemIfMatches(itemID)
                }
            } catch {
                let message = Self.optimizationErrorMessage(for: error)
                try? repository.updateJobStatus(id: jobID, status: .failed, error: message)
                await MainActor.run {
                    self?.optimizationState[itemID] = .failed(message: message)
                    self?.runningJobIDs.remove(jobID)
                    self?.refreshOpenedItemIfMatches(itemID)
                }
            }
        }
    }

    private func applyOptimizationOutcome(_ outcome: OptimizeOutcome, itemID: String, jobID: String) {
        switch outcome {
        case let .optimized(originalBytes, newBytes, asset):
            optimizationState[itemID] = .succeeded(beforeBytes: originalBytes, afterBytes: newBytes)
            invalidateAssetCache(itemID: itemID, assetID: asset.id)
        case let .alreadyOptimized(originalBytes, _):
            optimizationState[itemID] = .alreadyOptimized(bytes: originalBytes)
        }
        runningJobIDs.remove(jobID)
        refreshOpenedItemIfMatches(itemID)
        refreshStorageUsage()
        refreshItemThumbnails(for: items)
    }

    private func isOptimizationRunning(for itemID: String) -> Bool {
        if case .running = optimizationState[itemID] {
            return true
        }
        return false
    }

    nonisolated private static func optimizationErrorMessage(for error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return "Falha recuperável de otimização: \(localized)"
        }
        return "Falha recuperável de otimização: \(error.localizedDescription)"
    }

    private func invalidateAssetCache(itemID: String, assetID: String) {
        guard let appPaths else {
            return
        }
        let cacheDirectory = appPaths.temporaryCacheDirectory
            .appendingPathComponent(itemID, isDirectory: true)
            .appendingPathComponent(assetID, isDirectory: true)
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    func clearTerminalOptimizationState(for itemID: String) {
        switch optimizationState[itemID] {
        case .succeeded, .alreadyOptimized:
            optimizationState[itemID] = nil
        default:
            return
        }
    }

    private func applyOutcome(_ outcome: JobAutomationOutcome, to item: Item) throws {
        guard let repository else {
            return
        }
        switch outcome {
        case .skipped:
            return
        case let .summarized(summary):
            _ = try repository.patchItem(id: item.id, patch: ItemPatch(summary: summary))
        case let .taggedAutomatically(tags) where !tags.isEmpty:
            _ = try repository.patchItem(id: item.id, patch: ItemPatch(tags: tags))
        case .taggedAutomatically:
            return
        case let .articleScraped(result):
            try applyArticleScrapeResult(result, to: item)
        case let .mediaDownloaded(result):
            try applyMediaDownloadResult(result, to: item)
        case let .thumbnailFetched(result):
            try applyRemoteThumbnailResult(result, to: item)
        }
    }

    private func applyArticleScrapeResult(_ result: ArticleScrapeResult, to item: Item) throws {
        guard let repository else {
            return
        }
        let currentTitle = item.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let metadata = try articleMetadataJSON(from: result)
        _ = try repository.patchItem(
            id: item.id,
            patch: ItemPatch(
                title: currentTitle ?? result.title,
                bodyText: result.bodyText,
                metadataJSON: metadata
            )
        )
        if let heroImage = result.heroImage {
            try storeArticleHeroImage(heroImage, itemID: item.id)
        }
    }

    private func storeArticleHeroImage(_ heroImage: ArticleHeroImage, itemID: String) throws {
        guard let repository, let assetStore else {
            return
        }
        let mimeType = heroImage.mimeType?.lowercased().hasPrefix("image/") == true
            ? heroImage.mimeType
            : "image/jpeg"
        let stored = try assetStore.write(
            data: heroImage.data,
            itemID: itemID,
            role: .heroImage,
            originalFilename: heroImage.originalFilename ?? "hero-image",
            mimeType: mimeType
        )
        do {
            try repository.insertAsset(stored.record)
        } catch {
            try? assetStore.remove(record: stored.record)
            throw error
        }
    }

    private func articleMetadataJSON(from result: ArticleScrapeResult) throws -> String? {
        var metadata: [String: String] = [:]
        if let description = result.description {
            metadata["description"] = description
        }
        if let author = result.author {
            metadata["author"] = author
        }
        if let sitename = result.sitename {
            metadata["sitename"] = sitename
        }
        if let publishedAt = result.publishedAt {
            metadata["published_at"] = publishedAt
        }
        if let heroImageURL = result.heroImageURL {
            metadata["hero_image_url"] = heroImageURL
        }
        guard !metadata.isEmpty else {
            return nil
        }
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)
    }

    private func applyMediaDownloadResult(_ result: MediaDownloadResult, to item: Item) throws {
        guard let repository, let assetStore else {
            return
        }
        var storedVideo = try assetStore.write(
            data: result.data,
            itemID: item.id,
            role: .original,
            originalFilename: result.originalFilename,
            mimeType: result.mimeType
        ).record
        storedVideo.durationSeconds = result.durationSeconds
        var storedRecords: [AssetRecord] = [storedVideo]

        do {
            try repository.insertAsset(storedVideo)
            if let mediaThumbnail = result.thumbnail {
                let storedThumbnail = try storeDownloadedMediaThumbnail(mediaThumbnail, itemID: item.id)
                storedRecords.append(storedThumbnail)
            } else if let storedThumbnail = try createThumbnailIfSupported(
                for: storedVideo,
                itemID: item.id,
                originalFilename: result.originalFilename
            ) {
                storedRecords.append(storedThumbnail)
            }
            for subtitle in result.subtitles {
                let storedSubtitle = try assetStore.write(
                    data: subtitle.data,
                    itemID: item.id,
                    role: .subtitle,
                    originalFilename: subtitle.originalFilename,
                    mimeType: subtitle.mimeType
                )
                storedRecords.append(storedSubtitle.record)
                try repository.insertAsset(storedSubtitle.record)
            }
            let currentTitle = item.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let metadata = try mediaMetadataJSON(from: result)
            _ = try repository.patchItem(
                id: item.id,
                patch: ItemPatch(
                    title: currentTitle ?? result.title,
                    metadataJSON: metadata
                )
            )
        } catch {
            rollbackStoredAssets(storedRecords)
            throw error
        }
    }

    private func mediaMetadataJSON(from result: MediaDownloadResult) throws -> String? {
        var metadata: [String: String] = [:]
        if let webpageURL = result.webpageURL {
            metadata["webpage_url"] = webpageURL
        }
        if let durationSeconds = result.durationSeconds {
            metadata["duration_seconds"] = String(durationSeconds)
        }
        if let uploader = result.uploader {
            metadata["uploader"] = uploader
        }
        if let uploadDate = result.uploadDate {
            metadata["upload_date"] = uploadDate
        }
        if let thumbnailURL = result.thumbnail?.sourceURL {
            metadata["thumbnail_source_url"] = thumbnailURL
        }
        metadata["media_kind"] = result.kind.rawValue
        guard !metadata.isEmpty else {
            return nil
        }
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)
    }

    private func applyRemoteThumbnailResult(_ result: RemoteThumbnailResult, to item: Item) throws {
        guard let repository, let assetStore else {
            return
        }
        let existingAssets = try repository.assets(forItemID: item.id)
        if existingAssets.contains(where: { $0.role == .thumbnail }) {
            if let sourceURL = result.sourceURL {
                let metadata = try remoteThumbnailMetadataJSON(sourceURL: sourceURL)
                _ = try repository.patchItem(id: item.id, patch: ItemPatch(metadataJSON: metadata))
            }
            return
        }
        let storedSource = try assetStore.write(
            data: result.data,
            itemID: item.id,
            role: .original,
            originalFilename: result.originalFilename,
            mimeType: result.mimeType
        )
        var storedRecords: [AssetRecord] = [storedSource.record]
        do {
            try repository.insertAsset(storedSource.record)
            if let storedThumbnail = try createThumbnailIfSupported(
                for: storedSource.record,
                itemID: item.id,
                originalFilename: result.originalFilename
            ) {
                storedRecords.append(storedThumbnail)
            } else {
                let storedThumbnail = try assetStore.write(
                    data: result.data,
                    itemID: item.id,
                    role: .thumbnail,
                    originalFilename: result.originalFilename,
                    mimeType: result.mimeType
                )
                storedRecords.append(storedThumbnail.record)
                try repository.insertAsset(storedThumbnail.record)
            }
            if let sourceURL = result.sourceURL {
                let metadata = try remoteThumbnailMetadataJSON(sourceURL: sourceURL)
                _ = try repository.patchItem(id: item.id, patch: ItemPatch(metadataJSON: metadata))
            }
        } catch {
            rollbackStoredAssets(storedRecords)
            throw error
        }
    }

    private func rollbackStoredAssets(_ records: [AssetRecord]) {
        let ids = records.map(\.id)
        try? repository?.deleteAssets(ids: ids)
        for record in records {
            try? assetStore?.remove(record: record)
        }
        refreshStorageUsage()
    }

    private func remoteThumbnailMetadataJSON(sourceURL: String) throws -> String? {
        let data = try JSONSerialization.data(
            withJSONObject: ["thumbnail_source_url": sourceURL],
            options: [.sortedKeys]
        )
        return String(data: data, encoding: .utf8)
    }

    private func refreshOpenedItemIfMatches(_ itemID: String) {
        guard let repository else {
            return
        }
        if selectedItem?.id == itemID {
            if let refreshed = try? repository.item(id: itemID) {
                selectedItem = refreshed
            }
        }
        if items.contains(where: { $0.id == itemID }) {
            refreshItems()
            refreshSidebarData()
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

    private static func assetPayloadJSON(assetID: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["asset_id": assetID], options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? #"{"asset_id":"\#(assetID)"}"#
    }

    private static func assetID(fromPayload payloadJSON: String?) -> String? {
        guard
            let payloadJSON,
            let data = payloadJSON.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let payload = object as? [String: Any]
        else {
            return nil
        }
        return payload["asset_id"] as? String
    }

    private func makeItemAIService() throws -> ItemAIService {
        let overrides = currentLLMOverrides()
        let configuration = try LLMConfiguration.resolve(overrides: overrides)
        return ItemAIService(
            client: OpenAICompatibleClient(configuration: configuration),
            configuration: configuration
        )
    }

    private func currentLLMOverrides() -> LLMOverrides {
        guard let llmSettingsStore else {
            return LLMOverrides()
        }
        let record = (try? llmSettingsStore.read()) ?? LLMSettingsRecord()
        return LLMOverrides(
            url: record.url,
            model: record.model,
            contextLimit: record.contextLimit
        )
    }

    func currentLLMSettings() -> LLMSettingsRecord {
        (try? llmSettingsStore?.read()) ?? LLMSettingsRecord()
    }

    func resolvedLLMConfiguration() -> (LLMConfiguration?, String?) {
        do {
            let configuration = try LLMConfiguration.resolve(overrides: currentLLMOverrides())
            return (configuration, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    func saveLLMSettings(url: String, model: String, contextLimit: String) -> String? {
        guard let llmSettingsStore else {
            return "Vault não está desbloqueado."
        }
        let candidate = LLMSettingsRecord(
            url: url.nilIfEmpty,
            model: model.nilIfEmpty,
            contextLimit: contextLimit.nilIfEmpty
        )
        let overrides = LLMOverrides(
            url: candidate.url,
            model: candidate.model,
            contextLimit: candidate.contextLimit
        )
        do {
            _ = try LLMConfiguration.resolve(overrides: overrides)
            try llmSettingsStore.write(candidate)
            recordUserActivity()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func clearLLMSettings() -> String? {
        guard let llmSettingsStore else {
            return "Vault não está desbloqueado."
        }
        do {
            try llmSettingsStore.clear()
            recordUserActivity()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func chatAvailable(for item: Item) -> Bool {
        ItemChatService.isAvailable(for: item)
    }

    func chatHistory(for item: Item) -> ([ChatMessage], String?) {
        guard let repository else {
            return ([], "Vault não está desbloqueado.")
        }
        do {
            return (try repository.chatHistory(forItemID: item.id), nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }

    func clearChatHistory(for item: Item) -> String? {
        guard let repository else {
            return "Vault não está desbloqueado."
        }
        do {
            try repository.clearChatHistory(forItemID: item.id)
            recordUserActivity()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func sendChatMessage(
        item: Item,
        userContent: String,
        onChunk: @escaping @MainActor (String) -> Void
    ) async -> String? {
        guard let repository else {
            return "Vault não está desbloqueado."
        }
        let trimmed = userContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Digite uma mensagem antes de enviar."
        }

        let snapshot: Item
        let history: [ChatMessage]
        do {
            snapshot = try repository.item(id: item.id)
            history = try repository.chatHistory(forItemID: item.id)
        } catch {
            return error.localizedDescription
        }

        let userMessage = ChatMessage(
            itemID: item.id,
            role: .user,
            content: trimmed
        )
        do {
            try repository.appendChatMessage(userMessage)
        } catch {
            return error.localizedDescription
        }

        let configuration: LLMConfiguration
        let service: ItemChatService
        do {
            configuration = try LLMConfiguration.resolve(overrides: currentLLMOverrides())
            service = ItemChatService(
                client: OpenAICompatibleClient(configuration: configuration),
                configuration: configuration
            )
        } catch {
            return LLMRecoverableErrorMapper().jobErrorMessage(for: error)
        }

        let conversation = ItemChatService.Conversation(
            item: snapshot,
            history: history,
            newUserMessage: trimmed
        )

        var collected = ""
        do {
            let stream = try service.streamReply(conversation)
            for try await chunk in stream {
                collected += chunk
                onChunk(chunk)
            }
        } catch {
            return LLMRecoverableErrorMapper().jobErrorMessage(for: error)
        }

        let finalAnswer = collected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalAnswer.isEmpty else {
            return "Resposta vazia do provider de IA."
        }
        let assistantMessage = ChatMessage(
            itemID: item.id,
            role: .assistant,
            content: finalAnswer
        )
        do {
            try repository.appendChatMessage(assistantMessage)
        } catch {
            return error.localizedDescription
        }
        recordUserActivity()
        return nil
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

    private func refreshStorageUsage() {
        do {
            if let appPaths {
                storageBytes = try storageByteCount(at: appPaths.assetsDirectory)
            } else {
                storageBytes = 0
            }
        } catch {
            storageBytes = 0
        }
    }

    private func refreshItemThumbnails(for items: [Item]) {
        guard let repository, let assetStore else {
            itemThumbnailURLs = [:]
            return
        }
        let visibleIDs = Set(items.map(\.id))
        do {
            let records = try repository.assets(forItemIDs: Array(visibleIDs))
            var grouped: [String: [AssetRecord]] = [:]
            for record in records {
                grouped[record.itemID, default: []].append(record)
            }

            var urls: [String: URL] = [:]
            for item in items {
                guard let record = preferredThumbnailAsset(in: grouped[item.id] ?? []) else {
                    continue
                }
                urls[item.id] = try? assetStore.decryptToTemporaryFile(record: record)
            }
            itemThumbnailURLs = urls
        } catch {
            itemThumbnailURLs = itemThumbnailURLs.filter { visibleIDs.contains($0.key) }
        }
    }

    private func createThumbnailIfSupported(
        for originalRecord: AssetRecord,
        itemID: String,
        originalFilename: String
    ) throws -> AssetRecord? {
        guard let repository, let assetStore else {
            return nil
        }
        let sourceURL = try assetStore.decryptToTemporaryFile(record: originalRecord)
        let thumbnailData: Data
        do {
            thumbnailData = try NativeThumbnailGenerator().makeJPEGThumbnailData(
                for: sourceURL,
                mimeType: originalRecord.mimeType
            )
        } catch is ThumbnailGenerationError {
            return nil
        }

        let baseName = (originalFilename as NSString).deletingPathExtension
        let storedThumbnail = try assetStore.write(
            data: thumbnailData,
            itemID: itemID,
            role: .thumbnail,
            originalFilename: "\(baseName)-thumbnail.jpg",
            mimeType: "image/jpeg"
        )
        do {
            try repository.insertAsset(storedThumbnail.record)
            return storedThumbnail.record
        } catch {
            try? assetStore.remove(record: storedThumbnail.record)
            throw error
        }
    }

    private func storeDownloadedMediaThumbnail(
        _ thumbnail: DownloadedMediaThumbnail,
        itemID: String
    ) throws -> AssetRecord {
        guard let repository, let assetStore else {
            throw DataError.assetStoreUnavailable
        }
        let normalizedData = try normalizedThumbnailData(
            thumbnail.data,
            mimeType: thumbnail.mimeType,
            originalFilename: thumbnail.originalFilename
        )
        let baseName = (thumbnail.originalFilename as NSString).deletingPathExtension.nilIfEmpty ?? "media-thumbnail"
        let storedThumbnail = try assetStore.write(
            data: normalizedData ?? thumbnail.data,
            itemID: itemID,
            role: .thumbnail,
            originalFilename: normalizedData == nil ? thumbnail.originalFilename : "\(baseName)-thumbnail.jpg",
            mimeType: normalizedData == nil ? thumbnail.mimeType : "image/jpeg"
        )
        do {
            try repository.insertAsset(storedThumbnail.record)
            return storedThumbnail.record
        } catch {
            try? assetStore.remove(record: storedThumbnail.record)
            throw error
        }
    }

    private func normalizedThumbnailData(
        _ data: Data,
        mimeType: String?,
        originalFilename: String
    ) throws -> Data? {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hypomnemata-media-thumbnail-\(UUID().uuidString)")
            .appendingPathExtension((originalFilename as NSString).pathExtension.nilIfEmpty ?? "img")
        try data.write(to: tempURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: tempURL) }
        do {
            return try NativeThumbnailGenerator().makeJPEGThumbnailData(for: tempURL, mimeType: mimeType)
        } catch is ThumbnailGenerationError {
            return nil
        }
    }

    private func runOCRIfSupported(
        for originalRecord: AssetRecord,
        itemID: String,
        originalFilename: String
    ) throws -> Bool {
        guard let repository, let assetStore else {
            return false
        }
        let sourceURL = try assetStore.decryptToTemporaryFile(record: originalRecord)
        let extractedText: String
        do {
            extractedText = try NativeOCRExtractor()
                .extractText(from: sourceURL, mimeType: originalRecord.mimeType)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch is NativeOCRError {
            return false
        }

        guard !extractedText.isEmpty else {
            return true
        }

        _ = try repository.patchItem(id: itemID, patch: ItemPatch(bodyText: extractedText))
        let baseName = (originalFilename as NSString).deletingPathExtension
        let storedText = try assetStore.write(
            data: Data(extractedText.utf8),
            itemID: itemID,
            role: .derivedText,
            originalFilename: "\(baseName)-ocr.txt",
            mimeType: "text/plain; charset=utf-8"
        )
        do {
            try repository.insertAsset(storedText.record)
            return true
        } catch {
            try? assetStore.remove(record: storedText.record)
            throw error
        }
    }

    private func preferredThumbnailAsset(in records: [AssetRecord]) -> AssetRecord? {
        records.first { $0.role == .thumbnail }
            ?? records.first { $0.role == .heroImage }
            ?? records.first { isImageAsset($0) && $0.role == .original }
    }

    private func isPlayableMediaAsset(_ record: AssetRecord) -> Bool {
        record.role == .original && (isVideoAsset(record) || isAudioAsset(record))
    }

    private func isImageAsset(_ record: AssetRecord) -> Bool {
        record.mimeType?.lowercased().hasPrefix("image/") == true
            || ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff"].contains(record.originalFilename?.pathExtensionLowercased ?? "")
    }

    private func isVideoAsset(_ record: AssetRecord) -> Bool {
        record.mimeType?.lowercased().hasPrefix("video/") == true
            || ["mp4", "mov", "m4v", "webm", "mkv", "avi"].contains(record.originalFilename?.pathExtensionLowercased ?? "")
    }

    private func isAudioAsset(_ record: AssetRecord) -> Bool {
        record.mimeType?.lowercased().hasPrefix("audio/") == true
            || ["m4a", "mp3", "aac", "opus", "ogg", "wav", "flac"].contains(record.originalFilename?.pathExtensionLowercased ?? "")
    }

    private func previewKind(for record: AssetRecord, url: URL) -> AssetPreview.Kind {
        let mimeType = record.mimeType?.lowercased() ?? ""
        let pathExtension = url.pathExtension.lowercased()
        if mimeType.hasPrefix("image/") || ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp"].contains(pathExtension) {
            return .image
        }
        if mimeType == "application/pdf" || pathExtension == "pdf" {
            return .pdf
        }
        if mimeType.hasPrefix("video/") || ["mp4", "mov", "m4v", "webm", "mkv", "avi"].contains(pathExtension) {
            return .video
        }
        if mimeType.hasPrefix("audio/") || ["m4a", "mp3", "aac", "opus", "ogg", "wav", "flac"].contains(pathExtension) {
            return .video
        }
        return .file
    }

    private func runStartupRecovery(repository: SQLiteItemRepository, assetStore: EncryptedAssetStore) {
        cleanupOrphanOptimizationTempFiles()
        recoverInterruptedOptimizationJobs(repository: repository)
        let logger = optimizationLogger
        Task.detached(priority: .utility) {
            AppModel.cleanupOrphanEncryptedBlobs(
                repository: repository,
                assetStore: assetStore,
                logger: logger
            )
        }
    }

    private func cleanupOrphanOptimizationTempFiles(fileManager: FileManager = .default) {
        let tempDirectory = fileManager.temporaryDirectory
        guard let filenames = try? fileManager.contentsOfDirectory(atPath: tempDirectory.path) else {
            return
        }
        for filename in filenames where filename.hasPrefix("hypomnemata-optimize-") {
            try? fileManager.removeItem(at: tempDirectory.appendingPathComponent(filename))
        }
    }

    private func recoverInterruptedOptimizationJobs(repository: SQLiteItemRepository) {
        do {
            try repository.markRunningJobsFailed(
                kind: .optimizeVideo,
                error: "App reiniciado durante a otimização."
            )
        } catch {
            optimizationLogger.error("optimizeVideo recovery failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated private static func cleanupOrphanEncryptedBlobs(
        repository: SQLiteItemRepository,
        assetStore: EncryptedAssetStore,
        logger: Logger
    ) {
        do {
            let referencedPaths = Set(try repository.allAssets().map(\.encryptedPath))
            let cutoff = Date().addingTimeInterval(-60 * 60)
            let orphans = try assetStore.findOrphanEncryptedBlobs(
                referencedPaths: referencedPaths,
                olderThan: cutoff
            )
            for orphan in orphans {
                try? assetStore.removeEncryptedBlob(at: orphan)
            }
        } catch {
            logger.error("optimizeVideo janitor failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func insufficientDiskSpaceMessage(for record: AssetRecord) -> String? {
        guard let appPaths else {
            return nil
        }
        let requiredBytes = record.byteCount * 2
        guard let availableBytes = availableDiskSpace(at: appPaths.rootDirectory), availableBytes < requiredBytes else {
            return nil
        }
        return "Espaço insuficiente para otimizar este vídeo. Libere pelo menos \(ByteCountFormatter.string(fromByteCount: requiredBytes, countStyle: .file))."
    }

    private func availableDiskSpace(at url: URL) -> Int64? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return nil
        }
        if let important = values.volumeAvailableCapacityForImportantUsage {
            return important
        }
        if let capacity = values.volumeAvailableCapacity {
            return Int64(capacity)
        }
        return nil
    }

    private func logOptimizationOutcome(_ outcome: OptimizeOutcome, itemID: String, ffmpegSeconds: Double) {
        switch outcome {
        case let .optimized(originalBytes, newBytes, asset):
            let ratio = originalBytes > 0 ? Double(newBytes) / Double(originalBytes) : 0
            optimizationLogger.info("optimizeVideo item_id=\(itemID, privacy: .public) original_bytes=\(originalBytes) new_bytes=\(newBytes) duration_seconds=\(asset.durationSeconds ?? 0, privacy: .public) ffmpeg_seconds=\(ffmpegSeconds, privacy: .public) ratio=\(ratio, privacy: .public)")
        case let .alreadyOptimized(originalBytes, asset):
            optimizationLogger.info("optimizeVideo item_id=\(itemID, privacy: .public) original_bytes=\(originalBytes) new_bytes=\(asset.byteCount) duration_seconds=\(asset.durationSeconds ?? 0, privacy: .public) ffmpeg_seconds=\(ffmpegSeconds, privacy: .public) ratio=1 already_optimized=true")
        }
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

    var pathExtensionLowercased: String {
        (self as NSString).pathExtension.lowercased()
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
