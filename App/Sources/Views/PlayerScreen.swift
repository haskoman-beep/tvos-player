import SwiftUI
import Combine
import PlayerCore

/// Vollbild-Player. Kennt nur `PlaybackEngine`; das Backend ist austauschbar.
struct PlayerScreen: View {
    @EnvironmentObject var model: AppModel
    let url: URL
    let request: PlayRequest
    var headers: [String: String] = [:]
    var onEnded: () -> Void = {}
    /// Quelle taugt nicht (Platzhalter, Fehler nach Neustart): nächste Quelle versuchen.
    var onFallback: (String) -> Void = { _ in }
    @State private var backend: AetherBackend?
    @State private var initError: String?

    var body: some View {
        Group {
            if let backend { PlayerControls(engine: backend, url: url, title: request.title, profile: model.profile,
                                                       start: model.progress.resumePosition(for: request.id),
                                                       startFraction: model.progress.resumeFraction(for: request.id),
                                                       runtimeMinutes: request.runtimeMinutes,
                                                       prefs: LoadPrefs(audioLanguages: model.profile.audioPriority.filter { $0 != "orig" },
                                                                        subtitleLanguages: model.profile.subtitlesEnabled ? [model.profile.subtitleLanguage] : [],
                                                                        headers: headers),
                                                       report: { pos, dur in model.recordProgress(request, position: pos, duration: dur) },
                                                       onEnded: onEnded, onFallback: onFallback,
                                                       onPause: { model.scrobblePause(request) }) }
            else { Text(initError ?? "Player wird gestartet …") }
        }
        .onDisappear { model.endPlayback(request) }
        .onAppear {
            do { backend = try AetherBackend() } catch { initError = "Player-Start fehlgeschlagen: \(error)"; RemoteLog.error("player", initError ?? "") }
        }
    }
}

