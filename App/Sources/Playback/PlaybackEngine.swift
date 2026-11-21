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

    func load(_ url: URL, start: Double?) async throws
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

/// AetherEngine-Backend.
@MainActor
final class AetherBackend: PlaybackEngine {
    let engine: AetherEngine
    private var bag: AnyCancellable?

    init() throws {
        engine = try AetherEngine()
        bag = engine.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var isPlaying: Bool { engine.state == .playing }
    var isLoading: Bool { engine.state == .loading || engine.state == .seeking }
    var isEnded: Bool { engine.state == .ended }
    var currentTime: Double { engine.clock.currentTime }
    var duration: Double { engine.duration }
    var audioTracks: [AudioTrackInfo] {
        engine.audioTracks.map { AudioTrackInfo(id: $0.id, language: $0.language, name: $0.name, channels: $0.channels) }
    }
    var activeAudioID: Int? { engine.activeAudioTrackIndex }
    var subtitleTracks: [AudioTrackInfo] {
        engine.subtitleTracks.map { AudioTrackInfo(id: $0.id, language: $0.language, name: $0.name) }
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

    func load(_ url: URL, start: Double?) async throws { _ = try await engine.load(url: url, startPosition: start) }
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
