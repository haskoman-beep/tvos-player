import Foundation

/// Fehler der Wiedergabe, wie die Engine ihn meldet, ohne Engine-Typen (testbar).
/// `kind` ist der stabile Rohwert der Fehlerart (AetherEngine `PlaybackErrorKind.rawValue`), nie der Meldungstext.
public struct PlaybackFailure: Equatable, Sendable {
    public var kind: String?
    /// `NSError.domain` des Fehlers darunter (z. B. "NSURLErrorDomain"), nil = von der Engine selbst.
    public var domain: String?
    /// `NSError.code` darunter, bei `sourceRefused`/`sourceRateLimited` der HTTP-Status.
    public var code: Int?
    /// Negativer FFmpeg-Fehlercode, falls vorhanden.
    public var ffmpegCode: Int?
    /// URL-Fehlercode tiefer in der Kette (z. B. unter AVFoundation −11800), falls das Backend ihn kennt.
    public var underlyingURLCode: Int?
    public var message: String

    public init(kind: String? = nil, domain: String? = nil, code: Int? = nil, ffmpegCode: Int? = nil,
                underlyingURLCode: Int? = nil, message: String = "") {
        self.kind = kind; self.domain = domain; self.code = code; self.ffmpegCode = ffmpegCode
        self.underlyingURLCode = underlyingURLCode; self.message = message
    }

    /// Kurz fürs Log (ohne Meldungstext, der Links enthalten kann).
    public var logText: String {
        "\(kind ?? "ohne Art")" + (domain.map { " · \($0)" } ?? "") + (code.map { " · \($0)" } ?? "")
            + (ffmpegCode.map { " · ffmpeg \($0)" } ?? "")
    }
}

/// Einordnung eines Wiedergabefehlers. Entscheidet über die Strategie in `RecoveryPlanner`.
public enum PlaybackErrorClass: String, Sendable, CaseIterable {
    /// Netz kurz weg oder kein Netz (Verbindung verloren, offline).
    case network
    /// Server der Quelle nicht erreichbar (Name unbekannt, Verbindung abgelehnt).
    case hostUnreachable
    /// Zeitüberschreitung (Anfrage oder Start ohne abspielbare Spur).
    case timeout
    /// Link abgelaufen oder entfernt (HTTP 403/404/410).
    case linkExpired
    /// Debrid-/Resolver-Fehler (HTTP 401/402/451/5xx).
    case debrid
    /// Dienst drosselt (HTTP 429/503/509): andere Quelle trifft dasselbe Limit.
    case rateLimited
    /// Format oder Datei lässt sich hier nicht abspielen.
    case unsupported
    /// Zertifikat der Quelle abgelehnt.
    case certificate
    /// Speicher des Geräts voll.
    case storage
    /// Sonst (Quelle abgerissen, Dekoder): einmal neu laden, dann nächste Quelle (bisheriges Verhalten).
    case unknown

    /// Deutsche Kurzbezeichnung für Hinweise.
    public var label: String {
        switch self {
        case .network: "Netzwerk unterbrochen"
        case .hostUnreachable: "Server nicht erreichbar"
        case .timeout: "Zeitüberschreitung"
        case .linkExpired: "Link abgelaufen"
        case .debrid: "Debrid-Fehler"
        case .rateLimited: "Dienst drosselt gerade"
        case .unsupported: "Format nicht abspielbar"
        case .certificate: "Zertifikat abgelehnt"
        case .storage: "Speicher voll"
        case .unknown: "Wiedergabefehler"
        }
    }
}

/// Was nach einem Fehler geschieht.
public enum RecoveryStep: Equatable, Sendable {
    /// Gleiche Quelle an der Stelle neu laden, nach `delay` Sekunden.
    case retrySame(delay: Double)
    /// Link derselben Quelle neu auflösen (frische Addon-Antwort), dann an der Stelle laden.
    case reresolve
    /// Nächste Quelle (bestehender Fallback der Quellenliste).
    case nextSource
    /// Aufhören und eine klare Meldung zeigen (mit „Andere Quelle wählen“).
    case giveUp(message: String)
}

