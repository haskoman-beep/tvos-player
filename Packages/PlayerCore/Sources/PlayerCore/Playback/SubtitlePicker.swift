import Foundation

/// Ergebnis der automatischen Untertitel-Wahl beim Start.
public struct SubtitlePick: Equatable, Sendable {
    /// nil = Untertitel aus.
    public var track: AudioTrackInfo?
    /// Kurzer Grund für das Log, z. B. "erzwungen in Tonsprache".
    public var reason: String

    public init(track: AudioTrackInfo?, reason: String) { self.track = track; self.reason = reason }

    /// `UT gewählt: <Sprache> <Plaketten> (Grund)` bzw. `UT aus (Grund)`.
    public var logText: String {
        guard let t = track else { return "UT aus (\(reason))" }
        let badges = MediaLabels.trackBadges(isForced: SubtitlePicker.isForced(t), isHearingImpaired: SubtitlePicker.isSDH(t),
                                             isCommentary: t.isCommentary, isDefault: t.isDefault, isExternal: t.isExternal)
        let head = ([MediaLabels.languageName(t.language)] + badges).joined(separator: " ")
        return "UT gewählt: \(head) (\(reason))"
    }
}

/// Einstellungen für die automatische Untertitel-Wahl, aus dem Profil.
public struct SubtitlePreferences: Equatable, Sendable {
    public var mode: SubtitleMode
    public var preferredLanguage: String?
    public var secondaryLanguages: [String]

    public init(mode: SubtitleMode, preferredLanguage: String?, secondaryLanguages: [String]) {
        self.mode = mode; self.preferredLanguage = preferredLanguage; self.secondaryLanguages = secondaryLanguages
    }

    public init(profile: Profile) {
        self.init(mode: profile.subtitleMode, preferredLanguage: profile.subtitleLanguage,
                  secondaryLanguages: SubtitlePicker.secondaryLanguages(preferred: profile.subtitleLanguage,
                                                                        audioPriority: profile.audioPriority))
    }
}

/// Automatische Untertitel-Wahl (reine Logik, ohne Engine).
///
/// Regeln:
/// - Kommentarspuren werden nie automatisch gewählt.
/// - Sprachen werden nur über `MediaLabels.languageCode` verglichen (ger/deu/de → "de").
/// - `.off`: aus.
/// - `.forcedOnly`: erzwungene Spur in der Tonsprache (Tonsprache unbekannt → Wunschsprache).
///   Ist die Tonsprache keine der Sprachen des Nutzers (Wunschsprache, Zweitsprachen), wird wie bei
///   `.always` eine volle Spur gesucht, sonst versteht man den Film nicht.
/// - `.always`: volle Spur in der Wunschsprache (Nicht-SDH vor SDH), sonst in einer Zweitsprache,
///   sonst wenigstens die erzwungene Spur in der Tonsprache. Eine erzwungene Spur steht hier bewusst
///   hinten: „Immer“ heißt voller Dialog, eine erzwungene Spur zeigt nur Schilder.
/// - Innerhalb einer Sprache: Nicht-SDH vor SDH, dann Container-Standard, dann Reihenfolge der Datei.
/// - Erzwungen/SDH/Kommentar zählen auch, wenn nur der Spurname es sagt ("Forced", "SDH", "Commentary").
public enum SubtitlePicker {
    /// Wie `pick(_:mode:preferredLanguage:audioLanguage:secondaryLanguages:)`, mit gebündelten Einstellungen.
    public static func pick(_ tracks: [AudioTrackInfo], preferences p: SubtitlePreferences, audioLanguage: String?) -> SubtitlePick {
        pick(tracks, mode: p.mode, preferredLanguage: p.preferredLanguage, audioLanguage: audioLanguage,
             secondaryLanguages: p.secondaryLanguages)
    }

