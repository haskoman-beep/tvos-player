import Foundation

/// Welle F-h2: Spalten des schmalen Spur-Panels (oben angedockt), nebeneinander statt Reiter.
/// ◀/▶ wechselt die Spalte, ▲/▼ die Zeile, Auswahl wirkt sofort. „Info“ ist eine reine Textspalte ohne Fokus.
public enum TrackPanelColumn: Hashable, Sendable, CaseIterable {
    case audio, subtitles, offset

    public var title: String {
        switch self {
        case .audio: "Ton"
        case .subtitles: "Untertitel"
        case .offset: "Versatz"
        }
    }
}

/// Zeile in einer Spalte: Spur (Engine-ID), „Aus“, Versatz-Schritt (Index in `SubtitleOffset.steps`) oder Zurücksetzen.
public enum TrackPanelRowID: Hashable, Sendable {
    case track(Int)
    case off
    case step(Int)
    case reset
}

/// Fokusstelle im Panel.
public struct TrackPanelSpot: Hashable, Sendable {
    public var column: TrackPanelColumn
    public var row: TrackPanelRowID
    public init(_ column: TrackPanelColumn, _ row: TrackPanelRowID) { self.column = column; self.row = row }
}

/// Eine einzeilige Zeile: „Englisch · Dolby Atmos 5.1“, optional eine kleine Marke („Standard“), Häkchen wenn aktiv.
public struct TrackPanelRow: Equatable, Sendable, Identifiable {
    public var id: TrackPanelRowID
    public var line: String
    public var tag: String?
    public var isActive: Bool
    public init(id: TrackPanelRowID, line: String, tag: String? = nil, isActive: Bool = false) {
        self.id = id; self.line = line; self.tag = tag; self.isActive = isActive
    }
}

/// Eine Spalte mit Überschrift und schmaler Liste.
public struct TrackPanelColumnModel: Equatable, Sendable {
    public var column: TrackPanelColumn
    public var title: String
    /// Kleiner, gedimmter Hinweis neben der Überschrift („lädt…“, „bis Play gesperrt“); nil = keiner.
    public var note: String?
    public var rows: [TrackPanelRow]
    /// Spalte gesperrt (Zeilen deaktiviert, Wahl wird ignoriert), z. B. während eines Tonwechsels.
    public var isLocked: Bool

    public init(column: TrackPanelColumn, title: String, note: String? = nil, rows: [TrackPanelRow], isLocked: Bool = false) {
        self.column = column; self.title = title; self.note = note; self.rows = rows; self.isLocked = isLocked
    }

    /// Zeile beim Betreten der Spalte: die aktive, sonst die erste.
    public var entryRow: TrackPanelRowID? { (rows.first(where: \.isActive) ?? rows.first)?.id }
}

/// Welle F-h2 R1: Maße des Panels und Zeichenbudget einer Zeile aus der echten Spaltenbreite.
/// Breiten: Ton 760 + Untertitel 660 + Versatz 230 + 2 Abstände 32 = 1714 ≤ 1760 (1920 minus Sicherheitsrand 2 × 80).
/// Info steht als eine Fußzeile unter den Spalten, damit Ton und Untertitel die Breite bekommen.
public enum TrackPanelMetrics {
    public static let audioColumnWidth: Double = 760
    public static let subtitleColumnWidth: Double = 660
    public static let offsetColumnWidth: Double = 230
    public static let columnSpacing: Double = 32
    /// Zeilenschrift `.callout` auf tvOS (pt) und mittlere Zeichenbreite gemischter deutscher Texte (Anteil der Größe).
    public static let lineFontSize: Double = 31
    public static let lineCharWidth: Double = 0.53
    /// Innenrand der Zeile (ThemeRowButtonStyle: 2 × Space.m) und der Liste (2 × Space.xs, Platz fürs Anheben).
    public static let rowPadding: Double = 40
    public static let listInset: Double = 16
    /// Häkchen-Platz und Abstand zwischen Häkchen, Text und Marke (Space.xs).
    public static let markWidth: Double = 28
    public static let spacing: Double = 8
    /// Marke: `.caption2.bold()` (23 pt), breitere Zeichen, Innenrand 2 × Space.s.
    public static let tagFontSize: Double = 23
    public static let tagCharWidth: Double = 0.62
    public static let tagPadding: Double = 24

