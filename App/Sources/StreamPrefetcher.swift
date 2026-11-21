import Foundation
import PlayerCore

/// Quellen vorladen (Task 7): Ruht der Fokus 350 ms auf einer Kachel (Entprellung in `HomeFocus`),
/// holt die App die Quellen dieses Titels über `AppModel.streams` (10-min-Cache, Abfragen dedupliziert).
/// Höchstens 2 Abfragen gleichzeitig; neue Ruhe-Kacheln verdrängen die älteste wartende,
/// laufende werden nie abgebrochen. Kein Vorladen, solange ein Player läuft.
/// Schonung der Addons (AIOStreams/Debrid): höchstens 8 Starts je 60 s (Überschuss verworfen),
/// leere Ergebnisse 120 s nicht erneut, nach „alle Addons leer“ 5 min Pause.
@MainActor
final class StreamPrefetcher {
    static let shared = StreamPrefetcher()
    static let maxRunning = 2
    static let maxWaiting = 2
    static let maxStartsPerMinute = 8
    static let allEmptyPause: TimeInterval = 300
    static let playerGrace: TimeInterval = 2
    /// Höchstzahl Einträge im Quellen-Cache (AppModel) und in `prefetched` – eine gemeinsame Grenze.
    static let cacheLimit = 40

    private struct Job { let type: String; let id: String }
    private var running = Set<String>()
    private var waiting: [Job] = []
    /// Starts der letzten 60 s (Token-Eimer).
    private var starts: [Date] = []
    /// Erfolgreich vorgeladene IDs mit Zeitpunkt (Log „vorgeladen“ nur, solange der Cache-Eintrag davon stammen kann).
    private var prefetched: [String: Date] = [:]
    /// Offene Player (je Bildschirm ein Kennzeichen, damit doppelte onAppear nichts verklemmen).
    private var players = Set<UUID>()
    /// Letztes Öffnen oder Schließen eines Players (2-s-Schonfrist).
    private var lastPlayerAppeared: Date?
    /// Zählt Ruhe-Kacheln; eine späte TMDB-Nachschlage-Antwort gilt nur, solange keine neuere Kachel ruht.
    private var generation = 0
    private var imagesVersion = 0

    private init() {}

    var playerActive: Bool { !players.isEmpty }

    /// Diese ID wird gerade vorgeladen (Log: Detailseite wartet auf das Vorladen).
    func isRunning(_ id: String) -> Bool { running.contains(id) }

    /// Cache-Eintrag dieser ID stammt (noch) vom Vorladen.
    func wasPrefetched(_ id: String) -> Bool {
        guard let at = prefetched[id] else { return false }
        return Date().timeIntervalSince(at) < RevalidationPolicy.streams.usableFor
    }

    func playerAppeared(_ token: UUID) {
        players.insert(token)
        lastPlayerAppeared = Date()
        waiting.removeAll()
        notifyImages()
    }

    func playerDisappeared(_ token: UUID) {
        players.remove(token)
        lastPlayerAppeared = Date()   // auch nach dem Schließen 2 s Ruhe
        notifyImages()
    }

    /// Bildspeicher (Welle A b): während der Wiedergabe klein. Fortlaufende Nummer, damit eine
    /// verspätete ältere Meldung den neueren Zustand nicht überschreibt.
    private func notifyImages() {
        imagesVersion += 1
        let active = playerActive, version = imagesVersion
        Task { await ImagePipeline.shared.setPlaybackActive(active, version: version) }
    }

    /// Ruhe-Kachel: Ziel bestimmen und einreihen. Ohne IMDb-ID oder bei Serien ohne bekannte Folge: nichts.
    func request(_ route: Route, model: AppModel) {
        generation += 1
        guard allowed(model) else { return }
        switch route {
        case .streams(let r):
            enqueue(Job(type: r.type, id: r.id), model: model)
        case .detail(let m) where m.type == "movie":
            if m.id.hasPrefix("tt") { enqueue(Job(type: "movie", id: m.id), model: model); return }
            // TMDB-Eintrag: nur die IMDb-ID nachschlagen (gecacht, wie die Detailseite), keine Meta-Abfrage.
            // Ruht inzwischen eine andere Kachel, verfällt die Anfrage.
            let gen = generation
            Task {
                guard let imdb = await model.imdbID(for: m), gen == self.generation else { return }
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

    /// Darf jetzt überhaupt vorgeladen werden (Schalter, Player offen/gerade gestartet, Pause nach „alle leer“)?
    private func allowed(_ model: AppModel) -> Bool {
        guard model.profile.appearance.prefetchStreams, !playerActive else { return false }
        let now = Date()
        if let t = lastPlayerAppeared, now.timeIntervalSince(t) < Self.playerGrace { return false }
        if let t = model.streamsAllEmptyAt, now.timeIntervalSince(t) < Self.allEmptyPause { return false }
        return true
    }

    /// Freie Starts im Token-Eimer (60 s).
    private func freeStarts() -> Int {
        let now = Date()
        starts.removeAll { now.timeIntervalSince($0) >= 60 }
        return Self.maxStartsPerMinute - starts.count
    }

    private func enqueue(_ job: Job, model: AppModel) {
        guard allowed(model), model.streamCacheState(id: job.id) == .missing,
              !running.contains(job.id) else { return }
        waiting.removeAll { $0.id == job.id }
        // Eimer voll: verwerfen, nicht einreihen. Bei vollem Laufplatz zählen die Wartenden mit, außer dem Platz,
        // den die neue Kachel gleich durch Verdrängen der ältesten wartenden bekommt (die neue gewinnt).
        let reserved = running.count < Self.maxRunning ? 0 : min(waiting.count, Self.maxWaiting - 1)
        guard freeStarts() - reserved > 0 else { return }
        if running.count < Self.maxRunning {
            start(job, model: model)
        } else {
            waiting.append(job)
            if waiting.count > Self.maxWaiting { waiting.removeFirst() }
        }
    }

    private func start(_ job: Job, model: AppModel) {
        guard allowed(model), freeStarts() > 0 else { return }
        running.insert(job.id)
        let t0 = Date()
        starts.append(t0)
        Task {
            let list = await model.streams(type: job.type, id: job.id)
            self.running.remove(job.id)
            if !list.isEmpty { self.markPrefetched(job.id) }
            RemoteLog.info("prefetch", "prefetch → \(job.id) (\(Int(Date().timeIntervalSince(t0) * 1000)) ms, \(list.count) Quellen)")
            self.startNext(model: model)
        }
    }

    /// Wie der Quellen-Cache: abgelaufene raus, höchstens 40, älteste zuerst raus.
    private func markPrefetched(_ id: String) {
        let now = Date()
        prefetched = prefetched.filter { now.timeIntervalSince($0.value) < RevalidationPolicy.streams.usableFor }
        prefetched[id] = now
        if prefetched.count > Self.cacheLimit {
            for (k, _) in prefetched.sorted(by: { $0.value < $1.value }).prefix(prefetched.count - Self.cacheLimit) {
                prefetched[k] = nil
            }
        }
    }

    /// Freier Platz: die jüngste wartende Kachel zuerst (der Fokus ist meist noch dort).
    private func startNext(model: AppModel) {
        guard allowed(model) else { waiting.removeAll(); return }
        // Eimer leer: Überschuss verwerfen statt ihn später nachzuholen.
        guard freeStarts() > 0 else { waiting.removeAll(); return }
        while running.count < Self.maxRunning, freeStarts() > 0, let job = waiting.popLast() {
            guard model.streamCacheState(id: job.id) == .missing, !running.contains(job.id) else { continue }
            start(job, model: model)
        }
    }
}
