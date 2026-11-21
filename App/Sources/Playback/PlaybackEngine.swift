import SwiftUI
import Combine
import AetherEngine
import PlayerCore

/// Eigene Player-Schnittstelle (Spec §4): Die App kennt nur dieses Protokoll,
/// damit später ein zweites Backend (AVPlayer) ohne App-Umbau möglich ist.
@MainActor
protocol PlaybackEngine: ObservableObject {
    var isPlaying: Bool { get }
    var isLoading: Bool { get }
    var isEnded: Bool { get }
    var currentTime: Double { get }
    var duration: Double { get }
    var audioTracks: [AudioTrackInfo] { get }
    var activeAudioID: Int? { get }
    var subtitleTracks: [AudioTrackInfo] { get }
    var activeSubtitleID: Int? { get }
    var errorText: String? { get }
    /// Fehler mit Art und Code für die Fehlerleiter (Standard und Aether-Umsetzung in PlaybackFailureMapping.swift).
    var playbackFailure: PlaybackFailure? { get }
    var infoText: String { get }
    var errorDetail: String { get }
    /// Bildbreite der Quelle in Pixeln (für die Auflösungs-Plakette); nil vor dem Laden oder ohne Video.
    var sourceVideoWidth: Int? { get }
    /// Name des Dynamik-Formats der Quelle ("sdr", "hdr10", "hdr10Plus", "dolbyVision", "hlg"); nil = unbekannt.
    var sourceVideoFormatName: String? { get }

    func load(_ url: URL, start: Double?, prefs: LoadPrefs) async throws
    /// Neue Sitzung an der aktuellen Stelle (frisches Fehlerbudget der Engine).
    func recover() async throws
    func play()
    func pause()
    func togglePlayPause()
    var stateText: String { get }
    func seek(_ seconds: Double) async
    func selectAudio(_ id: Int)
    /// Wahl durch den Nutzer (Spur-Panel). Ab dann ändert keine Automatik mehr die Untertitel („Aus bleibt Aus“).
    func selectSubtitle(_ id: Int?)
    /// Automatische Wahl (Start-Auswahl, nachgeladene Addon-Untertitel). Tut nichts und liefert false,
    /// wenn der Nutzer in dieser Wiedergabe schon selbst gewählt hat.
    @discardableResult func autoSelectSubtitle(_ id: Int?) -> Bool
    /// true, sobald der Nutzer in dieser Wiedergabe selbst eine Untertitelspur (oder Aus) gewählt hat.
    var subtitleChosenByUser: Bool { get }
    /// Einstellungen für die automatische Wahl (aus dem Profil, vor dem Laden setzen). nil = keine Automatik.
    var subtitlePreferences: SubtitlePreferences? { get set }
    /// Automatische Wahl neu bewerten über die aktuelle `subtitleTracks` (auch später ergänzte, z. B. Addon).
    /// Tut nichts nach einer Nutzerwahl oder ohne `subtitlePreferences`; schaltet nur, wenn das Ergebnis von
    /// der aktiven Spur abweicht. `audioLanguage` nil = Sprache der aktiven Tonspur. Liefert die Wahl (nil = übersprungen).
    @discardableResult func reconsiderSubtitles(audioLanguage: String?) -> SubtitlePick?
    /// Externe Untertiteldatei als Spur anmelden (`isExternal = true`); liefert die Spur-ID oder nil.
    @discardableResult
    func addExternalSubtitle(url: URL, name: String, language: String?, formatHint: String?) -> Int?
    func stop()
    associatedtype Surface: View
    func surface() -> Surface
    /// Untertitel-Overlay für die aktive Spur (über der Surface, unter der Steuerleiste).
    associatedtype SubtitleLayer: View
    /// controlsInset: 0 = Steuerleiste verborgen, sonst ihre gemessene Höhe; die Untertitel stehen darüber.
    func subtitleLayer(controlsInset: CGFloat) -> SubtitleLayer
}

extension PlaybackEngine {
    /// Für spätere Spuren (Addon-Untertitel): nach dem Hinzufügen aufrufen, nicht `autoSelectSubtitle`.
    @discardableResult func reconsiderSubtitles() -> SubtitlePick? { reconsiderSubtitles(audioLanguage: nil) }
}

