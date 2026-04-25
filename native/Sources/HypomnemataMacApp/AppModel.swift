import Foundation
import HypomnemataCore
import HypomnemataData
import HypomnemataIngestion

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
            database = db
            repository = SQLiteItemRepository(database: db)
            state = .unlocked
            refreshItems()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func lock() {
        do {
            try database?.close()
        } catch {
            state = .failed(error.localizedDescription)
        }
        database = nil
        repository = nil
        items = []
        state = .locked
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
}
