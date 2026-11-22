import Foundation

/// Welle E-b: Quellenliste folgt dem Addon (Reihenfolge, Text, Filter). Reine Regeln, die App zeigt nur an.

/// Anzeige-Reihenfolge der Quellenliste (Einstellung „Quellen sortieren“).
public enum StreamOrderMode: String, Codable, Sendable, CaseIterable {
    /// Reihenfolge, in der die Addons liefern (Addon-Reihenfolge im Profil, darin die Liste des Addons).
    case addon
    /// Ordnung der App aus Welle C-d (`SourceRanking`).
    case smart

    public var label: String {
        switch self {
        case .addon: "Wie Addon"
        case .smart: "Smart (App)"
        }
    }
}

/// Eigene Plaketten der App in der Quellenliste (Einstellung „App-Plaketten in der Quellenliste“).
public enum StreamListBadgeMode: String, Codable, Sendable, CaseIterable {
    case off
    /// Nur „sofort“ und Größe, und nur, wenn der Addon-Text sie nicht schon zeigt.
    case compact

    public var label: String {
        switch self {
        case .off: "Aus"
        case .compact: "Kompakt"
        }
    }
}

/// Dubletten in einer Quellenliste. Schlüssel einer Quelle: infoHash+fileIdx, Adresse, Dateiname+Größe (je nur,
/// wenn vorhanden). Zwei Einträge desselben Addons sind gleich, sobald einer ihrer Schlüssel übereinstimmt: AIOStreams
/// verpackt dieselbe Datei aus mehreren Scrapern hinter verschiedenen, verschlüsselten Abspiel-Adressen; dort trifft
/// erst Dateiname+Größe. Der erste Eintrag bleibt (Reihenfolge und `id` der übrigen unverändert).
/// Review E-b I1: infoHash- und Datei-Schlüssel enthalten den Debrid-Dienst (TB, RD, …; unbekannt „-“). Dieselbe
/// Datei bei zwei Diensten bleibt zwei Zeilen (Cache-Status kann je Dienst anders sein); die Adresse ist ohnehin je Dienst.
public enum StreamDedupe {
    public static func keys(_ s: StreamItem) -> [String] {
        var out: [String] = []
        let service = ReleaseName.service(s) ?? "-"
        if let h = s.infoHash?.trimmingCharacters(in: .whitespaces).lowercased(), !h.isEmpty {
            out.append("h|\(service)|\(h)|\(s.fileIdx.map(String.init) ?? "-")")
        }
        if let u = s.url?.trimmingCharacters(in: .whitespaces), !u.isEmpty { out.append("u|\(u)") }
        if let f = s.behaviorHints?.filename?.trimmingCharacters(in: .whitespaces), !f.isEmpty,
           let size = s.behaviorHints?.videoSize, size > 0 {
            out.append("f|\(service)|\(f.lowercased())|\(size)")
        }
        return out
    }

    /// Dubletten je Addon entfernen; über die ganze Liste nie zwei Einträge mit gleicher `id` (ForEach-Identität).
    public static func unique<T>(_ list: [(addon: String, stream: T)], stream: (T) -> StreamItem) -> [(addon: String, stream: T)] {
        var seen: [String: Set<String>] = [:]
        var ids = Set<String>()
        return list.filter { e in
            let s = stream(e.stream)
            let k = keys(s)
            let dup = k.contains { seen[e.addon, default: []].contains($0) }
            // Auch die Schlüssel einer verworfenen Dublette merken (A~B über Datei, B~C über Adresse → C ist A).
            // Alle Schlüssel einer Quelle tragen denselben Dienst (Adresse: dieselbe Abspiel-Verbindung), die Kette
            // springt also nicht auf einen anderen Dienst über (Review E-b M4).
            seen[e.addon, default: []].formUnion(k)
            return ids.insert(s.id).inserted && !dup
        }
    }

    public static func unique(_ list: [(addon: String, stream: StreamItem)]) -> [(addon: String, stream: StreamItem)] {
        unique(list) { $0 }
    }
}

/// Reihenfolge für Anzeige und automatische Wahl.
public enum StreamListOrder {
    /// Anzeige: Dubletten raus, dann je nach Einstellung Addon-Reihenfolge oder `SourceRanking`.
    public static func display(_ list: [(addon: String, stream: StreamItem)], mode: StreamOrderMode,
                               context: SourceRankContext) -> [(addon: String, stream: StreamItem)] {
        ordered(StreamDedupe.unique(list), mode: mode, context: context)
    }

    /// Wie `display`, für eine schon von Dubletten befreite Liste (die App braucht sie auch fürs Log).
    public static func ordered(_ unique: [(addon: String, stream: StreamItem)], mode: StreamOrderMode,
                               context: SourceRankContext) -> [(addon: String, stream: StreamItem)] {
        mode == .smart && unique.count > 1 ? SourceRanking.order(unique, context: context) : unique
    }

