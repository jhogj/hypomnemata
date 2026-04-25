import Foundation
import GRDB
import HypomnemataCore
import HypomnemataData
import HypomnemataIngestion
import HypomnemataMedia

@main
struct HypomnemataNativeChecks {
    static func main() throws {
        try checkCore()
        try checkData()
        try checkMedia()
        try checkPerformance()
        print("HypomnemataNativeChecks: ok")
    }

    private static func checkCore() throws {
        precondition(KindInference.infer(urlString: "https://x.com/user/status/1") == .tweet)
        precondition(KindInference.infer(urlString: "https://twitter.com/user/status/1") == .tweet)
        precondition(KindInference.infer(urlString: "https://www.youtube.com/watch?v=abc") == .video)
        precondition(KindInference.infer(urlString: "https://youtu.be/abc") == .video)
        precondition(KindInference.infer(urlString: "https://vimeo.com/123456") == .video)
        precondition(KindInference.infer(urlString: "https://example.com/report.pdf") == .pdf)
        precondition(KindInference.infer(urlString: "https://example.com/photo.webp") == .image)
        precondition(KindInference.infer(urlString: "https://example.com/news/story") == .article)
        precondition(KindInference.infer(urlString: nil, filename: "clip.mov") == .video)

        let validURLDraft = try CapturePlanner.validate(CaptureDraft(
            sourceURL: "  https://example.com/news/story  ",
            title: "  Matéria  ",
            note: "  nota  ",
            tags: [" Dev ", "dev", "Leitura"]
        ))
        precondition(validURLDraft.sourceURL == "https://example.com/news/story")
        precondition(validURLDraft.title == "Matéria")
        precondition(validURLDraft.note == "nota")
        precondition(validURLDraft.tags == ["dev", "leitura"])

        let urlPlan = try CapturePlanner.validateAndPlan(CaptureDraft(sourceURL: "https://youtu.be/abc"))
        precondition(urlPlan.1.kind == .video)
        precondition(urlPlan.1.jobs == [.downloadMedia, .summarize, .autotag])

        let pdfPlan = try CapturePlanner.validateAndPlan(CaptureDraft(fileURL: URL(fileURLWithPath: "/tmp/documento.pdf")))
        precondition(pdfPlan.1.kind == .pdf)
        precondition(pdfPlan.1.jobs == [.generateThumbnail, .runOCR, .summarize, .autotag])

        let textPlan = try CapturePlanner.validateAndPlan(CaptureDraft(bodyText: "texto solto"))
        precondition(textPlan.1.kind == .note)
        precondition(textPlan.1.jobs.isEmpty)

        do {
            _ = try CapturePlanner.validate(CaptureDraft(sourceURL: "example.com/noticia"))
            preconditionFailure("URL without http/https was accepted.")
        } catch CaptureValidationError.invalidURL(_) {
            // Expected: URL captures must be explicit web URLs.
        }

        do {
            _ = try CapturePlanner.validate(CaptureDraft())
            preconditionFailure("Empty capture was accepted.")
        } catch CaptureValidationError.missingInput {
            // Expected: capture needs one source.
        }

        do {
            _ = try CapturePlanner.validate(CaptureDraft(sourceURL: "https://example.com", bodyText: "texto"))
            preconditionFailure("Capture with multiple sources was accepted.")
        } catch CaptureValidationError.multipleInputs {
            // Expected: capture source must be unambiguous.
        }

        let missingDependencyError = JobDependencyResolver(
            doctor: DependencyDoctor(environment: ["PATH": "/tmp/hypomnemata-no-tools"])
        ).missingDependencyError(for: .scrapeArticle)
        precondition(missingDependencyError?.contains("trafilatura") == true)
        precondition(missingDependencyError?.contains("brew install trafilatura") == true)

        let nativeOCRDependencyError = JobDependencyResolver(
            doctor: DependencyDoctor(environment: ["PATH": "/tmp/hypomnemata-no-tools"])
        ).missingDependencyError(for: .runOCR)
        precondition(nativeOCRDependencyError == nil)

        let text = "Veja [[018f73ba-9f9d-7a0d-8ac2-f28f82cf1296|Nome atual]] e texto"
        precondition(LinkParser.references(in: text) == [
            ItemLinkReference(targetID: "018f73ba-9f9d-7a0d-8ac2-f28f82cf1296", displayText: "Nome atual"),
        ])

        let id = UUIDV7.generateString()
        precondition(id.count == 36)
        precondition(id[id.index(id.startIndex, offsetBy: 14)] == "7")
        precondition(["8", "9", "a", "b"].contains(id[id.index(id.startIndex, offsetBy: 19)]))
    }

