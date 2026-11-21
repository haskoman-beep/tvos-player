import Foundation

/// Was der Hinzufügen-Browser anbietet (Plan §2.5, Ebene 2): links die Quellen mit Anzahl, rechts die Einträge,
/// dazu eine Suche über alle Quellen. Reine Logik; die UI entscheidet nur über Darstellung und Fokus.
public struct RowCatalog: Sendable {
    public let groups: [RowCatalogGroup]

    /// - Parameters:
    ///   - layout: aktuelle Startseite (für „auf der Startseite (n)“).
    ///   - addons: installierte Addons; je Addon mit Katalogen eine Gruppe.
    ///   - collections: eigene Collections des Profils.
    ///   - kitSources: Kit-Dateien (Katalog und eigene), `kitContents` die geladenen Inhalte je Quellen-ID.
    ///   - traktID: Trakt Client ID eingetragen. `traktLogin`: bei Trakt angemeldet.
    ///   - packages: fertige Pakete (Standard `ReadyPackages.all`).
    public init(layout: HomeLayout,
                addons: [InstalledAddon] = [],
                collections: [MediaCollection] = [],
                kitSources: [FusionKitSource] = [],
                kitContents: [String: FusionKitContent] = [:],
                traktID: Bool = false,
                traktLogin: Bool = false,
                packages: [MediaCollection] = ReadyPackages.all) {
        var positions: [String: Int] = [:]
        for (i, r) in layout.rows.enumerated() where positions[r.content.key] == nil { positions[r.content.key] = i + 1 }
        func status(_ key: String) -> RowCatalogEntry.Status { positions[key].map { .onHome(position: $0) } ?? .available }

        var groups: [RowCatalogGroup] = []

        // 1. Je Addon eine Gruppe, Abschnitte nach Typ (Filme, Serien, …).
        for a in addons {
            let gid = "addon:" + a.manifest.id
            var sections: [(type: String, entries: [RowCatalogEntry])] = []
            for c in a.manifest.catalogs where !(c.extra ?? []).contains(where: { $0.isRequired == true }) {
                let src = RowCatalog.addonSource(addon: a.manifest, catalog: c)
                let e = RowCatalogEntry(id: "list:" + src.id, title: c.name ?? c.id,
                                        subtitle: "Liste · " + RowCatalog.typeSingular(c.type),
                                        source: a.manifest.name, groupID: gid,
                                        action: .content(.list(src)), status: status("list:" + src.id))
                if let i = sections.firstIndex(where: { $0.type == c.type }) { sections[i].entries.append(e) }
                else { sections.append((c.type, [e])) }
            }
            guard !sections.isEmpty else { continue }
            let order = ["movie": 0, "series": 1]
            let sorted = sections.enumerated().sorted { l, r in
                (order[l.element.type] ?? 2, l.offset) < (order[r.element.type] ?? 2, r.offset)
            }.map(\.element)
            groups.append(RowCatalogGroup(id: gid, kind: .addon, title: a.manifest.name,
                                          sections: sorted.map { RowCatalogSection(title: RowCatalog.typePlural($0.type), entries: $0.entries) }))
        }

        // 2. Eigene Collections.
        let own = collections.filter { !FusionImport.isKitID($0.id) }
        let ownEntries = own.map { c in
            RowCatalogEntry(id: "collection:" + c.id, title: c.title, subtitle: "Collection · \(c.folders.count) Ordner",
                            source: RowCatalogGroup.Kind.collections.title, groupID: RowCatalogGroup.Kind.collections.rawValue,
                            action: .content(.collection(id: c.id)), status: status("collection:" + c.id))
        }
        groups.append(.fixed(.collections, entries: ownEntries))

        // 3. Fusion-Kit, nach Thema gruppiert; der Ersteller steht im Untertitel.
        groups.append(RowCatalog.kitGroup(sources: kitSources, contents: kitContents, traktID: traktID,
                                          traktLogin: traktLogin, status: status))

        // 4. Trakt.
        let traktEntries = [CatalogSource.traktRecommendedMovies, .traktRecommendedShows].map { s in
            RowCatalogEntry(id: "list:" + s.id, title: s.title, subtitle: "Liste · " + RowCatalog.typeSingular(s.mediaType),
                            source: RowCatalogGroup.Kind.trakt.title, groupID: RowCatalogGroup.Kind.trakt.rawValue,
                            action: .content(.list(s)),
                            status: traktLogin ? status("list:" + s.id) : (positions["list:" + s.id].map { .onHome(position: $0) }
                                ?? .unavailable(traktID ? "braucht Trakt-Anmeldung" : "braucht Trakt-Anmeldung und Client ID")))
        }
        groups.append(.fixed(.trakt, entries: traktEntries))

        // 5. Sonderlisten, feste Reihenfolge: Weiterschauen, Merkliste, Demnächst.
        let specials = [CatalogSource.continueWatching, .watchlist, .upcoming].map { s in
            RowCatalogEntry(id: "list:" + s.id, title: s.title, subtitle: "Liste",
                            source: RowCatalogGroup.Kind.special.title, groupID: RowCatalogGroup.Kind.special.rawValue,
                            action: .content(.list(s)), status: status("list:" + s.id))
        }
        groups.append(.fixed(.special, entries: specials))

        // 6. Fertige Pakete, die noch keine eigene Collection sind.
        let ownIDs = Set(collections.map(\.id))
        let pkgs = packages.filter { !ownIDs.contains($0.id) }.map { p in
            RowCatalogEntry(id: "collection:" + p.id, title: p.title, subtitle: "\(p.folders.count) Ordner",
                            source: RowCatalogGroup.Kind.packages.title, groupID: RowCatalogGroup.Kind.packages.rawValue,
                            action: .package(p), status: status("collection:" + p.id))
        }
        groups.append(.fixed(.packages, entries: pkgs))

        self.groups = groups
    }