    public static func tagWidth(_ tag: String) -> Double {
        Double(tag.count) * tagFontSize * tagCharWidth + tagPadding
    }

    /// Zeichen, die eine Zeile in dieser Spalte höchstens haben darf (abgerundet, mindestens 8).
    public static func lineBudget(columnWidth: Double, mark: Bool = true, tag: String? = nil) -> Int {
        var room = columnWidth - rowPadding - listInset
        if mark { room -= markWidth + spacing }
        if let tag, !tag.isEmpty { room -= tagWidth(tag) + spacing }
        guard room.isFinite, room > 0 else { return 8 }
        return max(8, Int((room / (lineFontSize * lineCharWidth)).rounded(.down)))
    }
}

public enum TrackPanelLayout {
    /// Panelhöhe: ein Drittel des Bildschirms, darunter bleibt das Video sichtbar.
    public static func panelHeight(screenHeight: Double) -> Double {
        guard screenHeight.isFinite, screenHeight > 0 else { return 0 }
        return (screenHeight / 3).rounded(.down)
    }

    // MARK: Spalten

    /// Ton-Spalte in Panel-Reihenfolge (Profil-Tonsprachen zuerst). `audioLocked`: Tonwahl bis Play gesperrt
    /// (nach dem Hintergrund) – Hinweis neben der Überschrift.
    public static func audioColumn(_ tracks: [AudioTrackInfo], activeID: Int?, priority: [String], audioLocked: Bool = false,
                                   width: Double = TrackPanelMetrics.audioColumnWidth) -> TrackPanelColumnModel {
        let sorted = TrackPanelLogic.sortedAudio(tracks, priority: priority)
        let lines = audioLines(sorted, columnWidth: width)
        let rows = sorted.enumerated().map { i, t in
            TrackPanelRow(id: .track(t.id), line: lines[i], tag: tag(t), isActive: t.id == activeID)
        }
        return TrackPanelColumnModel(column: .audio, title: TrackPanelColumn.audio.title,
                                     note: audioLocked ? "bis Play gesperrt" : nil, rows: rows)
    }

    /// Untertitel-Spalte: „Aus“ zuerst, dann die Spuren nach Sprache (Profil-UT-Sprache zuerst).
    /// Eine aktive ID ohne passende Spur zählt als „Aus“.
    public static func subtitleColumn(_ tracks: [AudioTrackInfo], activeID: Int?, preferredLanguage: String?,
                                      width: Double = TrackPanelMetrics.subtitleColumnWidth) -> TrackPanelColumnModel {
        let sorted = TrackPanelLogic.subtitleGroups(tracks, preferredLanguage: preferredLanguage).flatMap(\.tracks)
        let lines = subtitleLines(sorted, columnWidth: width)
        let activeExists = activeID.map { id in sorted.contains { $0.id == id } } ?? false
        var rows = [TrackPanelRow(id: .off, line: "Aus", isActive: !activeExists)]
        rows += sorted.enumerated().map { i, t in
            TrackPanelRow(id: .track(t.id), line: lines[i], tag: tag(t), isActive: activeExists && t.id == activeID)
        }
        return TrackPanelColumnModel(column: .subtitles, title: TrackPanelColumn.subtitles.title, rows: rows)
    }

