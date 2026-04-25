import Foundation
import HypomnemataCore
import HypomnemataData
import HypomnemataIngestion
import HypomnemataMedia

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
    @Published var query = ""
    @Published var showCapture = false
    @Published var dependencyStatuses: [DependencyStatus] = []

    private var database: NativeDatabase?
    private var repository: SQLiteItemRepository?
    private var assetStore: EncryptedAssetStore?
    private var appPaths: AppPaths?

    var isUnlocked: Bool {
        if case .unlocked = state {
            return true
        }
        return false
    }

    init() {
        refreshDependencies()
    }

    func refreshDependencies() {
        dependencyStatuses = DependencyDoctor().check()
    }

    func unlock(passphrase: String) {
        do {
            let paths = try AppPaths.production()
            let db = try NativeDatabase(
                appPaths: paths,
                passphrase: passphrase,
                requireSQLCipher: true
            )
            let assetKeyData = try db.loadOrCreateAssetKeyData()
            database = db
            repository = SQLiteItemRepository(database: db)
            appPaths = paths
            assetStore = try EncryptedAssetStore(
                rootDirectory: paths.assetsDirectory,
                cacheDirectory: paths.temporaryCacheDirectory,
                keyData: assetKeyData
            )
            state = .unlocked
            refreshItems()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func lock() {
        clearTemporaryCache()
        do {
            try database?.close()
        } catch {
            state = .failed(error.localizedDescription)
        }
        database = nil
        repository = nil
        assetStore = nil
        appPaths = nil
        items = []
        state = .locked
    }

    func prepareForQuit() {
        clearTemporaryCache()
    }

    func refreshItems() {
        guard let repository else {
            return
        }
        do {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items = try repository.listItems(filter: ItemListFilter(kind: activeKind))
            } else {
                items = try repository.search(query)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func createCapture(_ draft: CaptureDraft) {
        guard let repository else {
            return
        }
        do {
            let plan = CapturePlanner.plan(draft)
            let metadataJSON: String?
            if plan.jobs.isEmpty {
                metadataJSON = nil
            } else {
                let data = try JSONSerialization.data(
                    withJSONObject: ["planned_jobs": plan.jobs.map(\.rawValue)],
                    options: [.sortedKeys]
                )
                metadataJSON = String(data: data, encoding: .utf8)
            }
            _ = try repository.createItem(
                kind: plan.kind,
                sourceURL: draft.sourceURL,
                title: draft.title,
                note: draft.note,
                bodyText: draft.bodyText,
                summary: nil,
                metadataJSON: metadataJSON,
                tags: draft.tags
            )
            showCapture = false
            refreshItems()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func clearTemporaryCache() {
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
        } catch {
            state = .failed(error.localizedDescription)
        }
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