public enum PlaybackErrorClassifier {
    /// Fehlerarten, bei denen dieselbe Datei hier nie spielt.
    static let unsupportedKinds: Set<String> = [
        "hlsFormatUnsupported", "dolbyVisionRequiresHardware", "demuxedAudioLiveUnsupported",
        "masterPlaylistRejected", "audioBridgeProducedNoOutput", "sourceFabricatesRanges",
        "hlsPlaylistOnRawLivePath", "customSourceProbeFailed",
    ]
    static let timeoutKinds: Set<String> = ["noPlayableTrackWithinBudget", "liveReloadNeverReady"]
    /// FFmpeg AVERROR_INVALIDDATA („Invalid data found when processing input“).
    static let ffmpegInvalidData = -1_094_995_529

    /// Nach Art, HTTP-Status und URL-Fehlercode einordnen, nie nach dem Meldungstext.
    public static func classify(_ f: PlaybackFailure) -> PlaybackErrorClass {
        let kind = f.kind ?? ""
        switch kind {
        case "sourceRateLimited": return .rateLimited
        case "sourceCertificateRejected": return .certificate
        case "storageExhausted": return .storage
        case "sourceRefused": return httpClass(f.code)
        default: break
        }
        if unsupportedKinds.contains(kind) { return .unsupported }
        if timeoutKinds.contains(kind) { return .timeout }
        if f.domain == "NSURLErrorDomain", let c = f.code, let cls = urlClass(c) { return cls }
        // AVPlayer-Weg: CoreMedia meldet HTTP-Fehler als eigene Codes (−12660 = 403, −12938 = 404).
        if f.domain == "CoreMediaErrorDomain", f.code == -12660 || f.code == -12938 { return .linkExpired }
        // AVFoundation −11800 („unbekannt“): der URL-Fehler darunter entscheidet.
        if f.domain == "AVFoundationErrorDomain", f.code == -11800, let u = f.underlyingURLCode, let cls = urlClass(u) { return cls }
        if kind == "sourceOpenFailed", f.ffmpegCode == ffmpegInvalidData {
            return .unsupported
        }
        return .unknown
    }

    static func httpClass(_ status: Int?) -> PlaybackErrorClass {
        switch status ?? 0 {
        case 403, 404, 410: .linkExpired
        case 429, 503, 509: .rateLimited
        case 401, 402, 451, 500...599: .debrid
        default: .unknown
        }
    }

    /// NSURLError-Codes (Foundation).
    static func urlClass(_ code: Int) -> PlaybackErrorClass? {
        switch code {
        case -1001: .timeout                                     // timedOut
        case -1005, -1009, -1018, -1020: .network                // connectionLost, notConnected, roaming, dataNotAllowed
        case -1003, -1004, -1006: .hostUnreachable               // cannotFindHost, cannotConnect, dnsLookupFailed
        case -1206 ... -1200: .certificate                       // secureConnectionFailed … clientCertificateRequired
        default: nil
        }
    }
}

/// Fehlerleiter je Wiedergabe: je Fehlerklasse eine Strategie, begrenzte Versuche, kein Endlos-Kreisen.
/// Nach `healthySeconds` echt gespielten Sekunden seit dem letzten Versuch beginnt die Leiter neu. Gezählt wird
/// Spielzeit (ein Takt je Sekunde), nicht der Positionsabstand: Sprünge und Fortsetzen an `start` zählen nicht.
public struct RecoveryPlanner: Sendable {
    /// Höchstens so viele Neuversuche (gleiche Quelle oder neu aufgelöst) je Leiter, über alle Klassen.
    public var maxAttempts = 4
    public var healthySeconds: Double = 120
    public private(set) var attempts: [PlaybackErrorClass: Int] = [:]
    public private(set) var total = 0
    /// Fehlerfrei gespielte Sekunden seit dem letzten Versuch.
    public private(set) var playedSinceAttempt: Double = 0
    /// true = Link-Neuauflösen ist möglich (Addon-Quelle, kein Trailer).
    public var canReresolve: Bool

    public init(canReresolve: Bool = true) { self.canReresolve = canReresolve }