    /// Versatz-Spalte: Überschrift mit dem Wert („Versatz +0,3 s“), Zeilen je Schritt, dann „Zurücksetzen“.
    /// `nativeTrack`: die aktive Spur zeichnet das System, der Versatz wirkt dort nicht.
    public static func offsetColumn(offset: Double, nativeTrack: Bool) -> TrackPanelColumnModel {
        let v = SubtitleOffset.normalized(offset)
        let title = v == 0 ? TrackPanelColumn.offset.title : "\(TrackPanelColumn.offset.title) \(SubtitleOffset.label(v))"
        var rows = SubtitleOffset.steps.enumerated().map { i, s in
            TrackPanelRow(id: .step(i), line: SubtitleOffset.stepLabel(s) + " s")
        }
        rows.append(TrackPanelRow(id: .reset, line: "Zurücksetzen"))
        return TrackPanelColumnModel(column: .offset, title: title, note: nativeTrack ? "wirkt hier nicht" : nil, rows: rows)
    }

    /// Sperre auf die Spalten legen: gesperrte Spalten bekommen `isLocked` und den Hinweis „lädt…“ (Tonwechsel)
    /// bzw. „gesperrt“. Häkchen bleiben, wie die Engine sie meldet.
    public static func applying(_ lock: TrackLock?, to columns: [TrackPanelColumnModel]) -> [TrackPanelColumnModel] {
        guard let lock else { return columns }
        return columns.map { c in
            guard lock.blocks(c.column) else { return c }
            var l = c
            l.isLocked = true
            l.note = lock == .audioSwitching ? "lädt…" : "gesperrt"
            return l
        }
    }

    // MARK: Fokus

    /// Startfokus: Ton auf der aktiven Spur, ohne Tonspuren die Untertitel-Spalte.
    public static func initialSpot(_ columns: [TrackPanelColumnModel]) -> TrackPanelSpot? {
        for c in columns where c.column != .offset && !c.isLocked {
            if let r = c.entryRow { return TrackPanelSpot(c.column, r) }
        }
        return nil
    }

    /// Spaltenwechsel (◀/▶): in Ton und Untertitel auf der aktiven Zeile landen statt auf der nächstgelegenen.
    /// Rückgabe: Stelle, auf die umgelenkt wird; nil = so lassen (erster Fokus, gleiche Spalte, Versatz-Spalte).
    public static func redirect(from old: TrackPanelSpot?, to new: TrackPanelSpot, columns: [TrackPanelColumnModel]) -> TrackPanelSpot? {
        guard let old, old.column != new.column, new.column != .offset,
              let entry = columns.first(where: { $0.column == new.column })?.entryRow, entry != new.row else { return nil }
        return TrackPanelSpot(new.column, entry)
    }

    /// Wisch nach oben schließt das Panel nur, wenn der Fokus beim Wischbeginn in der obersten Zeile stand
    /// (sonst ist es ein Schritt nach oben in der Liste). Ohne Fokus oder in einer leeren Spalte schließt er immer.
    public static func closesOnSwipeUp(startSpot: TrackPanelSpot?, columns: [TrackPanelColumnModel]) -> Bool {
        guard let s = startSpot, let c = columns.first(where: { $0.column == s.column }), let top = c.rows.first else { return true }
        return top.id == s.row
    }

    // MARK: Info-Fußzeile

