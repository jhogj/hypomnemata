import Foundation

public enum DataError: LocalizedError, Equatable {
    case sqlCipherUnavailable
    case itemNotFound(String)
    case invalidKind(String)
    case invalidDatabasePath(URL)
    case invalidStoredAssetKey
    case assetKeyGenerationFailed(Int32)
    case emptyPassphrase
    case emptyFolderName
    case assetStoreUnavailable

    public var errorDescription: String? {
        switch self {
        case .sqlCipherUnavailable:
            "SQLCipher não está disponível nesta build. Instale e vincule SQLCipher antes de abrir vaults de produção."
        case let .itemNotFound(id):
            "Item não encontrado: \(id)"
        case let .invalidKind(kind):
            "Tipo inválido: \(kind)"
        case let .invalidDatabasePath(url):
            "Caminho de banco inválido: \(url.path)"
        case .invalidStoredAssetKey:
            "Chave de assets armazenada no vault está inválida."
        case let .assetKeyGenerationFailed(status):
            "Falha ao gerar chave de assets segura: OSStatus \(status)"
        case .emptyPassphrase:
            "A senha não pode ficar vazia."
        case .emptyFolderName:
            "O nome da pasta não pode ficar vazio."
        case .assetStoreUnavailable:
            "Storage criptografado de assets não está disponível."
        }
    }
}