    public func group(_ id: String) -> RowCatalogGroup? { groups.first { $0.id == id } }

    public var allEntries: [RowCatalogEntry] { groups.flatMap(\.entries) }

    /// Suche über alle Quellen. Groß-/Kleinschreibung und Umlaute sind egal („Komödie“ = „komodie“, „ß“ = „ss“).
    /// Mehrere Wörter müssen alle vorkommen (in Titel, Untertitel oder Quelle). Treffer im Titel stehen vorn,
    /// sonst bleibt die Reihenfolge des Katalogs. Leere Suche = keine Treffer.
    public func search(_ query: String) -> [RowCatalogEntry] {
        let words = RowCatalog.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        var inTitle: [RowCatalogEntry] = [], elsewhere: [RowCatalogEntry] = []
        var seen = Set<String>()
        for e in allEntries where !seen.contains(e.id) {
            let title = RowCatalog.fold(e.title)
            let all = title + " " + RowCatalog.fold(e.subtitle) + " " + RowCatalog.fold(e.source)
            guard words.allSatisfy({ all.contains($0) }) else { continue }
            seen.insert(e.id)
            if words.allSatisfy({ title.contains($0) }) { inTitle.append(e) } else { elsewhere.append(e) }
        }
        return inTitle + elsewhere
    }