    /// Info als eine Zeile: Werte mit „ · “; Werte, die allein missverständlich sind, mit Bezeichnung.
    public static func infoLine(_ rows: [TrackPanelInfoRow]) -> String? {
        let labelled: Set<String> = ["Ausgabe", "Ton-Ausgabe", "Quelle"]
        let parts = rows.map { labelled.contains($0.label) ? "\($0.label): \($0.value)" : $0.value }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Beschriftung

    /// Kleine Marke: „Standard“ (Container-Flag), sonst „Extern“ bei nachgeladenen Spuren.
    public static func tag(_ t: AudioTrackInfo) -> String? {
        if t.isDefault { return "Standard" }
        return t.isExternal ? "Extern" : nil
    }

    /// Format ohne Klammerzusatz: „Dolby Atmos (DD+)“ → „Dolby Atmos“. „Unbekannt“ → nil.
    public static func shortAudioFormat(_ t: AudioTrackInfo) -> String? {
        let f = MediaLabels.audioFormat(codec: t.codec, profile: t.profile, isAtmos: t.isAtmos, isDTSX: t.isDTSX)
        guard f != "Unbekannt" else { return nil }
        if let p = f.firstIndex(of: "(") { return String(f[..<p]).trimmingCharacters(in: .whitespaces) }
        return f
    }

    /// Sprachformen von lang nach kurz: „Portugiesisch (Brasilien)“, „Port. (BR)“, „pt-BR“.
    /// Unbekannte Sprache → leer (dann zählt der Ersatz-Hauptteil).
    public static func languageForms(_ raw: String?) -> [String] {
        guard !TrackPanelLogic.isUnknownLanguage(raw), let code = MediaLabels.languageCode(raw) else { return [] }
        let name = MediaLabels.languageName(raw)
        var forms = [name]
        func abbrev(_ w: String) -> String { w.count > 6 ? String(w.prefix(4)) + "." : w }
        if let paren = name.range(of: " (") {
            let base = String(name[..<paren.lowerBound])
            let region = code.split(separator: "-").dropFirst().first.map { String($0).uppercased() }
            forms.append(region.map { "\(abbrev(base)) (\($0))" } ?? abbrev(base))
        } else if name.count > 10 {
            forms.append(abbrev(name))
        }
        forms.append(code)
        var seen = Set<String>()
        return forms.filter { seen.insert($0).inserted }
    }

    /// Ton-Zeilen in Listenreihenfolge, Budget je Zeile aus der Spaltenbreite (mit Marke weniger).
    public static func audioLines(_ tracks: [AudioTrackInfo], columnWidth: Double = TrackPanelMetrics.audioColumnWidth) -> [String] {
        lines(tracks, budget: { TrackPanelMetrics.lineBudget(columnWidth: columnWidth, tag: tag($0)) }) { t, i in
            let format = shortAudioFormat(t)
            let forms = leadForms(t, number: i + 1, fallbackFormat: format)
            // Ist das Format schon der Hauptteil (unbekannte Sprache), bleiben nur die Kanäle.
            let tech = [forms.first == format ? nil : format, MediaLabels.channels(t.channels, layout: t.channelLayout)]
                .compactMap { $0 }.joined(separator: " ")
            return Parts(lead: forms, kind: kind(t, audio: true), tech: tech.isEmpty ? nil : tech)
        }
    }

    /// Untertitel-Zeilen („Englisch“, „Englisch · Erzwungen“), Budget je Zeile aus der Spaltenbreite.
    public static func subtitleLines(_ tracks: [AudioTrackInfo], columnWidth: Double = TrackPanelMetrics.subtitleColumnWidth) -> [String] {
        lines(tracks, budget: { TrackPanelMetrics.lineBudget(columnWidth: columnWidth, tag: tag($0)) }) { t, i in
            Parts(lead: leadForms(t, number: i + 1, fallbackFormat: TrackPanelLogic.subtitleFormat(codec: t.codec, isImage: t.isImage)),
                  kind: kind(t, audio: false), tech: nil)
        } extra: { t in
            TrackPanelLogic.subtitleFormat(codec: t.codec, isImage: t.isImage).map { $0.replacingOccurrences(of: " · ", with: " ") }
        }
    }

    /// Eine Zeile in `max` Zeichen. Art (`kind`) und Unterscheider (`key`) fallen nie weg; zuerst wird die Sprache
    /// gekürzt (`lead`: Formen von lang nach kurz), die Technik fällt vor der Kurzform des Codes weg, zuletzt wird
    /// die kürzeste Sprachform mit „…“ gekappt. Passen Art und Unterscheider allein nicht, bleibt die Zeile zu lang
    /// (das System kürzt dann am Ende) – bei realen Spaltenbreiten (Budget ≥ 20) kommt das nicht vor.
    public static func fit(lead: [String], kind: String? = nil, key: String? = nil, tech: String? = nil, max: Int) -> String {
        let fixed = [kind, key].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let forms = lead.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let t = tech?.trimmingCharacters(in: .whitespaces)
        func join(_ l: String?, _ tech: String?) -> String {
            ([l].compactMap { $0 } + fixed + [tech].compactMap { $0 }.filter { !$0.isEmpty }).joined(separator: " · ")
        }
        guard let longest = forms.first else { return join(nil, t).count <= max ? join(nil, t) : join(nil, nil) }
        // Mit Technik nur Langname und Kurzform (nicht der Code), dann ohne Technik alle Formen.
        if let t, !t.isEmpty {
            for l in forms.prefix(2) where join(l, t).count <= max { return join(l, t) }
        }
        for l in forms where join(l, nil).count <= max { return join(l, nil) }
        let shortest = forms.last ?? longest
        let rest = join("", nil).count            // Trenner und feste Teile
        let room = max - rest
        guard room >= 2 else { return join(String(shortest.prefix(1)) + "…", nil) }
        return join(String(shortest.prefix(room - 1)) + "…", nil)
    }

    // MARK: intern

    struct Parts {
        var lead: [String]
        var kind: String?
        var tech: String?
    }

    /// Zeilen mit garantiert verschiedenem Text. Doppelte bekommen einen Unterscheider (Spurname bzw. `extra`),
    /// bleiben sie gleich, „Spur n“ (n = Listenplatz); bleibt dann noch etwas gleich, bekommt die ganze Gruppe „Spur n“.
    private static func lines(_ tracks: [AudioTrackInfo], budget: (AudioTrackInfo) -> Int,
                              base: (AudioTrackInfo, Int) -> Parts,
                              extra: (AudioTrackInfo) -> String? = { _ in nil }) -> [String] {
        let parts = tracks.enumerated().map { i, t in base(t, i) }
        let budgets = tracks.map(budget)
        func build(_ key: (Int) -> String?) -> [String] {
            parts.indices.map { i in
                let k = key(i)
                return fit(lead: parts[i].lead, kind: parts[i].kind, key: k == parts[i].lead.first ? nil : k,
                           tech: parts[i].tech, max: budgets[i])
            }
        }
        func duplicates(_ l: [String]) -> Set<Int> {
            var count: [String: Int] = [:]
            l.forEach { count[$0, default: 0] += 1 }
            return Set(l.indices.filter { count[l[$0], default: 0] > 1 })
        }
        var out = build { _ in nil }
        let first = duplicates(out)
        guard !first.isEmpty else { return out }
        let names = tracks.map { TrackPanelLogic.meaningfulName($0) ?? extra($0) }
        out = build { first.contains($0) ? names[$0] : nil }
        let second = duplicates(out)
        guard !second.isEmpty else { return out }
        out = build { i in second.contains(i) ? "Spur \(i + 1)" : (first.contains(i) ? names[i] : nil) }
        guard !duplicates(out).isEmpty else { return out }
        return build { i in first.contains(i) || second.contains(i) ? "Spur \(i + 1)" : nil }
    }

    /// Hauptteil-Formen: Sprache (lang → kurz); bei unbekannter Sprache der Spurname, sonst das Format, sonst „Spur n“.
    private static func leadForms(_ t: AudioTrackInfo, number: Int, fallbackFormat: String?) -> [String] {
        let forms = languageForms(t.language)
        if !forms.isEmpty { return forms }
        return [TrackPanelLogic.meaningfulName(t) ?? fallbackFormat ?? "Spur \(number)"]
    }

    /// Art der Spur als Wort in der Zeile (Inhalt, keine Marke).
    private static func kind(_ t: AudioTrackInfo, audio: Bool) -> String? {
        if t.isCommentary { return "Kommentar" }
        if audio, t.isVisualImpaired { return "Hörfilm" }
        if !audio, t.isForced { return "Erzwungen" }
        if !audio, t.isHearingImpaired { return "SDH" }
        return nil
    }
}
