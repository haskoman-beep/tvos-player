import Foundation

/// Now-Playing-Karte (Welle G-b): was Kontrollzentrum, iPhone-Fernbedienung und die Apple-TV-Übersicht zeigen.
/// Serie: Titel = Serienname, Zeile darunter = Folge („S1 E3 · Name“). Film: Titel, darunter das Jahr.
public struct NowPlayingCard: Equatable, Sendable {
    public var title: String
    public var subtitle: String?
    /// Bild für die Karte: Poster, sonst Hintergrundbild (nil = keins).
    public var artworkURL: URL?

    public init(title: String, subtitle: String? = nil, artworkURL: URL? = nil) {
        self.title = title; self.subtitle = subtitle; self.artworkURL = artworkURL
    }

    /// `episodeLine` gesetzt = Folge einer Serie (`title` ist dann der Serienname).
    public static func make(title: String, episodeLine: String?, year: String?, poster: String?, background: String?) -> NowPlayingCard {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let sub = (episodeLine ?? year)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return NowPlayingCard(title: cleanTitle.isEmpty ? "Player" : cleanTitle,
                              subtitle: sub?.isEmpty == false ? sub : nil,
                              artworkURL: artworkURL(poster: poster, background: background))
    }

    /// Nur http(s)-Adressen; Poster vor Hintergrund (die Karte ist eher hoch als breit).
    public static func artworkURL(poster: String?, background: String?) -> URL? {
        for s in [poster, background] {
            guard let s, let u = URL(string: s), let scheme = u.scheme?.lowercased(),
                  scheme == "https" || scheme == "http", u.host != nil else { continue }
            return u
        }
        return nil
    }

    /// Für das Fern-Log (ohne Bildadresse).
    public var logText: String {
        "„\(title)“\(subtitle.map { " · \($0)" } ?? "")\(artworkURL == nil ? " · ohne Bild" : " · mit Bild")"
    }
}

/// Systembefehl (Kontrollzentrum, iPhone-Fernbedienung), unabhängig von der Engine.
public enum RemoteTransportCommand: Equatable, Sendable {
    case play
    case pause
    case togglePlayPause
    /// Vorzeichen: negativ = zurück.
    case skip(seconds: Double)
    case changePosition(to: Double)
    case nextTrack
    case previousTrack

    public var logName: String {
        switch self {
        case .play: "Play"
        case .pause: "Pause"
        case .togglePlayPause: "Play/Pause"
        case .skip(let s): s.isFinite ? "\(s < 0 ? "−" : "+")\(Int(abs(s).rounded())) s" : "Sprung ?"
        case .changePosition(let t): "Position \(Int(t.isFinite ? t : 0)) s"
        case .nextTrack: "Nächster Titel"
        case .previousTrack: "Voriger Titel"
        }
    }
}

/// Zustand des Players, wenn ein Systembefehl kommt.
public struct RemoteTransportContext: Equatable, Sendable {
    public var isPlaying: Bool
    /// Engine lädt oder springt (`.loading`/`.seeking`): gilt als Absicht „spielt“ (Play pausiert dann nie).
    public var isBusy: Bool
    /// Ausgangspunkt für Sprünge: gesammeltes Sprungziel, sonst aktuelle Stelle.
    public var position: Double
    /// Ausgang, Spulen über die Touchfläche, Spur-Panel oder Fehlerkarte: Systembefehle zählen nicht.
    public var inputBlocked: Bool
    /// Up-next-Karte steht: Play/Pause startet wie der Klick die nächste Folge, Pause allein wird ignoriert.
    public var upNextShowing: Bool
    /// Sekunden seit dem letzten Play/Pause-Druck der Siri-Remote (auch dem, der nur das Spulen bestätigt hat).
    public var sinceLastPress: Double

    public init(isPlaying: Bool, isBusy: Bool = false, position: Double, inputBlocked: Bool = false,
                upNextShowing: Bool = false, sinceLastPress: Double = .infinity) {
        self.isPlaying = isPlaying; self.isBusy = isBusy; self.position = position
        self.inputBlocked = inputBlocked; self.upNextShowing = upNextShowing; self.sinceLastPress = sinceLastPress
    }

    /// Absicht der Engine: spielt, lädt oder springt.
    public var wantsPlaying: Bool { isPlaying || isBusy }
}

/// Was der Player mit einem Systembefehl tut. Es gibt keinen eigenen Weg: `.toggle` geht über dieselbe
/// Play/Pause-Funktion wie die Siri-Remote (350-ms-Doppelfilter, Neuaufbau nach dem Hintergrund, Fehlerleiter),
/// `.seek` über die ±10-s-Sammlung (450 ms, Sperre beim Neuaufbau, Endgrenze).
public enum RemoteTransportAction: Equatable, Sendable {
    case toggle
    case seek(by: Double)
    case ignore(String)

    public var logText: String {
        switch self {
        case .toggle: "Play/Pause"
        case .seek(let d): "Sprung \(d < 0 ? "" : "+")\(Int(d.rounded())) s"
        case .ignore(let why): "ignoriert (\(why))"
        }
    }
}

public enum RemoteTransport {
    /// Wählbare Sprungweite der Systembefehle (iPhone-Fernbedienung, Kontrollzentrum) in Sekunden.
    public static let skipChoices = [10, 30]
    public static let defaultSkipSeconds = 10
    /// Play/Pause so kurz nach einem Druck der Siri-Remote ist derselbe Druck (wie `togglePlay`, 350 ms).
    public static let doublePressWindow = 0.35
    /// Kleinere Positionswechsel gelten als „bleibt stehen“.
    public static let minPositionChange = 0.5

    /// Gespeicherter Wert → Sprungweite; unbekannte Werte fallen auf den Standard.
    public static func skipInterval(_ seconds: Int) -> Double {
        Double(skipChoices.contains(seconds) ? seconds : defaultSkipSeconds)
    }

    public static func choiceLabel(_ seconds: Int) -> String { "\(seconds) Sekunden" }

    public static func action(for command: RemoteTransportCommand, context c: RemoteTransportContext) -> RemoteTransportAction {
        if c.inputBlocked { return .ignore("gesperrt") }
        switch command {
        case .play, .pause, .togglePlayPause:
            if c.sinceLastPress < doublePressWindow { return .ignore("doppelt zum Tastendruck") }
        default: break
        }
        switch command {
        case .play:
            return c.wantsPlaying ? .ignore("spielt schon") : .toggle
        case .pause:
            if c.upNextShowing { return .ignore("Up-next läuft") }
            return c.wantsPlaying ? .toggle : .ignore("schon pausiert")
        case .togglePlayPause:
            return .toggle
        case .skip(let s):
            guard s.isFinite, s != 0 else { return .ignore("ungültige Sprungweite") }
            return .seek(by: s)
        case .changePosition(let t):
            guard t.isFinite, t >= 0, c.position.isFinite else { return .ignore("ungültige Position") }
            let delta = t - c.position
            return abs(delta) < minPositionChange ? .ignore("gleiche Stelle") : .seek(by: delta)
        case .nextTrack, .previousTrack:
            return .ignore("keine Titelliste")
        }
    }
}
