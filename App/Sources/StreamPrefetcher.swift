import Foundation
import PlayerCore

/// Quellen vorladen (Task 7): Ruht der Fokus 350 ms auf einer Kachel (Entprellung in `HomeFocus`),
/// holt die App die Quellen dieses Titels über `AppModel.streams` (10-min-Cache, Abfragen dedupliziert).
/// Höchstens 2 Abfragen gleichzeitig; neue Ruhe-Kacheln verdrängen die älteste wartende,
/// laufende werden nie abgebrochen. Kein Vorladen, solange ein Player läuft.
/// Schonung der Addons (AIOStreams/Debrid): leere Ergebnisse 120 s nicht erneut, nach „alle Addons leer“ 5 min Pause.
/// Wave F-k R1: also quietly for poster tiles on screen (quality badges for every visible tile), planned by PlayerCore
/// `VisiblePrefetchPlan`: 400 ms after scrolling stops, at most 4 at once (+ the 2 focus slots = 6 in all),
/// off-screen tiles dropped, a title fetched once per source cache lifetime, only while poster badges are on. Same
/// pauses as above (player open, „alle Addons leer“, setting off).
/// Wave F-k R2: one budget for both, 12 searches per 60 s (`PrefetchBudget`): the focus prefetch first (it may use
/// all; surplus dropped as before), visible tiles only above a reserve of 4 and not while a page runs its own source
/// search. Visible-tile results are the weak tier of the source cache (`StreamCacheTiers`).
@MainActor
final class StreamPrefetcher {
    static let shared = StreamPrefetcher()
    static let maxRunning = 2
    static let maxWaiting = 2
    /// Wave F-k R2: searches per 60 s for both prefetchers together; starts the visible tiles leave to the focus.
    static let searchesPerMinute = 12
    static let focusReserve = 4
    static let allEmptyPause: TimeInterval = 300
    static let playerGrace: TimeInterval = 2
    /// Höchstzahl Einträge im Quellen-Cache (AppModel) und in `prefetched` – eine gemeinsame Grenze.
    static let cacheLimit = 40

    private struct Job { let type: String; let id: String }
    private var running = Set<String>()
    private var waiting: [Job] = []
    /// Erfolgreich vorgeladene IDs mit Zeitpunkt (Log „vorgeladen“ nur, solange der Cache-Eintrag davon stammen kann).
    private var prefetched: [String: Date] = [:]
    /// Offene Player (je Bildschirm ein Kennzeichen, damit doppelte onAppear nichts verklemmen).
    private var players = Set<UUID>()
    /// Letztes Öffnen oder Schließen eines Players (2-s-Schonfrist).
    private var lastPlayerAppeared: Date?
    /// Zählt Ruhe-Kacheln; eine späte TMDB-Nachschlage-Antwort gilt nur, solange keine neuere Kachel ruht.
    private var generation = 0
    private var imagesVersion = 0

    /// Wave F-k R1: tiles on screen (plan), their entries, row names for the log, running jobs, pending pass.
    /// Its `budget` is the token bucket of both prefetchers (R2).
    private var visible = VisiblePrefetchPlan(budget: PrefetchBudget(perMinute: StreamPrefetcher.searchesPerMinute,
                                                                     focusReserve: StreamPrefetcher.focusReserve))
    private var visibleItems: [String: MetaPreview] = [:]
    private var rowTitles: [String: String] = [:]
    private var visibleJobs: [String: Task<Void, Never>] = [:]
    private var passTask: Task<Void, Never>?
    private weak var visibleModel: AppModel?

    private init() {}

    var playerActive: Bool { !players.isEmpty }