    private static func checkData() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hypomnemata-native-checks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appPaths = AppPaths(rootDirectory: root)

        let database = try NativeDatabase(
            appPaths: appPaths,
            passphrase: "test",
            requireSQLCipher: true
        )

        let repository = SQLiteItemRepository(database: database)
        let item = try repository.createItem(
            kind: .note,
            sourceURL: nil,
            title: "filosófia grega",
            note: "Sócrates",
            bodyText: nil,
            summary: nil,
            metadataJSON: nil,
            tags: ["Filosofia", "grega"]
        )
        let article = try repository.createItem(
            kind: .article,
            sourceURL: "https://example.com/platao",
            title: "Academia de Platão",
            note: nil,
            bodyText: "Diálogos políticos e teoria das ideias.",
            summary: nil,
            metadataJSON: nil,
            tags: ["filosofia", "platao"]
        )
        let bookmark = try repository.createItem(
            kind: .bookmark,
            sourceURL: "https://example.com/grdb",
            title: "GRDB",
            note: "Referência técnica",
            bodyText: nil,
            summary: nil,
            metadataJSON: nil,
            tags: ["dev"]
        )
        let folder = try repository.createFolder(name: "Estudos")
        try repository.addItems([item.id, article.id], toFolder: folder.id)
        do {
            _ = try repository.createFolder(name: " ")
            preconditionFailure("Empty folder name was accepted.")
        } catch DataError.emptyFolderName {
            // Expected: folders need a visible name.
        }

        let storedItem = try repository.item(id: item.id)
        let noteItems = try repository.listItems(filter: ItemListFilter(kind: .note))
        let searchIDs = try repository.search("filosofia").map(\.id)
        let filteredArticleIDs = try repository.listItems(
            filter: ItemListFilter(kind: .article, tag: "filosofia", folderID: folder.id)
        ).map(\.id)
        let filteredBookmarkIDs = try repository.listItems(
            filter: ItemListFilter(kind: .bookmark, tag: "filosofia", folderID: folder.id)
        ).map(\.id)
        let filteredSearchIDs = try repository.search(
            "platao",
            filter: ItemListFilter(kind: .article, tag: "filosofia", folderID: folder.id)
        ).map(\.id)
        let folders = try repository.listFolders()
        let kindCounts = try repository.itemCountsByKind()
        let tagCounts = try repository.tagCounts()
        let totalItemCount = try repository.totalItemCount()
        let jobTime = ClockTimestamp.nowISO8601()
        let plannedJobs = [
            Job(
                id: "job-a",
                itemID: article.id,
                kind: .scrapeArticle,
                payloadJSON: #"{"source_url":"https://example.com/platao"}"#,
                createdAt: jobTime,
                updatedAt: jobTime
            ),
            Job(
                id: "job-b",
                itemID: article.id,
                kind: .summarize,
                payloadJSON: #"{"source_url":"https://example.com/platao"}"#,
                createdAt: jobTime,
                updatedAt: jobTime
            ),
        ]
        try repository.insertJobs(plannedJobs)
        try repository.updateJobStatus(
            id: "job-b",
            status: .failed,
            error: "Dependência ausente: trafilatura. Rode `brew install trafilatura`."
        )
        let storedJobs = try repository.jobs(forItemID: article.id)
        precondition(storedItem.tags == ["filosofia", "grega"])
        precondition(bookmark.kind == .bookmark)
        precondition(noteItems.count == 1)
        precondition(searchIDs == [item.id])
        precondition(filteredArticleIDs == [article.id])
        precondition(filteredBookmarkIDs.isEmpty)
        precondition(filteredSearchIDs == [article.id])
        precondition(folders == [Folder(id: folder.id, name: "Estudos", itemCount: 2, createdAt: folder.createdAt)])
        precondition(totalItemCount == 3)
        precondition(kindCounts[.note] == 1)
        precondition(kindCounts[.article] == 1)
        precondition(kindCounts[.bookmark] == 1)
        precondition(kindCounts[.video] == 0)
        precondition(tagCounts == [
            TagCount(name: "dev", count: 1),
            TagCount(name: "filosofia", count: 2),
            TagCount(name: "grega", count: 1),
            TagCount(name: "platao", count: 1),
        ])
        precondition(storedJobs.count == 2)
        precondition(storedJobs[0] == plannedJobs[0])
        precondition(storedJobs[1].id == "job-b")
        precondition(storedJobs[1].status == .failed)
        precondition(storedJobs[1].error?.contains("brew install trafilatura") == true)

