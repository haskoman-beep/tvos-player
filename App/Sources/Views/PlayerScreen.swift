import SwiftUI
import Combine
import PlayerCore

/// Vollbild-Player. Kennt nur `PlaybackEngine`; das Backend ist austauschbar.
struct PlayerScreen: View {
    @EnvironmentObject var model: AppModel
    let url: URL
    let request: PlayRequest
    @State private var backend: AetherBackend?
    @State private var initError: String?

    var body: some View {
        Group {
            if let backend { PlayerControls(engine: backend, url: url, title: request.title, profile: model.profile,
                                                       start: model.progress.resumePosition(for: request.id),
                                                       report: { pos, dur in model.recordProgress(request, position: pos, duration: dur) }) }
            else { Text(initError ?? "Player wird gestartet …") }
        }
        .onAppear {
            do { backend = try AetherBackend() } catch { initError = "Player-Start fehlgeschlagen: \(error)" }
        }
    }
}

struct PlayerControls<E: PlaybackEngine>: View {
    @ObservedObject var engine: E
    let url: URL
    let title: String
    let profile: Profile
    let start: Double?
    let report: (Double, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showOverlay = true
    @State private var showTracks = false
    @State private var hideTask: Task<Void, Never>?
    @State private var loadError: String?
    @State private var tick = 0
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
        .onPlayPauseCommand { engine.isPlaying ? engine.pause() : engine.play(); poke() }
        .onMoveCommand { dir in
            switch dir {
            case .left: Task { await engine.seek(engine.currentTime - 10) }
            case .right: Task { await engine.seek(engine.currentTime + 10) }
            case .down: showTracks = true
            default: break
            }
            poke()
        }
        .onExitCommand { saveProgress(); engine.stop(); dismiss() }
        .onReceive(timer) { _ in
            tick &+= 1
            if tick % 10 == 0 && engine.isPlaying { saveProgress() }
        }
        .onDisappear { saveProgress() }
        .sheet(isPresented: $showTracks) { TrackSheet(engine: engine) }
        .task {
            do {
                try await engine.load(url, start: start)
                if let best = preferredAudioTrack(engine.audioTracks, priority: profile.audioPriority), best.id != engine.activeAudioID {
                    engine.selectAudio(best.id)
                }
                if profile.subtitlesEnabled,
                   let sub = engine.subtitleTracks.first(where: { ($0.language ?? "").hasPrefix(profile.subtitleLanguage) }) {
                    engine.selectSubtitle(sub.id)
                } else {
                    engine.selectSubtitle(nil)
                }
                engine.play()
                poke()
            } catch { loadError = "\(error)" }
        }
    }

    private var overlay: some View {
        let _ = tick
        let d = max(engine.duration, 1)
        return VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title3.bold())
            ProgressView(value: min(engine.currentTime, d), total: d)
            HStack {
                Text(fmt(engine.currentTime)); Spacer()
                Text(engine.infoText).font(.caption).foregroundStyle(.secondary)
                Spacer(); Text("-" + fmt(d - engine.currentTime))
            }
            .font(.caption.monospacedDigit())
            Text("◀▶ 10 s · ▼ Ton/Untertitel · ⏯ Pause · Zurück beenden").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(60)
        .background(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top))
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
