import Foundation

public enum RowStyle: String, Codable, Sendable, CaseIterable, Hashable {
    case hero, poster, landscape, top10, logoTiles, collectionTiles

    public var displayName: String {
        switch self {
        case .hero: "Hero"
        case .poster: "Poster"
        case .landscape: "Querformat"
        case .top10: "Top 10"
        case .logoTiles: "Logo-Kacheln"
        case .collectionTiles: "Collection-Kacheln"
        }
    }
}

/// Inhalt einer Startseiten-Reihe: eine Titelliste oder eine ganze Collection (als Ordner-Kacheln).
public enum RowContent: Codable, Sendable, Hashable {
    case list(CatalogSource)
    case collection(id: String)

    public var allowedStyles: [RowStyle] {
        switch self {
        case .list: [.poster, .landscape, .hero, .top10]
        case .collection: [.collectionTiles, .logoTiles]
        }
    }

    public var key: String {
        switch self {
        case .list(let s): "list:" + s.id
        case .collection(let id): "collection:" + id
        }
    }
}

public struct HomeRow: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var content: RowContent
    public var style: RowStyle

    public init(id: UUID = UUID(), content: RowContent, style: RowStyle? = nil) {
        self.id = id; self.content = content
        self.style = style.flatMap { content.allowedStyles.contains($0) ? $0 : nil } ?? content.allowedStyles[0]
    }
}

public struct HomeLayout: Codable, Sendable, Hashable {
    public var rows: [HomeRow]
    /// Task 1.2: rows this build cannot read (unknown `style`, `SourceKind` or other content from a newer build),
    /// kept as raw JSON in their original order. Not shown; `encode` writes them back unchanged after `rows`.
    public var unknownRows: [JSONValue] = []
    public init(rows: [HomeRow] = []) { self.rows = rows }

    enum CodingKeys: String, CodingKey { case rows }

    /// Same format as before (`{"rows":[…]}`); an unreadable row is set aside instead of failing the layout.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let items = try c.decodeIfPresent([Salvaged<HomeRow>].self, forKey: .rows) ?? []
        (rows, unknownRows) = Salvaged.split(items)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        var list = c.nestedUnkeyedContainer(forKey: .rows)
        for row in rows { try list.encode(row) }
        for raw in unknownRows { try list.encode(raw) }
    }
}
