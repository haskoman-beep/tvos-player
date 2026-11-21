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
    public init(rows: [HomeRow] = []) { self.rows = rows }
}
