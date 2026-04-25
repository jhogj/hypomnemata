import Foundation

public enum DataError: LocalizedError, Equatable {
    case sqlCipherUnavailable
    case itemNotFound(String)
    case invalidKind(String)
    case invalidDatabasePath(URL)

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
        }
    }
}