        let cascadeJobItem = try repository.createItem(
            kind: .article,
            sourceURL: "https://example.com/cascade",
            title: "Cascade job",
            note: nil,
            bodyText: nil,
            tags: []
        )
        try repository.insertJobs([Job(id: "job-cascade", itemID: cascadeJobItem.id, kind: .scrapeArticle)])
        let cascadeJobsBeforeDelete = try repository.jobs(forItemID: cascadeJobItem.id)
        precondition(cascadeJobsBeforeDelete.count == 1)
        try repository.deleteItems(ids: [cascadeJobItem.id])
        let cascadeJobsAfterDelete = try repository.jobs(forItemID: cascadeJobItem.id)
        precondition(cascadeJobsAfterDelete.isEmpty)

        let patchedItem = try repository.patchItem(
            id: item.id,
            patch: ItemPatch(
                title: "Ética socrática",
                note: "Maiêutica",
                bodyText: "Virtude e conhecimento caminham juntos.",
                tags: ["etica", "filosofia"]
            )
        )
        let patchedSearchIDs = try repository.search("maieutica").map(\.id)
        let patchedTagCounts = try repository.tagCounts()
        precondition(patchedItem.title == "Ética socrática")
        precondition(patchedItem.note == "Maiêutica")
        precondition(patchedItem.bodyText == "Virtude e conhecimento caminham juntos.")
        precondition(patchedItem.tags == ["etica", "filosofia"])
        precondition(patchedSearchIDs == [item.id])
        precondition(patchedTagCounts == [
            TagCount(name: "dev", count: 1),
            TagCount(name: "etica", count: 1),
            TagCount(name: "filosofia", count: 2),
            TagCount(name: "platao", count: 1),
        ])

        try repository.deleteItems(ids: [bookmark.id])
        do {
            _ = try repository.item(id: bookmark.id)
            preconditionFailure("Deleted item was still readable.")
        } catch DataError.itemNotFound {
            // Expected: deleted items are not readable.
        }
        let postDeleteCounts = try repository.itemCountsByKind()
        let postDeleteTagCounts = try repository.tagCounts()
        let postDeleteFolders = try repository.listFolders()
        let postDeleteTotalItemCount = try repository.totalItemCount()
        precondition(postDeleteTotalItemCount == 2)
        precondition(postDeleteCounts[.bookmark] == 0)
        precondition(postDeleteTagCounts == [
            TagCount(name: "etica", count: 1),
            TagCount(name: "filosofia", count: 2),
            TagCount(name: "platao", count: 1),
        ])
        precondition(postDeleteFolders == [Folder(id: folder.id, name: "Estudos", itemCount: 2, createdAt: folder.createdAt)])

        let firstAssetKey = try database.loadOrCreateAssetKeyData()
        let secondAssetKey = try database.loadOrCreateAssetKeyData()
        precondition(firstAssetKey.count == 32)
        precondition(secondAssetKey == firstAssetKey)