    /// Welle D-b (Mi2): Profilwechsel – Plätze der alten Suchen freigeben (sie laufen aus, ohne etwa abzulegen),
    /// damit das neue Profil dieselben Titel gleich vorladen kann.
    func reset() {
        running.removeAll(); waiting.removeAll(); prefetched.removeAll()
        generation += 1; resets += 1
        // Wave F-k R1: results of the old profile out; tiles on screen are fetched again for the new one.
        for t in visibleJobs.values { t.cancel() }
        visibleJobs.removeAll()
        visible.resetResults(now: Date())
        QualityBadgeCache.shared.forget()
        if let m = visibleModel { scheduleVisiblePass(m) }
    }
    /// Zählt `reset()`: ein Vorladen von vor dem Wechsel gibt keinen Platz des neuen Profils frei.
    private var resets = 0

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
        // Wave F-k R1: visible-tile jobs not yet searching stop; the plan keeps the tiles for after the player.
        passTask?.cancel()
        for t in visibleJobs.values { t.cancel() }
        notifyImages()
    }

    func playerDisappeared(_ token: UUID) {
        players.remove(token)
        lastPlayerAppeared = Date()   // auch nach dem Schließen 2 s Ruhe
        notifyImages()
        if let m = visibleModel { scheduleVisiblePass(m, after: Self.playerGrace + 0.1) }
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
            // Nur wenn die Folge ohne Netzabfrage bekannt ist: angefangene Folge aus dem Fortschritt. (Wave F-k R2:
            // no S1E1 here – the detail page then mostly needs another episode; the badge comes from visible tiles.)
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

    /// Freie Starts im gemeinsamen Eimer (60 s); das Fokus-Vorladen darf alle nehmen (R2).
    private func freeStarts() -> Int { visible.budget.free(.focus, now: Date()) }

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
        visible.budget.take(.focus, now: t0)
        let epoch = resets
        Task {
            // Welle D-b (M3): veralteter, lückenhafter Stand → wirklich neu fragen (nicht nur den Cache-Treffer holen).
            let list = await model.streams(type: job.type, id: job.id, revalidate: model.partialNeedsRefresh(id: job.id),
                                           caller: .focusPrefetch)
            guard epoch == self.resets else { return }
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

// MARK: - Wave F-k R1: tiles on screen

extension StreamPrefetcher {
    /// A poster tile came on screen or left it (`row`: its row for order and log). Only films and series.
    func tile(_ item: MetaPreview, row: PrefetchRow, visible on: Bool, model: AppModel) {
        guard item.type == "movie" || item.type == "series" else { return }
        visibleModel = model
        let key = "\(item.type)|\(item.id)"
        guard on || visibleItems[key] != nil else { return }   // never registered: nothing to drop
        if on { visibleItems[key] = item; rowTitles[row.key] = row.title }
        let cancel = visible.setTile(key, row: row.key, visible: on, now: Date())
        for k in cancel { visibleJobs[k]?.cancel() }
        if !on, !visible.isVisible(key), !visible.isRunning(key) { visibleItems[key] = nil }
        scheduleVisiblePass(model)
    }

    /// Next pass when the plan allows it (debounce after the last change, or a free start of the per-minute limit).
    fileprivate func scheduleVisiblePass(_ model: AppModel, after delay: TimeInterval? = nil) {
        passTask?.cancel()
        let due = delay.map { Date().addingTimeInterval($0) } ?? visible.dueAt ?? Date()
        passTask = Task { [weak self] in
            let wait = due.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .milliseconds(Int(wait * 1000) + 10)) }
            guard !Task.isCancelled else { return }
            self?.visiblePass(model)
        }
    }

    private func visiblePass(_ model: AppModel) {
        guard allowed(model) else {
            // Player just closed (2 s rest): try again afterwards. Player open, setting off, „alle leer“: the next
            // tile change or the player closing schedules the next pass.
            if !playerActive, let t = lastPlayerAppeared, Date().timeIntervalSince(t) < Self.playerGrace {
                scheduleVisiblePass(model, after: Self.playerGrace - Date().timeIntervalSince(t) + 0.1)
            }
            return
        }
        let start = visible.pass(now: Date()) { self.tileState($0, model: model) }
        for key in start { startVisible(key, model: model) }
        logVisibleRows()
        if let next = visible.nextStartAt(now: Date()) { scheduleVisiblePass(model, after: max(0, next.timeIntervalSinceNow)) }
    }

    private func tileState(_ key: String, model: AppModel) -> VisiblePrefetchPlan.TileState {
        guard let item = visibleItems[key], model.profile.appearance.titles.posterBadges != .off else { return .skip }
        if QualityBadgeCache.shared.best(for: item, model: model) != nil { return .known }
        guard let id = model.streamCacheKey(for: item) else { return .needed }   // IMDb ID still to look up
        switch model.streamCacheState(id: id) {
        case .cached: return .known
        case .running: return .busy
        case .emptyRecently: return .skip
        case .missing: return .needed
        }
    }

    private func startVisible(_ key: String, model: AppModel) {
        guard let item = visibleItems[key] else {
            visible.finished(key, outcome: .unavailable, now: Date()); return
        }
        let epoch = resets
        visibleJobs[key] = Task {
            let outcome = await self.searchVisible(item, model: model)
            guard epoch == self.resets else { return }
            self.visibleJobs[key] = nil
            self.visible.finished(key, outcome: outcome, now: Date())
            if !self.visible.isVisible(key) { self.visibleItems[key] = nil }
            self.visiblePass(model)
        }
    }

    /// One tile: IMDb ID (cached lookup for TMDB entries), target (PrefetchTarget), then the shared source search
    /// (`AppModel.streams`: cache, merged queries). Cancel only bites before the search starts – a running search is
    /// shared with the detail page and fills the cache anyway.
    private func searchVisible(_ item: MetaPreview, model: AppModel) async -> VisiblePrefetchPlan.Outcome {
        let imdb = await model.imdbID(for: item)
        guard !Task.isCancelled, allowed(model) else { return .cancelled }
        let progress = item.type == "series" ? model.progress.latest(forItem: item.id) : nil
        guard let id = PrefetchTarget.streamID(type: item.type, imdb: imdb, progress: progress) else { return .unavailable }
        switch model.streamCacheState(id: id) {
        case .cached, .running: return .known
        case .emptyRecently: return .unavailable
        case .missing: break
        }
        let list = await model.streams(type: item.type, id: id, revalidate: model.partialNeedsRefresh(id: id),
                                       caller: .visiblePrefetch)
        if !list.isEmpty { markPrefetched(id) }
        return .loaded
    }

    /// Wave F-k R2: a page (detail, source list, player) runs its own source search: no new visible-tile starts.
    func pageSearchBegan() { visible.budget.foregroundSearchBegan() }

    func pageSearchEnded(_ model: AppModel) {
        visible.budget.foregroundSearchEnded()
        if visible.budget.foregroundSearches == 0, visibleModel != nil { scheduleVisiblePass(model) }
    }

    /// „Vorab-Quellen: <Reihe> n geladen, k aus Cache, m abgebrochen“, once per row when it has settled.
    private func logVisibleRows() {
        for r in visible.reports() { RemoteLog.info("home", r.tally.logLine(row: rowTitles[r.row] ?? r.row)) }
    }
}

/// Wave F-k R1: row of a poster tile for the visible-tile prefetch (order and log line). Rows set it for their
/// tiles; grids without a row share „Kacheln“.
struct PrefetchRow: Equatable {
    var key: String
    var title: String
}