extension PlaybackEngine {
    /// Backends ohne externe Untertitel melden nichts an.
    @discardableResult
    func addExternalSubtitle(url: URL, name: String, language: String?, formatHint: String?) -> Int? { nil }
}

/// Wünsche für das Laden, unabhängig vom Backend.
struct LoadPrefs {
    var audioLanguages: [String] = []
    var subtitleLanguages: [String] = []
    var headers: [String: String] = [:]
    /// Entferntes HLS direkt an AVPlayer (Trailer).
    var nativeRemoteHLS = false
}

/// AetherEngine-Backend.
@MainActor
final class AetherBackend: PlaybackEngine {
    let engine: AetherEngine
    private var bag: AnyCancellable?

    init() throws {
        engine = try AetherEngine()
        bag = engine.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        // Kein Untertitel-Versatz in der App: ohne Vorlauf-Reichweite liest die Engine eine Fernquelle
        // nicht ein zweites Mal für Cues voraus (AetherEngine-Doku „Cue retention“, AE#1015).
        engine.maximumSubtitleOffsetSeconds = 0
        Self.installEngineLog()
    }

    /// Engine-Meldungen (Muxer-Neustarts, Ton-Bridge, Sitzung) ins Fern-Log.
    private static var logInstalled = false
    private static func installEngineLog() {
        guard !logInstalled else { return }
        logInstalled = true
        EngineLog.structuredHandler = { line, cat, _ in
            // Nur Wichtiges: Lebenszyklus, Ton-Bridge, Muxer; aus Sitzung/Demux nur Fehler und Neustarts.
            let l = line.lowercased()
            let important = ["fail", "error", "revive", "restart", "cannot", "unrecoverable", "budget", "timeout"].contains { l.contains($0) }
            let noisy = ["accesslog", "audioroute", "memprobe", "cpuprobe", "ledger", "march-rate"].contains { l.contains($0) }
            // Dolby Vision Profil 7 (Umwandlung nach 8.1, FEL-Meldung, FEL-Kurven/-Quelle) immer durchlassen,
            // egal aus welcher Kategorie (Vergleich auf der kleingeschriebenen Zeile `l`).
            let dolbyVision = ["dv p7", "[felcurves]", "fel source"].contains { l.contains($0) }
            if !dolbyVision {
                switch cat {
                case .audioBridge, .muxer: break
                case .engine: if noisy && !important { return }
                case .session, .demux: if !important || l.contains("restarted=false") { return }
                default: return
                }
            }
            Task { @MainActor in RemoteLog.info("engine.\(cat.rawValue)", LogRedact.text(line)) }
        }
    }

    var isPlaying: Bool { engine.state == .playing }
    var isLoading: Bool { engine.state == .loading || engine.state == .seeking }
    var isEnded: Bool { engine.state == .ended }
    var currentTime: Double { engine.clock.currentTime }
    var duration: Double { engine.duration }
    var audioTracks: [AudioTrackInfo] {
        engine.audioTracks.map {
            AudioTrackInfo(id: $0.id, language: $0.language, name: $0.name, channels: $0.channels, codec: $0.codec,
                           isDefault: $0.isDefault, isCommentary: $0.isCommentary, isVisualImpaired: $0.isVisualImpaired,
                           profile: $0.profile, isAtmos: $0.isAtmos || $0.trueHDAtmos == .atmos, isDTSX: $0.isDTSX,
                           channelLayout: $0.channelLayout)
        }
    }
    var activeAudioID: Int? { engine.activeAudioTrackIndex }
    var subtitleTracks: [AudioTrackInfo] {
        engine.subtitleTracks.map {
            AudioTrackInfo(id: $0.id, language: $0.language, name: $0.name, codec: $0.codec,
                           isDefault: $0.isDefault, isForced: $0.isForced, isHearingImpaired: $0.isHearingImpaired,
                           isCommentary: $0.isCommentary, isExternal: $0.isExternal,
                           isImage: MediaLabels.isImageSubtitleCodec($0.codec),
                           isNativelyRendered: $0.isNativelyRenderedSubtitle)
        }
    }
    var activeSubtitleID: Int? { engine.activeSubtitleTrackIndex }
    var errorText: String? {
        if case .error(let s) = engine.state { return s }
        return engine.errorInfo.map { "\($0.kind)" }
    }
    var infoText: String {
        let dv = engine.sourceDVProfile.map { "DV P\($0)" } ?? "\(engine.sourceVideoFormat)"
        return "\(engine.sourceVideoCodecName ?? "?") · \(dv) → \(engine.videoFormat) · Ton \(engine.activeAudioDecoder ?? "-") (\(engine.audioDelivery))"
    }
    var sourceVideoWidth: Int? { engine.sourceVideoWidth > 0 ? Int(engine.sourceVideoWidth) : nil }
    /// Quellformat (nicht das auf das Panel geklemmte `videoFormat`): Plakette zeigt, was die Datei ist.
    var sourceVideoFormatName: String? { "\(engine.sourceVideoFormat)" }

