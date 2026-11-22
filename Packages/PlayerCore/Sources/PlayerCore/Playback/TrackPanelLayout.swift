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
    /// Kleiner Hinweis unter der Überschrift (nur Versatz, wenn er bei der Spur nicht wirkt); nil = keiner.
    public var note: String?
    public var rows: [TrackPanelRow]

    public init(column: TrackPanelColumn, title: String, note: String? = nil, rows: [TrackPanelRow]) {
        self.column = column; self.title = title; self.note = note; self.rows = rows
    }

    /// Zeile beim Betreten der Spalte: die aktive, sonst die erste.
    public var entryRow: TrackPanelRowID? { (rows.first(where: \.isActive) ?? rows.first)?.id }
}

public enum TrackPanelLayout {
    /// Höchstlänge einer Zeile in Zeichen (schmale Spalte, eine Zeile, Platz für Häkchen und Marke).
    public static let maxLineLength = 34

    /// Panelhöhe: ein Drittel des Bildschirms, darunter bleibt das Video sichtbar.
    public static func panelHeight(screenHeight: Double) -> Double {
        guard screenHeight.isFinite, screenHeight > 0 else { return 0 }
        return (screenHeight / 3).rounded(.down)
    }

    // MARK: Spalten

    /// Ton-Spalte in Panel-Reihenfolge (Profil-Tonsprachen zuerst).
    public static func audioColumn(_ tracks: [AudioTrackInfo], activeID: Int?, priority: [String]) -> TrackPanelColumnModel {
        let sorted = TrackPanelLogic.sortedAudio(tracks, priority: priority)
        let lines = audioLines(sorted)
        let rows = sorted.enumerated().map { i, t in
            TrackPanelRow(id: .track(t.id), line: lines[i], tag: tag(t), isActive: t.id == activeID)
        }
        return TrackPanelColumnModel(column: .audio, title: TrackPanelColumn.audio.title, rows: rows)
    }

    /// Untertitel-Spalte: „Aus“ zuerst, dann die Spuren nach Sprache (Profil-UT-Sprache zuerst).
    /// Eine aktive ID ohne passende Spur zählt als „Aus“.
    public static func subtitleColumn(_ tracks: [AudioTrackInfo], activeID: Int?, preferredLanguage: String?) -> TrackPanelColumnModel {
        let sorted = TrackPanelLogic.subtitleGroups(tracks, preferredLanguage: preferredLanguage).flatMap(\.tracks)
        let lines = subtitleLines(sorted)
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
        return TrackPanelColumnModel(column: .offset, title: title, note: nativeTrack ? "wirkt bei dieser Spur nicht" : nil, rows: rows)
    }

    // MARK: Fokus

    /// Startfokus: Ton auf der aktiven Spur, ohne Tonspuren die Untertitel-Spalte.
    public static func initialSpot(_ columns: [TrackPanelColumnModel]) -> TrackPanelSpot? {
        for c in columns where c.column != .offset {
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
    /// (sonst ist es ein Schritt nach oben in der Liste). Ohne Fokus schließt er immer.
    public static func closesOnSwipeUp(startSpot: TrackPanelSpot?, columns: [TrackPanelColumnModel]) -> Bool {
        guard let s = startSpot, let c = columns.first(where: { $0.column == s.column }) else { return true }
        return c.rows.first?.id == s.row
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

    /// Ton-Zeilen in Listenreihenfolge, gleiche Zeilen unterschieden (Spurname, sonst „Spur n“).
    public static func audioLines(_ tracks: [AudioTrackInfo]) -> [String] {
        lines(tracks) { t, i in
            let format = shortAudioFormat(t)
            let head = lead(t, number: i + 1, fallbackFormat: format)
            // Ist das Format schon der Hauptteil (unbekannte Sprache), bleiben nur die Kanäle.
            let tech = [head == format ? nil : format, MediaLabels.channels(t.channels, layout: t.channelLayout)]
                .compactMap { $0 }.joined(separator: " ")
            return (head, kind(t, audio: true), tech.isEmpty ? nil : tech)
        }
    }

    /// Untertitel-Zeilen („Englisch“, „Englisch · Erzwungen“), gleiche Zeilen unterschieden
    /// (Spurname, sonst Format, sonst „Spur n“).
    public static func subtitleLines(_ tracks: [AudioTrackInfo]) -> [String] {
        lines(tracks) { t, i in
            (lead(t, number: i + 1, fallbackFormat: TrackPanelLogic.subtitleFormat(codec: t.codec, isImage: t.isImage)),
             kind(t, audio: false), nil)
        } extra: { t in
            TrackPanelLogic.subtitleFormat(codec: t.codec, isImage: t.isImage).map { $0.replacingOccurrences(of: " · ", with: " ") }
        }
    }

    /// Teile wichtigste zuerst anfügen, solange die Zeile in `max` passt; der erste Teil bleibt immer
    /// (zu lang: mit „…“ gekürzt). Leere Teile fallen weg.
    public static func fit(_ parts: [String?], max: Int = maxLineLength) -> String {
        let p = parts.compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = p.first else { return "" }
        var line = first.count > max ? String(first.prefix(Swift.max(max - 1, 0))) + "…" : first
        for part in p.dropFirst() {
            let next = line + " · " + part
            if next.count <= max { line = next }
        }
        return line
    }

    // MARK: intern

    /// Zeilen aus (Hauptteil, Art, Technik); doppelte Zeilen bekommen den Unterscheider (Spurname, dann
    /// `extra`) direkt hinter Hauptteil und Art, notfalls „Spur n“. Kürzung über `fit`: Technik fällt zuerst weg.
    private static func lines(_ tracks: [AudioTrackInfo],
                              base: (AudioTrackInfo, Int) -> (lead: String, kind: String?, tech: String?),
                              extra: (AudioTrackInfo) -> String? = { _ in nil }) -> [String] {
        let parts = tracks.enumerated().map { i, t in base(t, i) }
        func build(_ disambiguate: (Int) -> String?) -> [String] {
            parts.indices.map { i in
                let d = disambiguate(i)
                return fit([parts[i].lead, parts[i].kind, d == parts[i].lead ? nil : d, parts[i].tech])
            }
        }
        func duplicates(_ l: [String]) -> Set<Int> {
            var count: [String: Int] = [:]
            l.forEach { count[$0, default: 0] += 1 }
            return Set(l.indices.filter { count[l[$0], default: 0] > 1 })
        }
        var out = build { _ in nil }
        var dup = duplicates(out)
        guard !dup.isEmpty else { return out }
        let names = tracks.map { TrackPanelLogic.meaningfulName($0) ?? extra($0) }
        let first = dup
        out = build { first.contains($0) ? names[$0] : nil }
        dup = duplicates(out)
        guard !dup.isEmpty else { return out }
        let second = dup
        return build { i in
            guard first.contains(i) else { return nil }
            if second.contains(i) { return "Spur \(i + 1)" }
            return names[i]
        }
    }

    /// Hauptteil: Sprache; bei unbekannter Sprache der Spurname, sonst das Format, sonst „Spur n“.
    private static func lead(_ t: AudioTrackInfo, number: Int, fallbackFormat: String?) -> String {
        guard TrackPanelLogic.isUnknownLanguage(t.language) else { return MediaLabels.languageName(t.language) }
        return TrackPanelLogic.meaningfulName(t) ?? fallbackFormat ?? "Spur \(number)"
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
