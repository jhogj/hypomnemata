import Foundation
import HypomnemataCore
import HypomnemataData
import HypomnemataMedia

@main
struct HypomnemataNativeChecks {
    static func main() throws {
        try checkCore()
        try checkData()
        try checkMedia()
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

        let database = try NativeDatabase(
            appPaths: AppPaths(rootDirectory: root),
            passphrase: "test",
            requireSQLCipher: false
        )
        defer { try? database.close() }

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

        let storedItem = try repository.item(id: item.id)
        let noteItems = try repository.listItems(filter: ItemListFilter(kind: .note))
        let searchIDs = try repository.search("filosofia").map(\.id)
        let tagCounts = try repository.tagCounts()
        precondition(storedItem.tags == ["filosofia", "grega"])
        precondition(noteItems.count == 1)
        precondition(searchIDs == [item.id])
        precondition(tagCounts == [
            TagCount(name: "filosofia", count: 1),
            TagCount(name: "grega", count: 1),
        ])

        let tools = DependencyDoctor.productionRequirements.map(\.executable)
        precondition(tools == ["sqlcipher", "ffmpeg", "yt-dlp", "gallery-dl", "trafilatura"])
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
    }
}
