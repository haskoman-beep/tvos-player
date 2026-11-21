import Foundation
import PlayerCore

/// Quellen vorladen (Task 7): Ruht der Fokus 350 ms auf einer Kachel (Entprellung in `HomeFocus`),
/// holt die App die Quellen dieses Titels über `AppModel.streams` (10-min-Cache, Abfragen dedupliziert).
/// Höchstens 2 Abfragen gleichzeitig; neue Ruhe-Kacheln verdrängen die älteste wartende,
/// laufende werden nie abgebrochen. Kein Vorladen, solange ein Player läuft.
@MainActor
final class StreamPrefetcher {
    static let shared = StreamPrefetcher()
    static let maxRunning = 2
    static let maxWaiting = 2

    private struct Job { let type: String; let id: String }
    private var running = Set<String>()
    private var waiting: [Job] = []
    /// Erfolgreich vorgeladene IDs (fürs Log der Detailseite/Quellenliste: Cache-Treffer durch Vorladen).
    private(set) var prefetched = Set<String>()
    /// Offene Player (je Bildschirm ein Kennzeichen, damit doppelte onAppear nichts verklemmen).
    private var players = Set<UUID>()

    private init() {}

    var playerActive: Bool { !players.isEmpty }

    /// Diese ID wird gerade vorgeladen (Log: Detailseite wartet auf das Vorladen).
    func isRunning(_ id: String) -> Bool { running.contains(id) }

    func playerAppeared(_ token: UUID) {
        players.insert(token)
        waiting.removeAll()
    }

    func playerDisappeared(_ token: UUID) {
        players.remove(token)
    }

    /// Ruhe-Kachel: Ziel bestimmen und einreihen. Ohne IMDb-ID oder bei Serien ohne bekannte Folge: nichts.
    func request(_ route: Route, model: AppModel) {
        guard model.profile.appearance.prefetchStreams, !playerActive else { return }
        switch route {
        case .streams(let r):
            enqueue(Job(type: r.type, id: r.id), model: model)
        case .detail(let m) where m.type == "movie":
            if m.id.hasPrefix("tt") { enqueue(Job(type: "movie", id: m.id), model: model); return }
            // TMDB-Eintrag: nur die IMDb-ID nachschlagen (wie die Detailseite), keine Meta-Abfrage.
            Task {
                guard let imdb = await model.imdbID(for: m) else { return }
                self.enqueue(Job(type: "movie", id: imdb), model: model)
            }
        case .detail(let m) where m.type == "series":
            // Nur wenn die Folge ohne Netzabfrage bekannt ist: angefangene Folge aus dem Fortschritt.
            guard let p = model.progress.latest(forItem: m.id), p.season != nil, p.episode != nil, !p.finished else { return }
            enqueue(Job(type: "series", id: p.id), model: model)
        default:
            return
        }
    }

    private func enqueue(_ job: Job, model: AppModel) {
        guard model.profile.appearance.prefetchStreams, !playerActive,
              model.streamCacheState(id: job.id) == .missing,
              !running.contains(job.id) else { return }
        waiting.removeAll { $0.id == job.id }
        if running.count < Self.maxRunning {
            start(job, model: model)
        } else {
            waiting.append(job)
            if waiting.count > Self.maxWaiting { waiting.removeFirst() }
        }
    }

    private func start(_ job: Job, model: AppModel) {
        running.insert(job.id)
        let t0 = Date()
        Task {
            let list = await model.streams(type: job.type, id: job.id)
            self.running.remove(job.id)
            if !list.isEmpty { self.prefetched.insert(job.id) }
            RemoteLog.info("prefetch", "prefetch → \(job.id) (\(Int(Date().timeIntervalSince(t0) * 1000)) ms, \(list.count) Quellen)")
            self.startNext(model: model)
        }
    }

    /// Freier Platz: die jüngste wartende Kachel zuerst (der Fokus ist meist noch dort).
    private func startNext(model: AppModel) {
        while !playerActive, running.count < Self.maxRunning, let job = waiting.popLast() {
            guard model.profile.appearance.prefetchStreams else { waiting.removeAll(); return }
            guard model.streamCacheState(id: job.id) == .missing, !running.contains(job.id) else { continue }
            start(job, model: model)
        }
    }
}