    /// Automatische Wahl (Weiterschauen, Rückfall, nächste Folge): immer `SourceRanking`, unabhängig von der Anzeige.
    /// Die Ordnung ist stabil und hält die Addon-Reihenfolge innerhalb gleicher Stufe; sie schiebt nur nach hinten,
    /// was die App besser weiß als das Addon (Dekoder des Geräts, Wunschsprache, sicher ungecacht).
    public static func automatic(_ list: [(addon: String, stream: StreamItem)],
                                 context: SourceRankContext) -> [(addon: String, stream: StreamItem)] {
        let u = StreamDedupe.unique(list)
        return u.count > 1 ? SourceRanking.order(u, context: context) : u
    }
}

/// Text einer Zeile genau wie vom Formatter des Addons: `name` und `description` (ältere Addons: `title`),
/// Zeilenumbrüche und Emoji bleiben. Welle F-i: der ganze Text (bis `maxLines` Zeilen je Spalte); die Zeile wächst
/// mit. Nur bei mehr Zeilen wird gekürzt, und dann stehen Zeilen mit Cache-Zustand („⚡Ready“, „❌ Not Ready“, „⏳“)
/// zuerst, damit sie nie wegfallen.
public struct StreamRowText: Equatable, Sendable {
    public static let maxLines = 12
    public var name: String
    public var body: String
    /// Wave Q: the full file name (`behaviorHints.filename`) as its own wrapped line, only when the formatter text
    /// does not already carry it (formatters often cut it or leave it out; its end holds group and audio).
    public var fileName: String?

    public init(_ s: StreamItem) {
        name = Self.capped(s.name ?? "")
        var b = Self.capped(s.label)
        if b.isEmpty, let f = s.behaviorHints?.filename { b = Self.capped(f) }
        body = b
        fileName = Self.extraFileName(s.behaviorHints?.filename, shown: name + "\n" + b)
    }

    /// File name not yet in `shown`. Compared on letters and digits only, ignoring case and a video extension:
    /// the same name with spaces for dots or without ".mkv" counts as shown, a cut one ("Movie.2023.2160p…") does
    /// not, so the full name follows.
    public static func extraFileName(_ file: String?, shown: String) -> String? {
        guard let f = file?.trimmingCharacters(in: .whitespacesAndNewlines), !f.isEmpty else { return nil }
        var stem = f
        if let dot = f.lastIndex(of: "."), videoExtensions.contains(f[f.index(after: dot)...].lowercased()) {
            stem = String(f[..<dot])
        }
        let key = normalized(stem)
        guard !key.isEmpty else { return nil }
        return normalized(shown).contains(key) ? nil : f
    }

    private static let videoExtensions: Set<String> = ["mkv", "mp4", "m4v", "avi", "mov", "ts", "m2ts", "webm", "wmv"]

    private static func normalized(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// CR/LF vereinheitlichen, Leerraum außen weg; mehr als `lines` Zeilen → Zeilen mit Cache-Zustand vorn, dann die
    /// übrigen in Formatter-Reihenfolge, letzte mit „…“.
    public static func capped(_ text: String, lines: Int = maxLines) -> String {
        let t = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = t.components(separatedBy: "\n")
        guard parts.count > lines, lines > 0 else { return t }
        let status = parts.filter { StreamTraits.cacheStatus($0) != nil }
        let rest = parts.filter { StreamTraits.cacheStatus($0) == nil }
        return (status + rest).prefix(lines).joined(separator: "\n") + " …"
    }
}

/// App-Plaketten der Quellenliste: Cache-Zustand (links, immer wenn bekannt) und kompakt die Größe (rechts, nur wenn
/// der Addon-Text sie nicht schon zeigt); jeweils nur, wenn der Typ in den Plaketten-Einstellungen an ist.
public enum StreamListBadges {
    /// Welle F-i: Cache-Zustand als eigene Plakette in der linken Spalte, unabhängig vom Addon-Text und von
    /// „App-Plaketten“ (nur die Plaketten-Einstellung „Cache-Status“ schaltet sie ab). Unbekannt → keine Plakette.
    public static func cacheBadge(_ s: StreamItem, settings: BadgeSettings) -> QualityBadge? {
        guard settings.shows(.cacheStatus) else { return nil }
        switch StreamTraits.parse(s).cached {
        case true?: return QualityBadge(type: .cacheStatus, text: QualityBadges.cachedText, tone: .ready)
        case false?: return QualityBadge(type: .cacheStatus, text: QualityBadges.uncachedText, tone: .pending)
        case nil: return nil
        }
    }

    /// Kompakte Plaketten rechts: nur noch die Größe (der Cache-Zustand steht links, `cacheBadge`).
    public static func badges(_ s: StreamItem, mode: StreamListBadgeMode, settings: BadgeSettings) -> [QualityBadge] {
        guard mode == .compact else { return [] }
        let t = StreamTraits.parse(s)
        let text = [s.name, s.description ?? s.title].compactMap { $0 }.joined(separator: "\n")
        var out: [QualityBadge] = []
        if let b = t.sizeBytes, b > 0, settings.shows(.size), !showsSize(text) {
            out.append(QualityBadge(type: .size, text: QualityBadges.formatSize(b)))
        }
        return out
    }

    /// Addon-Text nennt eine Größe („5.93 GB“, „1,4 GiB“, „850MB“).
    public static func showsSize(_ text: String) -> Bool {
        text.range(of: #"\d+(?:[.,]\d+)?\s*(?:[KMGT]i?B)(?![A-Za-z])"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