    /// Nächster Schritt für diesen Fehler.
    public mutating func next(for failure: PlaybackFailure) -> (PlaybackErrorClass, RecoveryStep) {
        let cls = PlaybackErrorClassifier.classify(failure)
        let n = attempts[cls, default: 0]
        var step = Self.ladder(cls, attempt: n, canReresolve: canReresolve)
        switch step {
        case .retrySame, .reresolve:
            if total >= maxAttempts {
                // Budget aufgebraucht: wo die Klasse sonst weiterschaltet, nächste Quelle; Netz → Meldung.
                step = cls == .network ? .giveUp(message: Self.message(cls)) : .nextSource
            } else {
                attempts[cls] = n + 1; total += 1; playedSinceAttempt = 0
            }
        case .nextSource, .giveUp: break
        }
        return (cls, step)
    }

    /// Ein Takt laufender, fehlerfreier Wiedergabe (`seconds` = Taktlänge): nach genug Spielzeit neu beginnen.
    public mutating func notePlaying(seconds: Double = 1) {
        guard total > 0 else { return }
        playedSinceAttempt += seconds
        if playedSinceAttempt >= healthySeconds { reset() }
    }

    /// Neuer Anlauf (Nutzer drückt „Erneut versuchen“ oder Play/Pause).
    public mutating func reset() { attempts = [:]; total = 0; playedSinceAttempt = 0 }

    /// Strategie je Klasse und Versuch (0 = erster Fehler dieser Klasse).
    public static func ladder(_ cls: PlaybackErrorClass, attempt n: Int, canReresolve: Bool) -> RecoveryStep {
        switch cls {
        case .network:
            // Netz kommt meist zurück: steigende Wartezeit; die nächste Quelle hätte dasselbe Netz.
            let delays: [Double] = [2, 5, 10]
            return n < delays.count ? .retrySame(delay: delays[n]) : .giveUp(message: message(cls))
        case .hostUnreachable, .timeout:
            return n < 1 ? .retrySame(delay: 2) : .nextSource
        case .linkExpired, .debrid:
            if n < 1 { return canReresolve ? .reresolve : (cls == .debrid ? .retrySame(delay: 2) : .nextSource) }
            return .nextSource
        case .unsupported:
            return .nextSource
        case .rateLimited, .certificate, .storage:
            return .giveUp(message: message(cls))
        case .unknown:
            return n < 1 ? .retrySame(delay: 0) : .nextSource
        }
    }

    /// Klare deutsche Meldung für `giveUp`.
    public static func message(_ cls: PlaybackErrorClass) -> String {
        switch cls {
        case .network: "Die Verbindung ist unterbrochen. Bitte das Netzwerk prüfen und erneut versuchen."
        case .rateLimited: "Der Dienst bremst gerade (zu viele Anfragen). Bitte kurz warten oder eine andere Quelle wählen."
        case .certificate: "Das Zertifikat der Quelle wird abgelehnt. Bitte eine andere Quelle wählen."
        case .storage: "Der Speicher des Apple TV ist voll. Bitte Speicher freigeben oder eine andere Quelle wählen."
        default: "\(cls.label). Bitte eine andere Quelle wählen."
        }
    }
}

extension LastSource {
    /// Link neu auflösen: genau dieselbe Datei (Dateiname bzw. Beschreibung) in einer frischen Addon-Antwort,
    /// bei mehreren Treffern die mit gleichem Namen (Dienst/Auflösung). Kein Ausweichen auf ähnliche Quellen
    /// (bingeGroup, Auflösung): das macht der normale Fallback. Leerer Fingerabdruck: nie ein Treffer.
    public func exactStream(in streams: [StreamItem]) -> StreamItem? {
        guard !fingerprint.isEmpty else { return nil }
        let hits = playableStreams(streams).filter { ($0.behaviorHints?.filename ?? $0.label) == fingerprint }
        return hits.first { $0.name == name } ?? hits.first
    }

    public func exactURL(in streams: [StreamItem]) -> URL? {
        exactStream(in: streams)?.url.flatMap(URL.init(string:))
    }
}