        let store = try EncryptedAssetStore(
            rootDirectory: appPaths.assetsDirectory,
            cacheDirectory: appPaths.temporaryCacheDirectory,
            keyData: firstAssetKey
        )
        let plaintext = Data("asset sensível do vault".utf8)
        let storedAsset = try store.write(
            data: plaintext,
            itemID: item.id,
            role: .original,
            originalFilename: "vault.txt",
            mimeType: "text/plain"
        )
        let ciphertext = try Data(contentsOf: storedAsset.absoluteURL)
        let restoredAsset = try store.read(record: storedAsset.record)
        precondition(ciphertext != plaintext)
        precondition(restoredAsset == plaintext)
        try repository.insertAsset(storedAsset.record)
        let itemAssets = try repository.assets(forItemID: item.id)
        precondition(itemAssets == [storedAsset.record])
        let batchAssets = try repository.assets(forItemIDs: [item.id, article.id])
        precondition(batchAssets == [storedAsset.record])

        let batchDeleteA = try repository.createItem(
            kind: .note,
            title: "Excluir em lote A",
            note: nil,
            bodyText: nil,
            tags: ["batch"]
        )
        let batchDeleteB = try repository.createItem(
            kind: .note,
            title: "Excluir em lote B",
            note: nil,
            bodyText: nil,
            tags: ["batch"]
        )
        let batchStoredAsset = try store.write(
            data: Data("batch asset".utf8),
            itemID: batchDeleteA.id,
            role: .original,
            originalFilename: "batch.txt",
            mimeType: "text/plain"
        )
        try repository.insertAsset(batchStoredAsset.record)
        let assetsBeforeBatchDelete = try repository.assets(forItemIDs: [batchDeleteA.id, batchDeleteB.id])
        precondition(assetsBeforeBatchDelete == [batchStoredAsset.record])
        try repository.deleteItems(ids: [batchDeleteA.id, batchDeleteB.id])
        for asset in assetsBeforeBatchDelete {
            try store.remove(record: asset)
        }
        let assetsAfterBatchDelete = try repository.assets(forItemIDs: [batchDeleteA.id, batchDeleteB.id])
        precondition(assetsAfterBatchDelete.isEmpty)
        precondition(!FileManager.default.fileExists(atPath: batchStoredAsset.absoluteURL.path))

        let decryptedTemp = try store.decryptToTemporaryFile(record: storedAsset.record)
        let decryptedTempData = try Data(contentsOf: decryptedTemp)
        precondition(decryptedTempData == plaintext)
        try store.clearTemporaryCache()
        precondition(!FileManager.default.fileExists(atPath: decryptedTemp.path))

        let tools = DependencyDoctor.productionRequirements.map(\.executable)
        precondition(tools == ["sqlcipher", "ffmpeg", "yt-dlp", "gallery-dl", "trafilatura"])

        do {
            try database.changePassphrase(to: "")
            preconditionFailure("Empty passphrase was accepted.")
        } catch DataError.emptyPassphrase {
            // Expected: empty vault passphrases are not valid.
        }

        let verifier = try NativeDatabase(
            appPaths: appPaths,
            passphrase: "test",
            requireSQLCipher: true
        )
        try verifier.close()

        try database.changePassphrase(to: "changed")
        let rekeyedAssetKey = try database.loadOrCreateAssetKeyData()
        precondition(rekeyedAssetKey == firstAssetKey)
        try database.close()

        do {
            let oldPassphraseDatabase = try NativeDatabase(
                appPaths: appPaths,
                passphrase: "test",
                requireSQLCipher: true
            )
            try oldPassphraseDatabase.close()
            preconditionFailure("Old passphrase opened the vault after rekey.")
        } catch {
            // Expected: SQLCipher must reject the old passphrase after rekey.
        }

        let reopened = try NativeDatabase(
            appPaths: appPaths,
            passphrase: "changed",
            requireSQLCipher: true
        )
        let reopenedAssetKey = try reopened.loadOrCreateAssetKeyData()
        precondition(reopenedAssetKey == firstAssetKey)
        let reopenedStore = try EncryptedAssetStore(
            rootDirectory: appPaths.assetsDirectory,
            cacheDirectory: appPaths.temporaryCacheDirectory,
            keyData: reopenedAssetKey
        )
        let reopenedAsset = try reopenedStore.read(record: storedAsset.record)
        precondition(reopenedAsset == plaintext)
        try reopened.close()