    var errorDetail: String { engine.errorInfo.map { String(describing: $0) } ?? "-" }

    func load(_ url: URL, start: Double?, prefs: LoadPrefs) async throws {
        var o = LoadOptions()
        o.preferredAudioLanguages = prefs.audioLanguages
        o.preferredSubtitleLanguages = prefs.subtitleLanguages
        o.httpHeaders = prefs.headers
        o.nativeRemoteHLS = prefs.nativeRemoteHLS
        // Schnellerer Start bei Fernquellen (Werte wie NuvioTVOS): 8 MiB / 5 s statt 50 MB / 60 s.
        o.probesize = 8 * 1024 * 1024
        o.maxAnalyzeDuration = 5_000_000
        o.skipsContainerAttachments = true
        _ = try await engine.load(url: url, startPosition: start, options: o)
    }
    func recover() async throws { try await engine.reloadAtCurrentPosition() }
    func play() { engine.play() }
    func pause() { engine.pause() }
    /// Engine liest den echten AVPlayer-Zustand (der veröffentlichte `state` kann hinterherhinken).
    func togglePlayPause() { engine.togglePlayPause() }
    var stateText: String { "\(engine.state)" }
    func seek(_ seconds: Double) async { await engine.seek(to: max(0, seconds)) }
    func selectAudio(_ id: Int) { engine.selectAudioTrack(index: id) }
    private(set) var subtitleChosenByUser = false
    func selectSubtitle(_ id: Int?) {
        subtitleChosenByUser = true
        applySubtitle(id)
    }
    @discardableResult func autoSelectSubtitle(_ id: Int?) -> Bool {
        guard !subtitleChosenByUser else { return false }
        applySubtitle(id)
        return true
    }
    var subtitlePreferences: SubtitlePreferences?
    @discardableResult func reconsiderSubtitles(audioLanguage: String?) -> SubtitlePick? {
        guard let prefs = subtitlePreferences else { return nil }
        let lang = audioLanguage ?? audioTracks.first(where: { $0.id == activeAudioID })?.language
        let pick = SubtitlePicker.pick(subtitleTracks, preferences: prefs, audioLanguage: lang)
        guard !subtitleChosenByUser else {
            RemoteLog.info("player", "UT: Nutzerwahl bleibt (\(pick.logText))")
            return nil
        }
        if pick.track?.id != activeSubtitleID { applySubtitle(pick.track?.id) }
        RemoteLog.info("player", pick.logText)
        return pick
    }
    private func applySubtitle(_ id: Int?) {
        if let id { engine.selectSubtitleTrack(index: id) } else { engine.clearSubtitle() }
    }
    func stop() { engine.stop() }
    func surface() -> some View { AetherPlayerSurface(engine: engine) }
    /// AetherEngine #88: Spur erscheint in `subtitleTracks` (synthetische ID, `isExternal`), wählbar über `selectSubtitle`.
    /// `httpHeaders` nil: Kopfzeilen der Quelle gehen nur an denselben Ursprung.
    @discardableResult
    func addExternalSubtitle(url: URL, name: String, language: String?, formatHint: String?) -> Int? {
        engine.addExternalSubtitleTrack(ExternalSubtitleTrack(url: url, name: name, language: language, formatHint: formatHint)).id
    }
}