    public static func pick(_ tracks: [AudioTrackInfo], mode: SubtitleMode, preferredLanguage: String?,
                            audioLanguage: String?, secondaryLanguages: [String] = []) -> SubtitlePick {
        guard mode != .off else { return SubtitlePick(track: nil, reason: "Einstellung Aus") }
        guard !tracks.isEmpty else { return SubtitlePick(track: nil, reason: "keine Untertitelspuren") }
        let usable = tracks.filter { !isCommentary($0) }
        let wish = MediaLabels.languageCode(preferredLanguage)
        let audio = MediaLabels.languageCode(audioLanguage)
        var known: [String] = []
        for code in [wish] + secondaryLanguages.map({ MediaLabels.languageCode($0) }) {
            if let code, !known.contains(code) { known.append(code) }
        }
        let forcedLanguage = audio ?? wish
        let forced = forcedLanguage.flatMap { lang in best(usable.filter { isForced($0) && code($0) == lang }) }

        func fullTrack() -> SubtitlePick? {
            for (i, lang) in known.enumerated() {
                guard let t = best(usable.filter { !isForced($0) && code($0) == lang }) else { continue }
                return SubtitlePick(track: t, reason: i == 0 ? "Wunschsprache" : "Zweitsprache")
            }
            return nil
        }

        switch mode {
        case .off:
            return SubtitlePick(track: nil, reason: "Einstellung Aus")
        case .forcedOnly:
            // Fremde Tonsprache zuerst: erzwungene Stellen in einer Sprache, die man nicht versteht, helfen nicht.
            if let audio, !known.isEmpty, !known.contains(audio), var full = fullTrack() {
                full.reason = "Ton \(MediaLabels.languageName(audio)) fremd, \(full.reason)"
                return full
            }
            if let forced {
                return SubtitlePick(track: forced, reason: audio != nil ? "erzwungen in Tonsprache" : "erzwungen, Tonsprache unbekannt")
            }
            let lang = forcedLanguage.map { MediaLabels.languageName($0) } ?? "Tonsprache"
            return SubtitlePick(track: nil, reason: "Nur erzwungene, keine erzwungene Spur in \(lang)")
        case .always:
            if let full = fullTrack() { return full }
            if let forced { return SubtitlePick(track: forced, reason: "nur erzwungene Spur passt") }
            return SubtitlePick(track: nil, reason: "keine Spur in Wunsch- oder Zweitsprache")
        }
    }

    /// Zweitsprachen: die Sprachen aus dem Tonspur-Vorrang ohne "orig" und ohne die Wunschsprache, in dieser
    /// Reihenfolge; ist die Liste leer, Englisch (außer Englisch ist die Wunschsprache). Sie sind der Ersatz
    /// bei `.always` und zählen (mit der Wunschsprache) als „verstandene“ Sprachen für die Prüfung auf
    /// fremde Tonsprache bei `.forcedOnly`.
    public static func secondaryLanguages(preferred: String?, audioPriority: [String]) -> [String] {
        let wish = MediaLabels.languageCode(preferred)
        var out: [String] = []
        for raw in audioPriority where raw.lowercased() != "orig" {
            if let c = MediaLabels.languageCode(raw), c != wish, !out.contains(c) { out.append(c) }
        }
        if out.isEmpty, wish != "en" { out = ["en"] }
        return out
    }

    static func isForced(_ t: AudioTrackInfo) -> Bool { t.isForced || nameHas(t, ["forced", "erzwungen"]) }
    static func isSDH(_ t: AudioTrackInfo) -> Bool {
        t.isHearingImpaired || nameHas(t, ["sdh", "hearing impaired", "hörgeschädigt", "hoergeschaedigt"])
    }
    static func isCommentary(_ t: AudioTrackInfo) -> Bool { t.isCommentary || nameHas(t, ["commentary", "kommentar"]) }

    private static func code(_ t: AudioTrackInfo) -> String? { MediaLabels.languageCode(t.language) }

    private static func nameHas(_ t: AudioTrackInfo, _ words: [String]) -> Bool {
        guard let n = t.name?.lowercased(), !n.isEmpty else { return false }
        return words.contains { w in
            // Wortgrenzen, damit z. B. "sdh" nicht in einem längeren Wort trifft.
            n.range(of: "(^|[^a-zäöü])\(w)([^a-zäöü]|$)", options: .regularExpression) != nil
        }
    }

    /// Nicht-SDH vor SDH, dann Standard-Flag, dann Dateireihenfolge.
    private static func best(_ candidates: [AudioTrackInfo]) -> AudioTrackInfo? {
        candidates.enumerated().min { a, b in
            let ka = (isSDH(a.element) ? 1 : 0, a.element.isDefault ? 0 : 1, a.offset)
            let kb = (isSDH(b.element) ? 1 : 0, b.element.isDefault ? 0 : 1, b.offset)
            return ka < kb
        }?.element
    }
}