struct PlayerControls<E: PlaybackEngine>: View {
    @ObservedObject var engine: E
    let url: URL
    let title: String
    let profile: Profile
    let start: Double?
    var startFraction: Double? = nil
    var runtimeMinutes: Double? = nil
    var prefs = LoadPrefs()
    let report: (Double, Double) -> Void
    let onEnded: () -> Void
    var onFallback: (String) -> Void = { _ in }
    var onPause: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var showOverlay = true
    @State private var showTracks = false
    @State private var hideTask: Task<Void, Never>?
    @State private var loadError: String?
    @State private var tick = 0
    @State private var fractionApplied = false
    /// Gesammeltes Sprungziel: mehrere ±10-s-Drücke werden zu einem Sprung (Muxer-Neustarts sparen).
    @State private var pendingSeek: Double?
    @State private var seekTask: Task<Void, Never>?
    @State private var lastToggle = Date.distantPast
    @State private var recoveries = 0
    @State private var lastGoodTime: Double = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            engine.surface().ignoresSafeArea()
            if engine.isLoading { ProgressView().scaleEffect(2) }
            if let e = loadError ?? engine.errorText {
                Text("Fehler: \(e)").padding(30).background(.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
            }
            if showOverlay { overlay.transition(.opacity) }
        }
        .focusable()
        .onPlayPauseCommand { togglePlay() }
        .onTapGesture { togglePlay() }   // Klick auf das Touchpad (Mitte) pausiert ebenfalls
        .onMoveCommand { dir in
            switch dir {
            case .left: queueSeek(-10)
            case .right: queueSeek(10)
            case .down: showTracks = true
            default: break
            }
            poke()
        }
        .onExitCommand { saveProgress(); engine.stop(); dismiss() }
        .onReceive(timer) { _ in
            tick &+= 1
            if engine.isPlaying, engine.errorText == nil { lastGoodTime = engine.currentTime }
            if tick % 10 == 0 && engine.isPlaying { saveProgress() }
        }
        .onDisappear { saveProgress(); RemoteLog.info("player", "Verlassen") }
        .onChange(of: engine.errorText) { _, e in
            guard let e else { return }
            RemoteLog.error("player", "Engine: \(e) · \(engine.infoText) · \(engine.errorDetail) · bei \(Int(lastGoodTime))s")
            recover(e)
        }
        .onChange(of: engine.duration) { _, d in
            // Stand aus Trakt/Simkl kennt nur den Anteil: springen, sobald die Laufzeit da ist.
            guard d > 0, !fractionApplied, start == nil, let f = startFraction else { return }
            fractionApplied = true
            Task { await engine.seek(f * d) }
        }
        .onChange(of: engine.isEnded) { _, ended in
            guard ended else { return }
            if engine.duration > 0 { report(engine.duration, engine.duration) }
            engine.stop()
            onEnded()
        }
        .sheet(isPresented: $showTracks) { TrackSheet(engine: engine) }
        .task {
            do {
                RemoteLog.info("player", "Laden \(title) · Start \(start.map { Int($0) } ?? 0)s · \(url.host ?? "?")")
                try await engine.load(url, start: start, prefs: prefs)
                if isPlaceholderVideo(duration: engine.duration, expectedRuntimeMinutes: runtimeMinutes) {
                    RemoteLog.info("player", "Platzhalter erkannt (\(Int(engine.duration))s, erwartet \(runtimeMinutes.map { Int($0) } ?? 0) min) → nächste Quelle")
                    engine.stop(); onFallback("Quelle noch nicht bereit (Platzhalter)"); return
                }
                RemoteLog.info("player", "Geladen · \(Int(engine.duration))s · \(engine.infoText) · Ton: " +
                    engine.audioTracks.map { "\($0.id):\($0.language ?? "?")/\($0.channels ?? 0)ch" }.joined(separator: " ") +
                    " · UT: \(engine.subtitleTracks.count)")
                if let best = preferredAudioTrack(engine.audioTracks, priority: profile.audioPriority), best.id != engine.activeAudioID {
                    engine.selectAudio(best.id)
                }
                if profile.subtitlesEnabled,
                   let sub = engine.subtitleTracks.first(where: { ($0.language ?? "").hasPrefix(profile.subtitleLanguage) }) {
                    engine.selectSubtitle(sub.id)
                } else {
                    engine.selectSubtitle(nil)
                }
                RemoteLog.info("player", "Spielt · Tonspur \(engine.activeAudioID.map(String.init) ?? "-") · UT \(engine.activeSubtitleID.map(String.init) ?? "aus")")
                engine.play()
                poke()
            } catch { loadError = "\(error)"; RemoteLog.error("player", "Laden fehlgeschlagen: \(error)") }
        }
    }

    private var overlay: some View {
        let _ = tick
        let d = max(engine.duration, 1)
        return VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title3.bold())
            ProgressView(value: min(pendingSeek ?? engine.currentTime, d), total: d)
            HStack {
                Text(fmt(pendingSeek ?? engine.currentTime)); Spacer()
                Text(engine.infoText).font(.caption).foregroundStyle(.secondary)
                Spacer(); Text("-" + fmt(d - engine.currentTime))
            }
            .font(.caption.monospacedDigit())
            Text("◀▶ 10 s · ▼ Ton/Untertitel · ⏯ Pause · Zurück beenden").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(60)
        .background(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top))
    }

    private func togglePlay() {
        // Ein Druck kann doppelt ankommen (Play/Pause-Taste + Systembefehl): zweiten innerhalb 350 ms ignorieren.
        let now = Date()
        if now.timeIntervalSince(lastToggle) < 0.35 { RemoteLog.info("player", "Play/Pause doppelt, ignoriert"); return }
        lastToggle = now
        let before = engine.stateText
        if engine.errorText != nil { recoveries = 0; recover("Neuer Versuch per Play/Pause"); return }
        engine.togglePlayPause()
        RemoteLog.info("player", "Play/Pause gedrückt · Zustand vorher \(before)")
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            RemoteLog.info("player", "Play/Pause · Zustand danach \(engine.stateText)")
            if !engine.isPlaying { saveProgress(); onPause() }
        }
        poke()
    }

    /// ±10 s sammeln und nach 450 ms einmal springen.
    private func queueSeek(_ delta: Double) {
        let base = pendingSeek ?? engine.currentTime
        let limit = engine.duration > 10 ? engine.duration - 5 : .greatestFiniteMagnitude
        let target = min(max(0, base + delta), limit)
        pendingSeek = target
        seekTask?.cancel()
        seekTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            RemoteLog.info("player", "Sprung \(Int(engine.currentTime)) → \(Int(target))s")
            await engine.seek(target)
            pendingSeek = nil
        }
    }

    /// Fehler mitten im Film: einmal an der Stelle neu laden (frisches Muxer-Budget), sonst nächste Quelle.
    private func recover(_ reason: String) {
        guard recoveries < 1 else {
            RemoteLog.error("player", "Neu laden half nicht → nächste Quelle")
            saveProgress(); engine.stop(); onFallback("Wiedergabefehler: \(reason)"); return
        }
        recoveries += 1
        let pos = lastGoodTime
        RemoteLog.info("player", "Neu laden an \(Int(pos))s nach: \(reason)")
        Task {
            do { try await engine.recover() }
            catch {
                RemoteLog.error("player", "reloadAtCurrentPosition fehlgeschlagen: \(error) → load ab \(Int(pos))s")
                do { try await engine.load(url, start: pos, prefs: prefs) }
                catch { engine.stop(); onFallback("Wiedergabefehler: \(reason)"); return }
            }
            engine.play()
        }
    }

    private func saveProgress() {
        guard engine.duration > 0, engine.currentTime > 0 else { return }
        report(engine.currentTime, engine.duration)
    }

    private func poke() {
        withAnimation { showOverlay = true }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled && engine.isPlaying { withAnimation { showOverlay = false } }
        }
    }

    private func fmt(_ s: Double) -> String {
        let t = Int(max(0, s)); return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}

struct TrackSheet<E: PlaybackEngine>: View {
    @ObservedObject var engine: E
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Section("Ton") {
                ForEach(engine.audioTracks, id: \.id) { t in
                    Button { engine.selectAudio(t.id); dismiss() } label: {
                        HStack {
                            Text("\(t.language?.uppercased() ?? "?") · \(t.name ?? "") · \(t.channels ?? 0) Kanäle")
                            Spacer()
                            if t.id == engine.activeAudioID { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            Section("Untertitel") {
                Button { engine.selectSubtitle(nil); dismiss() } label: {
                    HStack { Text("Aus"); Spacer(); if engine.activeSubtitleID == nil { Image(systemName: "checkmark") } }
                }
                ForEach(engine.subtitleTracks, id: \.id) { t in
                    Button { engine.selectSubtitle(t.id); dismiss() } label: {
                        HStack {
                            Text("\(t.language?.uppercased() ?? "?") · \(t.name ?? "")")
                            Spacer()
                            if t.id == engine.activeSubtitleID { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        }
    }
}
