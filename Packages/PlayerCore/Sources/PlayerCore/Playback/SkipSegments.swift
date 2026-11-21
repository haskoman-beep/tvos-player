import Foundation

/// Ein überspringbarer Bereich der laufenden Datei (Sekunden auf der Zeitachse von `currentTime`/`seek`).
public struct SkipSegment: Sendable, Equatable, Hashable {
    public enum Kind: String, Sendable, CaseIterable { case intro, recap, credits, postCredits }
    public enum Source: String, Sendable { case chapter, introDB }

    public var kind: Kind
    public var start: Double
    public var end: Double
    public var source: Source

    public init(kind: Kind, start: Double, end: Double, source: Source) {
        self.kind = kind; self.start = start; self.end = end; self.source = source
    }

    public var length: Double { end - start }
    /// Knopftext; nil = kein Knopf (Abspann steuert nur die Nächste-Folge-Karte).
    public var buttonTitle: String? {
        switch kind {
        case .intro: return "Intro überspringen"
        case .recap: return "Rückblick überspringen"
        case .credits, .postCredits: return nil
        }
    }
}

/// Kapitel der Datei, unabhängig von der Engine (Name, Start, Länge in Sekunden).
public struct ChapterMark: Sendable, Equatable {
    public var name: String
    public var start: Double
    /// 0 = unbekannt (dann bis zum nächsten Kapitel bzw. Dateiende).
    public var duration: Double

    public init(name: String, start: Double, duration: Double) {
        self.name = name; self.start = start; self.duration = duration
    }
}

/// Sprungbereiche aus Kapitelnamen, Zusammenführen mit IntroDB, Zeitpunkt der Nächste-Folge-Karte.
public enum SkipSegments {
    /// Kapitel dürfen 5–240 s lang sein (kürzer/länger ist eher ein Handlungskapitel).
    public static let chapterLengthRange: ClosedRange<Double> = 5...240
    /// Abspann zählt für die Nächste-Folge-Karte erst ab diesem Anteil der Laufzeit.
    public static let creditsMinFraction = 0.6

    /// Stichwörter (nach `normalizedTitle`). Der Titel muss im Wesentlichen nur aus dem Stichwort bestehen.
    static let keywords: [String: SkipSegment.Kind] = [
        "intro": .intro, "introduction": .intro, "opening": .intro, "op": .intro, "opening credits": .intro,
        "opening theme": .intro, "opening song": .intro, "title sequence": .intro, "vorspann": .intro,
        "recap": .recap, "previously": .recap, "previously on": .recap, "zuvor": .recap, "rückblick": .recap,
        "was bisher geschah": .recap,
        "credits": .credits, "end credits": .credits, "ending credits": .credits, "closing credits": .credits,
        "ending": .credits, "ed": .credits, "outro": .credits, "abspann": .credits,
        "post credits": .postCredits, "post credits scene": .postCredits, "after credits": .postCredits,
        "mid credits": .postCredits, "mid credits scene": .postCredits,
    ]

    /// Kleinschreibung, Satzzeichen weg, Ziffern am Wortende weg („OP2“ → „op“, „Opening 2“ → „opening“),
    /// reine Zahlen weg. Ergebnis: Wörter mit je einem Leerzeichen.
    static func normalizedTitle(_ s: String) -> String {
        let lowered = s.lowercased()
        var words: [String] = []
        var current = ""
        for ch in lowered {
            if ch.isLetter || ch.isNumber { current.append(ch) }
            else if !current.isEmpty { words.append(current); current = "" }
        }
        if !current.isEmpty { words.append(current) }
        return words.compactMap { w -> String? in
            var t = w
            while let last = t.last, last.isNumber { t.removeLast() }
            return t.isEmpty ? nil : t
        }.joined(separator: " ")
    }

    /// Art eines Kapitels nach seinem Titel; nil = kein Sprungkapitel.
    public static func kind(ofChapterTitle title: String) -> SkipSegment.Kind? {
        keywords[normalizedTitle(title)]
    }

    /// Sprungbereiche aus Kapiteln. Je Art nur der erste passende Bereich.
    public static func fromChapters(_ chapters: [ChapterMark], duration: Double) -> [SkipSegment] {
        let sorted = chapters.sorted { $0.start < $1.start }
        var out: [SkipSegment] = []
        for (i, c) in sorted.enumerated() {
            guard let kind = kind(ofChapterTitle: c.name), !out.contains(where: { $0.kind == kind }) else { continue }
            let end: Double
            if c.duration > 0 { end = c.start + c.duration }
            else if i + 1 < sorted.count { end = sorted[i + 1].start }
            else if duration > c.start { end = duration }
            else { continue }
            let seg = SkipSegment(kind: kind, start: max(0, c.start), end: end, source: .chapter)
            guard chapterLengthRange.contains(seg.length) else { continue }
            out.append(seg)
        }
        return out
    }