    /// Kleinschreibung, ohne Akzente/Umlautpunkte, „ß“ → „ss“, Leerraum zusammengefasst.
    public static func fold(_ s: String) -> String {
        let lowered = s.lowercased().replacingOccurrences(of: "ß", with: "ss")
        let scalars = lowered.decomposedStringWithCanonicalMapping.unicodeScalars.filter {
            $0.properties.generalCategory != .nonspacingMark
        }
        return String(String.UnicodeScalarView(scalars)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Dieselbe Quelle wie bisher im Hinzufügen-Blatt (ID bleibt gleich, damit vorhandene Reihen erkannt werden).
    public static func addonSource(addon a: AddonManifest, catalog c: CatalogDescriptor) -> CatalogSource {
        CatalogSource(id: "addon:\(a.id):\(c.type):\(c.id)", title: "\(c.name ?? c.id) (\(a.name))",
                      kind: .addon(addonId: a.id, catalogId: c.id, type: c.type),
                      mediaType: c.type == "series" ? .series : .movie)
    }

    static func typePlural(_ type: String) -> String {
        ["movie": "Filme", "series": "Serien", "anime": "Anime", "tv": "TV", "channel": "Kanäle", "other": "Sonstiges"][type]
            ?? type.capitalized
    }

    static func typeSingular(_ type: String) -> String {
        ["movie": "Film", "series": "Serie", "anime": "Anime", "tv": "TV", "channel": "Kanal", "other": "Sonstiges"][type]
            ?? type.capitalized
    }

    static func typeSingular(_ t: MediaType) -> String {
        switch t {
        case .movie: "Film"
        case .series: "Serie"
        case .both: "Film & Serie"
        }
    }

    /// Thema und Ersteller aus dem Titel einer Kit-Datei: „Genres · dannyrutledge“ → (Genres, dannyrutledge).
    static func kitTopic(_ title: String) -> (topic: String, creator: String?) {
        guard let r = title.range(of: " · ") else { return (title, nil) }
        let creator = String(title[r.upperBound...])
        return (String(title[..<r.lowerBound]), creator.isEmpty ? nil : creator)
    }

    static func kitGroup(sources: [FusionKitSource], contents: [String: FusionKitContent], traktID: Bool, traktLogin: Bool,
                         status: (String) -> RowCatalogEntry.Status) -> RowCatalogGroup {
        let kind = RowCatalogGroup.Kind.kit
        var sections: [(topic: String, entries: [RowCatalogEntry])] = []
        var hidden = 0, hiddenNeedsID = false, pending = 0
        var seen = Set<String>()
        for src in sources where seen.insert(src.id).inserted {
            guard let content = contents[src.id] else { pending += 1; continue }
            let (topic, creator) = kitTopic(src.title)
            for row in content.rows {
                guard let shown = row.available(traktID: traktID, traktLogin: traktLogin) else {
                    hidden += 1
                    if row.needs.contains(.traktID) && !traktID { hiddenNeedsID = true }
                    continue
                }
                let kindText: String = switch shown.body {
                case .collection(let c): "\(c.folders.count) Kacheln"
                case .list: shown.style == .top10 ? "Liste mit Rang" : "Liste"
                }
                let key = row.content.key
                let e = RowCatalogEntry(id: key, title: row.title,
                                        subtitle: [kindText, creator].compactMap { $0 }.joined(separator: " · "),
                                        source: kind.title, groupID: kind.rawValue,
                                        action: .kit(rowID: row.id, source: src), status: status(key))
                if let i = sections.firstIndex(where: { $0.topic == topic }) { sections[i].entries.append(e) }
                else { sections.append((topic, [e])) }
            }
        }
        var hint: String?
        if hidden > 0 {
            let what = hidden == 1 ? "1 Reihe ausgeblendet" : "\(hidden) Reihen ausgeblendet"
            hint = (hiddenNeedsID ? "Trakt Client ID fehlt – " : "Trakt-Anmeldung fehlt – ") + what
        }
        return RowCatalogGroup(id: kind.rawValue, kind: kind, title: kind.title,
                               sections: sections.map { RowCatalogSection(title: $0.topic, entries: $0.entries) },
                               hiddenCount: hidden, hint: hint, pendingSources: pending)
    }
}

/// Eine Quelle in der linken Spalte.
public struct RowCatalogGroup: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case addon, collections, kit, trakt, special, packages

        public var title: String {
            switch self {
            case .addon: "Addon"
            case .collections: "Meine Collections"
            case .kit: "Fusion-Kit"
            case .trakt: "Trakt"
            case .special: "Sonderlisten"
            case .packages: "Fertige Pakete"
            }
        }
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var sections: [RowCatalogSection]
    /// Kit: Reihen, die ohne Trakt Client ID bzw. Anmeldung nicht laden und deshalb fehlen.
    public var hiddenCount: Int
    /// Einmaliger Hinweis über der Liste, z. B. „Trakt Client ID fehlt – 12 Reihen ausgeblendet“.
    public var hint: String?
    /// Kit: Dateien, deren Inhalt (noch) nicht geladen ist.
    public var pendingSources: Int

    public init(id: String, kind: Kind, title: String, sections: [RowCatalogSection],
                hiddenCount: Int = 0, hint: String? = nil, pendingSources: Int = 0) {
        self.id = id; self.kind = kind; self.title = title; self.sections = sections
        self.hiddenCount = hiddenCount; self.hint = hint; self.pendingSources = pendingSources
    }

    static func fixed(_ kind: Kind, entries: [RowCatalogEntry]) -> RowCatalogGroup {
        RowCatalogGroup(id: kind.rawValue, kind: kind, title: kind.title,
                        sections: entries.isEmpty ? [] : [RowCatalogSection(title: nil, entries: entries)])
    }

    public var entries: [RowCatalogEntry] { sections.flatMap(\.entries) }

    /// Anzahl in der linken Spalte.
    public var count: Int { entries.count }

    /// Mit ▶ in die rechte Spalte: erster Eintrag ohne Häkchen, der sich hinzufügen lässt (sonst der erste).
    public var firstAvailable: RowCatalogEntry? { entries.first { $0.status == .available } ?? entries.first }
}

public struct RowCatalogSection: Sendable, Hashable {
    /// nil = Gruppe ohne Zwischenüberschrift.
    public var title: String?
    public var entries: [RowCatalogEntry]
    public init(title: String?, entries: [RowCatalogEntry]) { self.title = title; self.entries = entries }
}

/// Ein Eintrag in der rechten Spalte.
public struct RowCatalogEntry: Identifiable, Sendable, Hashable {
    public enum Action: Sendable, Hashable {
        /// Direkt als Reihe einfügen (`HomeEditor.toggle`).
        case content(RowContent)
        /// Kit-Reihe: über die Kit-Auswahl wählen; der Kit-Abgleich setzt sie ans Ende der Startseite.
        case kit(rowID: String, source: FusionKitSource)
        /// Fertiges Paket: erst als Collection anlegen, dann `.collection(id:)` einfügen.
        case package(MediaCollection)
    }

    public enum Status: Sendable, Hashable {
        case available
        /// Liegt schon auf der Startseite, an dieser Stelle (1-basiert).
        case onHome(position: Int)
        /// Lässt sich gerade nicht hinzufügen; der Text sagt, was fehlt.
        case unavailable(String)
    }

    /// Schlüssel der Reihe (`RowContent.key`), eindeutig über alle Quellen.
    public var id: String
    public var title: String
    public var subtitle: String
    /// Name der Quelle (Untertitel bei Suchtreffern).
    public var source: String
    public var groupID: String
    public var action: Action
    public var status: Status

    public init(id: String, title: String, subtitle: String, source: String, groupID: String, action: Action, status: Status) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.source = source
        self.groupID = groupID; self.action = action; self.status = status
    }

    public var isOnHome: Bool { if case .onHome = status { true } else { false } }

    /// Rechte Spalte: „auf der Startseite (7)“, der fehlende Dienst oder die Art.
    public var statusText: String {
        switch status {
        case .available: subtitle
        case .onHome(let p): "auf der Startseite (\(p))"
        case .unavailable(let why): why
        }
    }
}