        let sqliteRead = Process()
        sqliteRead.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        sqliteRead.arguments = [
            root.appendingPathComponent("Hypomnemata.sqlite").path,
            "select count(*) from items;",
        ]
        sqliteRead.standardOutput = Pipe()
        sqliteRead.standardError = Pipe()
        try sqliteRead.run()
        sqliteRead.waitUntilExit()
        precondition(sqliteRead.terminationStatus != 0)
    }

    private static func checkMedia() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hypomnemata-media-checks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = try EncryptedAssetStore(
            rootDirectory: root.appendingPathComponent("assets", isDirectory: true),
            cacheDirectory: root.appendingPathComponent("cache", isDirectory: true),
            keyData: EncryptedAssetStore.generateKeyData()
        )

        let plaintext = Data("conteúdo sensível".utf8)
        let stored = try store.write(
            data: plaintext,
            itemID: "item-1",
            role: .original,
            originalFilename: "nota.txt",
            mimeType: "text/plain"
        )

        let restored = try store.read(record: stored.record)
        let ciphertext = try Data(contentsOf: stored.absoluteURL)
        precondition(restored == plaintext)
        precondition(ciphertext != plaintext)

        let temp = try store.decryptToTemporaryFile(record: stored.record)
        let tempData = try Data(contentsOf: temp)
        precondition(tempData == plaintext)
        try store.clearTemporaryCache()
        precondition(!FileManager.default.fileExists(atPath: temp.path))

        let recreated = root.appendingPathComponent("cache", isDirectory: true)
        precondition(FileManager.default.fileExists(atPath: recreated.path))

        let missingCache = root.appendingPathComponent("missing-cache", isDirectory: true)
        try TemporaryCacheCleaner().clear(at: missingCache)
        precondition(FileManager.default.fileExists(atPath: missingCache.path))

        try store.remove(record: stored.record)
        precondition(!FileManager.default.fileExists(atPath: stored.absoluteURL.path))
        do {
            _ = try store.read(record: stored.record)
            preconditionFailure("Removed asset was still readable.")
        } catch MediaError.assetNotFound {
            // Expected: removed encrypted assets are no longer readable.
        }
    }

    private static func checkPerformance() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hypomnemata-performance-checks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let database = try NativeDatabase(
            appPaths: AppPaths(rootDirectory: root),
            passphrase: "performance",
            requireSQLCipher: true
        )
        defer { try? database.close() }

        let repository = SQLiteItemRepository(database: database)
        let now = ClockTimestamp.nowISO8601()
        var insertedIDs: [String] = []
        insertedIDs.reserveCapacity(10_000)

        try database.writer.write { db in
            for index in 0..<10_000 {
                let id = UUIDV7.generateString()
                insertedIDs.append(id)
                let kind: ItemKind = index.isMultiple(of: 2) ? .note : .article
                try db.execute(
                    sql: """
                        INSERT INTO items(
                            id, kind, source_url, title, note, body_text, summary, meta_json,
                            captured_at, created_at, updated_at
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        id,
                        kind.rawValue,
                        index.isMultiple(of: 2) ? nil : "https://example.com/perf-\(index)",
                        "Item perf \(index)",
                        "nota perf \(index)",
                        "corpo perf token\(index)",
                        index.isMultiple(of: 5) ? "resumo perf \(index)" : nil,
                        nil,
                        now,
                        now,
                        now,
                    ]
                )
            }
        }

        let listStart = Date()
        let listed = try repository.listItems(filter: ItemListFilter(limit: 200))
        let listElapsed = Date().timeIntervalSince(listStart)
        precondition(listed.count == 200)
        precondition(listElapsed < 2.0)

        let searchStart = Date()
        let found = try repository.search("token9999", filter: ItemListFilter(limit: 20))
        let searchElapsed = Date().timeIntervalSince(searchStart)
        precondition(found.count == 1)
        precondition(found[0].title == "Item perf 9999")
        precondition(searchElapsed < 2.0)

        let deleteIDs = Array(insertedIDs.prefix(500))
        let deleteStart = Date()
        try repository.deleteItems(ids: deleteIDs)
        let deleteElapsed = Date().timeIntervalSince(deleteStart)
        let remainingCount = try repository.totalItemCount()
        precondition(remainingCount == 9_500)
        precondition(deleteElapsed < 5.0)
    }
}