    /// Je Art gewinnt das Kapitel; IntroDB füllt fehlende Arten. Bereiche außerhalb der Datei fallen weg
    /// (IntroDB-Zeiten stammen evtl. von einer anderen Veröffentlichung), Enden werden aufs Dateiende gekürzt.
    public static func merge(chapters: [SkipSegment], introDB: [SkipSegment], duration: Double) -> [SkipSegment] {
        var out = chapters
        for s in introDB where !out.contains(where: { $0.kind == s.kind }) { out.append(s) }
        return out.compactMap { s -> SkipSegment? in
            var s = s
            if duration > 0 {
                guard s.start < duration else { return nil }
                s.end = min(s.end, duration)
            }
            return s.end - s.start >= 1 ? s : nil
        }.sorted { $0.start < $1.start }
    }

    /// Zeitpunkt für die Nächste-Folge-Karte aus dem Abspann, nil = Standard (keine Angabe).
    /// - Abspann muss nach 60 % der Laufzeit beginnen.
    /// - Gibt es eine Szene nach dem Abspann (eigener Bereich), wartet die Karte bis zu deren Ende,
    ///   außer sie reicht bis ans Dateiende (dann Standard).
    /// - Bleiben nach dem Abspann mehr als 5 s ohne bekannten Inhalt, ist eine Nachspann-Szene möglich: Standard.
    public static func upNextTime(_ segments: [SkipSegment], duration: Double) -> Double? {
        guard duration > 0,
              let credits = segments.first(where: { $0.kind == .credits && $0.start >= creditsMinFraction * duration
                                                    && $0.start < duration })
        else { return nil }
        if let post = segments.first(where: { $0.kind == .postCredits && $0.start >= credits.start }) {
            return post.end < duration - 2 ? post.end : nil
        }
        if duration - credits.end > 5 { return nil }
        return credits.start
    }
}

/// Planer für den Überspringen-Knopf. Zustand `idle` ↔ `seeking`: Während eines Sprungs wird der gemeldeten
/// Position nicht getraut (kein Knopf), bis sie am Ziel angekommen ist oder die Wartezeit abläuft.
public struct SkipPlanner: Sendable {
    public private(set) var segments: [SkipSegment] = []
    /// Laufender Sprung: Ziel und Startzeit (monotone Sekunden des Aufrufers).
    public private(set) var seeking: (target: Double, since: Double)?
    /// Mit Menü/Zurück weggeschickte Bereiche; erscheinen erst wieder, wenn die Position den Bereich verlassen hat.
    private var dismissed: Set<SkipSegment> = []
    /// Nach so vielen Sekunden gilt ein Sprung auch ohne Ankunft als beendet.
    public static let seekTimeout: Double = 8
    /// Abstand zum Ziel, ab dem die Position als angekommen gilt.
    public static let arrivalTolerance: Double = 2
    /// Kurz vor dem Bereichsende kein Knopf mehr (Sprung lohnt nicht).
    public static let endMargin: Double = 1

    public init(segments: [SkipSegment] = []) { self.segments = segments }

    public mutating func setSegments(_ s: [SkipSegment]) {
        segments = s
        dismissed = dismissed.filter { s.contains($0) }
    }

    /// Neuer Positionsstand (jede Sekunde o. ä.). `engineSeeking`: Engine meldet Laden/Springen.
    public mutating func observe(position: Double, engineSeeking: Bool, now: Double) {
        if let s = seeking {
            let arrived = !engineSeeking && position >= s.target - Self.arrivalTolerance
                && position <= s.target + Self.arrivalTolerance + 5
            if arrived || now - s.since >= Self.seekTimeout { seeking = nil }
        }
        guard seeking == nil, !engineSeeking else { return }
        dismissed = dismissed.filter { $0.start <= position && position < $0.end }
    }

    /// Bereich, für den jetzt ein Knopf erscheinen soll; nil = keiner.
    public func prompt(at position: Double, engineSeeking: Bool) -> SkipSegment? {
        guard seeking == nil, !engineSeeking else { return nil }
        return segments.first {
            $0.buttonTitle != nil && $0.start <= position && position < $0.end - Self.endMargin && !dismissed.contains($0)
        }
    }

    /// Sprung beginnen; liefert das Ziel (Bereichsende, vor dem Dateiende gehalten).
    public mutating func beginSkip(_ s: SkipSegment, duration: Double, now: Double) -> Double {
        var target = s.end
        if duration > 10 { target = min(target, duration - 5) }
        target = max(0, target)
        seeking = (target, now)
        // Ankunft zählt ab Ziel − 2 s, der Knopf stünde bis Ende − 1 s: ohne das flackerte er nach dem Sprung kurz auf.
        // Wird aufgehoben, sobald die Position den Bereich verlassen hat (observe).
        dismissed.insert(s)
        return target
    }

    /// Knopf für diesen Bereich ausblenden (Menü/Zurück).
    public mutating func dismiss(_ s: SkipSegment) { dismissed.insert(s) }
}
