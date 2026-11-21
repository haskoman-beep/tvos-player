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
    var infoText: String { get }
    var errorDetail: String { get }

    func load(_ url: URL, start: Double?, prefs: LoadPrefs) async throws
    /// Neue Sitzung an der aktuellen Stelle (frisches Fehlerbudget der Engine).
    func recover() async throws
    func play()
    func pause()
    func togglePlayPause()
    var stateText: String { get }
    func seek(_ seconds: Double) async
    func selectAudio(_ id: Int)
    func selectSubtitle(_ id: Int?)
    func stop()
    associatedtype Surface: View
    func surface() -> Surface
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
            switch cat {
            case .audioBridge, .muxer: break
            case .engine: if noisy && !important { return }
            case .session, .demux: if !important || l.contains("restarted=false") { return }
            default: return
            }
            Task { @MainActor in RemoteLog.info("engine.\(cat.rawValue)", line) }
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
                           isImage: MediaLabels.isImageSubtitleCodec($0.codec))
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
    func selectSubtitle(_ id: Int?) {
        if let id { engine.selectSubtitleTrack(index: id) } else { engine.clearSubtitle() }
    }
    func stop() { engine.stop() }
    func surface() -> some View { AetherPlayerSurface(engine: engine) }
}
