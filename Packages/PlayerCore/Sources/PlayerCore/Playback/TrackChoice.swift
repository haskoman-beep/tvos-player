import Foundation

/// Welle F-h: Spur-Panel im Player öffnen (Siri Remote) und die Spurwahl beschriften.
///
/// Ursache des Fehlers „keine Sprache für Ton und Untertitel wählbar“: das Panel ging nur über `onMoveCommand(.down)`
/// auf. tvOS meldet dort nur den Klick auf den unteren Rand der Touchfläche, kein Wischen. Ein Wisch nach unten
/// (tvOS-Konvention) kam nur beim Pan-Recognizer der Spul-Steuerung an, der senkrechte Wischer verwarf.
public enum TrackPanelEntry {
    /// Warum ein Öffnen-Wunsch nichts tut (für das Log).
    public enum IgnoreReason: Equatable, Sendable {
        case leaving, alreadyOpen, failure, scrubbing, skipPrompt
        case busy(TrackLock)

        public var logText: String {
            switch self {
            case .leaving: "Ausgang läuft"
            case .alreadyOpen: "Panel schon offen"
            case .failure: "Fehlerkarte steht"
            case .scrubbing: "Spulen läuft"
            case .skipPrompt: "Überspringen-Knopf hat den Fokus"
            case .busy(let l): l.logText
            }
        }
    }

    /// Was ein Öffnen-Wunsch (Wisch nach unten oder ▼-Klick) bewirkt.
    public enum Step: Equatable, Sendable {
        /// Panel öffnen.
        case open
        /// Erst die Up-next-Karte abbrechen (wie jede Richtungstaste), Panel bleibt zu.
        case cancelUpNext
        /// Nichts tun; der Grund geht ins Log.
        case ignore(IgnoreReason)
    }

    /// `lock`: laufender Neuaufbau/Start (`TrackLock.current`); dann öffnet das Panel nicht.
    /// Steht der Überspringen-Knopf, behält er den Fokus (Wisch und ▼ öffnen nicht).
    public static func decide(leaving: Bool, scrubbing: Bool, upNextShowing: Bool, failureShowing: Bool,
                              alreadyOpen: Bool, skipPromptShowing: Bool, lock: TrackLock?) -> Step {
        if leaving { return .ignore(.leaving) }
        if alreadyOpen { return .ignore(.alreadyOpen) }
        if failureShowing { return .ignore(.failure) }
        if scrubbing { return .ignore(.scrubbing) }
        if upNextShowing { return .cancelUpNext }
        if skipPromptShowing { return .ignore(.skipPrompt) }
        if let lock { return .ignore(.busy(lock)) }
        return .open
    }

    /// Mindestweg (Punkte der Touchfläche) für einen Wisch nach unten; ein schneller kurzer Wisch reicht auch.
    public static let swipeMinDistance: Double = 140
    public static let swipeFastDistance: Double = 60
    public static let swipeFastVelocity: Double = 700

    /// Ende einer Wischbewegung: war es ein Wisch nach unten? (UIKit-Achsen: y wächst nach unten.)
    /// Deutlich senkrecht (|dy| > 1,5 · |dx|), dann weit genug oder kurz und schnell.
    public static func isSwipeDown(translationX: Double, translationY: Double, velocityY: Double) -> Bool {
        guard translationX.isFinite, translationY.isFinite, velocityY.isFinite else { return false }
        guard translationY > 0, translationY > abs(translationX) * 1.5 else { return false }
        if translationY >= swipeMinDistance { return true }
        return translationY >= swipeFastDistance && velocityY >= swipeFastVelocity
    }

    /// Welle F-h2: Wisch nach oben (schließt das Panel aus der obersten Zeile). Spiegel von `isSwipeDown`.
    public static func isSwipeUp(translationX: Double, translationY: Double, velocityY: Double) -> Bool {
        isSwipeDown(translationX: translationX, translationY: -translationY, velocityY: -velocityY)
    }
}

/// Welle F-h R1: Spurwahl gesperrt, solange die Sitzung neu aufgebaut wird oder der Start läuft. Sonst würde die
/// Fehlerleiter eine Untertitelwahl danach still zurückdrehen und ein Ton-Neuladen liefe parallel zu ihrem.
/// (`restorePending` nach dem Hintergrund sperrt nur den Ton, „gesperrt bis Play“, und steht nicht hier.)
public enum TrackLock: Equatable, Sendable {
    /// Neuaufbau nach dem Hintergrund läuft.
    case restoring
    /// Fehlerleiter lädt neu (Wartezeit, frischer Link, reloadAtCurrentPosition).
    case recovering
    /// Start (`engine.load`) läuft.
    case loading
    /// Wiederholter Start ist angesetzt, aber noch nicht begonnen.
    case startPending
    /// Fehlerleiter wartet auf das Netz.
    case waitingForNetwork
    /// Engine meldet einen Fehler, die Leiter hat noch nicht entschieden.
    case engineError

    /// Reihenfolge: was gerade läuft, vor dem, was nur angesetzt ist.
    public static func current(restoring: Bool, recovering: Bool, loadInFlight: Bool, startPending: Bool,
                               waitingForNetwork: Bool, engineError: Bool) -> TrackLock? {
        if restoring { return .restoring }
        if recovering { return .recovering }
        if loadInFlight { return .loading }
        if startPending { return .startPending }
        if waitingForNetwork { return .waitingForNetwork }
        if engineError { return .engineError }
        return nil
    }

