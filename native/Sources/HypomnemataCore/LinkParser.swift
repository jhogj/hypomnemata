import Foundation

public struct ItemLinkReference: Equatable, Sendable {
    public var targetID: String
    public var displayText: String

    public init(targetID: String, displayText: String) {
        self.targetID = targetID
        self.displayText = displayText
    }
}

public enum LinkParser {
    private static let pattern = #"\[\[([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\|([^\]]*)\]\]"#

    public static func references(in text: String?) -> [ItemLinkReference] {
        guard let text, !text.isEmpty else {
            return []
        }
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges == 3 else {
                return nil
            }
            return ItemLinkReference(
                targetID: nsText.substring(with: match.range(at: 1)).lowercased(),
                displayText: nsText.substring(with: match.range(at: 2))
            )
        }
    }

    public static func targetIDs(in texts: [String?]) -> [String] {
        let ids = texts.flatMap { references(in: $0).map(\.targetID) }
        return Array(Set(ids)).sorted()
    }
}