    /// Hinweis für den Nutzer.
    public var text: String {
        self == .waitingForNetwork ? "Gerade nicht möglich – warte auf das Netz" : "Gerade nicht möglich – Quelle wird geladen"
    }

    public var logText: String {
        switch self {
        case .restoring: "Neuaufbau nach Hintergrund"
        case .recovering: "Fehlerleiter lädt neu"
        case .loading: "Start lädt"
        case .startPending: "Start angesetzt"
        case .waitingForNetwork: "warte auf Netz"
        case .engineError: "Engine-Fehler offen"
        }
    }
}

/// Kurze deutsche Namen der Spurwahl: „Deutsch 5.1 (E-AC-3)“, „Englisch“, „Aus“.
public enum TrackChoice {
    /// Kurzname des Tonformats für die Klammer: „E-AC-3“, „TrueHD Atmos“, „DTS-HD MA“.
    public static func codecShort(_ t: AudioTrackInfo) -> String? {
        guard let c = t.codec?.trimmingCharacters(in: .whitespaces).lowercased(), !c.isEmpty else { return nil }
        let p = t.profile?.uppercased() ?? ""
        let atmos = t.isAtmos ? " Atmos" : ""
        switch c {
        case "eac3": return "E-AC-3" + atmos
        case "ac3": return "AC-3"
        case "truehd", "mlp": return "TrueHD" + (t.isAtmos || p.contains("ATMOS") ? " Atmos" : "")
        case "dts", "dca":
            if t.isDTSX || p.contains("DTS:X") { return "DTS:X" }
            if p.contains("MA") { return "DTS-HD MA" }
            return "DTS"
        case "aac": return "AAC"
        case "flac": return "FLAC"
        case "opus": return "Opus"
        case "mp3": return "MP3"
        default: return c.hasPrefix("pcm") ? "PCM" : c.uppercased()
        }
    }

    /// Tonspur: Sprache, Kanäle, Format in Klammern („Deutsch 5.1 (E-AC-3)“, „Englisch Stereo (AAC)“).
    /// Ohne Sprache: Spurname, sonst „Spur n“. nil → „–“.
    public static func audioLabel(_ t: AudioTrackInfo?) -> String {
        guard let t else { return "–" }
        var parts = [baseName(t)]
        if let ch = MediaLabels.channels(t.channels, layout: t.channelLayout) { parts.append(ch) }
        if let c = codecShort(t) { parts.append("(\(c))") }
        if t.isCommentary { parts.append("· Kommentar") } else if t.isVisualImpaired { parts.append("· Hörfilm") }
        return parts.joined(separator: " ")
    }

    /// Untertitel: Sprache mit Art („Englisch“, „Englisch (erzwungen)“, „Deutsch (SDH)“); nil → „Aus“.
    public static func subtitleLabel(_ t: AudioTrackInfo?) -> String {
        guard let t else { return "Aus" }
        var kinds: [String] = []
        if t.isForced { kinds.append("erzwungen") }
        if t.isHearingImpaired { kinds.append("SDH") }
        if t.isCommentary { kinds.append("Kommentar") }
        if t.isExternal { kinds.append("extern") }
        let base = baseName(t)
        return kinds.isEmpty ? base : "\(base) (\(kinds.joined(separator: ", ")))"
    }

    /// Zeile für Log und Steuerleiste: „Ton Deutsch 5.1 (E-AC-3) / UT Aus“.
    public static func summary(audio: AudioTrackInfo?, subtitle: AudioTrackInfo?) -> String {
        "Ton \(audioLabel(audio)) / UT \(subtitleLabel(subtitle))"
    }

    /// Zeile der Steuerleiste: „Ton Deutsch 5.1 (E-AC-3) · Untertitel Aus · nach unten wischen: ändern“.
    public static func overlayLine(audio: AudioTrackInfo?, subtitle: AudioTrackInfo?) -> String {
        "Ton \(audioLabel(audio)) · Untertitel \(subtitleLabel(subtitle)) · nach unten wischen: ändern"
    }

    /// Aktive Spuren aus den Listen der Engine (IDs, die fehlen, zählen als keine Spur).
    public static func active(_ tracks: [AudioTrackInfo], id: Int?) -> AudioTrackInfo? {
        guard let id else { return nil }
        return tracks.first { $0.id == id }
    }

    /// Was eine Tonwahl im Panel auslöst.
    public enum AudioAction: Equatable, Sendable {
        /// Engine umschalten (sitzungserhaltendes Neuladen an derselben Stelle) und merken.
        case apply
        /// Spur läuft schon: nichts neu laden, nur merken.
        case keep
        /// Nach dem Hintergrund gesperrt, bis Play neu aufgebaut hat: nichts tun.
        case locked
    }

    public static func audioAction(selected: Int, active: Int?, locked: Bool) -> AudioAction {
        if locked { return .locked }
        return selected == active ? .keep : .apply
    }

    private static func baseName(_ t: AudioTrackInfo) -> String {
        let lang = MediaLabels.languageName(t.language)
        if lang != "Unbekannt" { return lang }
        if !MediaLabels.isGenericTrackName(t.name, language: t.language, codec: t.codec),
           let n = t.name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { return n }
        return "Spur \(t.id + 1)"
    }
}
