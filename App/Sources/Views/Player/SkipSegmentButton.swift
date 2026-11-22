import SwiftUI
import PlayerCore

extension AppModel {
    /// IntroDB-Abfrage für den PlayRequest (Film oder Folge); nil ohne IMDb-ID.
    func introDBQuery(for r: PlayRequest) async -> IntroDBQuery? {
        var imdb = await imdbID(for: r.item)
        if imdb == nil, r.id.hasPrefix("tt") { imdb = r.id.split(separator: ":").first.map(String.init) }
        guard let imdb else { return nil }
        SkipSegmentController.attachDisk(store.storage)   // IntroDB-Plattencache (Welle C-c)
        if r.type == "series" {
            guard let s = r.season, let e = r.episode else { return nil }
            return IntroDBQuery(imdb: imdb, season: s, episode: e)
        }
        return IntroDBQuery(imdb: imdb)
    }
}

/// Sprungbereiche der laufenden Wiedergabe: IntroDB + Kapitel, Planer für den Knopf, Abspann-Zeitpunkt.
/// Lebt als @StateObject in PlayerControls (eine Wiedergabe = ein Controller).
/// Wave P-a: action per segment type (`Profile.skip`, PlayerCore `SkipPolicy`), countdown for "Automatisch",
/// hint „Szene nach dem Abspann“ and the card after a movie (PostPlayCard.swift).
@MainActor
final class SkipSegmentController: ObservableObject {
    /// Bereich, für den der Knopf gerade steht (nil = kein Knopf).
    @Published private(set) var prompt: SkipSegment?
    /// Wave P-a: seconds left before the automatic jump (nil = plain button).
    @Published private(set) var countdown: Double?
    /// Wave P-a: the card after a movie is up (it holds the focus like the button).
    @Published private(set) var postPlayVisible = false
    /// Wave P-a: the card was closed („Abspann weiterschauen“/Menu); comes back only after rewinding before the credits.
    private var postPlayClosed = false
    /// Wave P-a: the credits run and a scene follows them (non-focusable hint).
    @Published private(set) var sceneHint = false
    /// Wave P-a: the next scene after the credits starts here (for the card's hint line); nil = none known.
    @Published private(set) var sceneStart: Double?
    /// Wave P-a: settings and context, set by SkipSegmentButton on every update.
    var settings = SkipSettings()
    var upNextCard = false
    var isMovie = false
    /// Wave P-a: false = jumps are blocked right now (leaving, after background until Play, track panel open).
    /// Never counts as a key press (an automatic jump keeps the „Noch da?“ counter running).
    var canSkip: () -> Bool = { true }

    /// Wave P-a: button or card on screen; PlayerControls then gives up the surface focus and blocks scrubbing.
    var holdsFocus: Bool { prompt != nil || postPlayVisible }
    /// Zeitpunkt der Nächste-Folge-Karte aus dem Abspann (Sekunden ab Dateibeginn); nil = Standard
    /// (bisherige Regel 20 s vor Ende). Für Abschnitt c (Up-next).
    @Published private(set) var upNextAt: Double?
    /// Alle bekannten Bereiche (Kapitel gewinnen je Art).
    @Published private(set) var segments: [SkipSegment] = []

    private var planner = SkipPlanner()
    private var introDB: [SkipSegment] = []
    private var chapters: [ChapterMark] = []
    private var duration: Double = 0
    private var lookupDone = false
    /// Abfrage dieser Wiedergabe (für Laufzeit nachtragen und Staffel-Schätzung).
    private var query: IntroDBQuery?
    /// Andere Folgen der Staffel (für die Schätzung, wenn diese Folge keine Marken hat).
    private var neighbors: [SkipSegmentStore.Entry] = []
    private var durationNoted = false
    /// Staffel-Schätzung fertig (eigenes Kennzeichen: bricht `.task` dabei ab, läuft sie beim nächsten Mal erneut).
    private var estimateDone = false
    /// Treffer je Abfrage (nur nicht-leere Antworten; Fehler werden nicht gemerkt), auf dem Gerät gespeichert.
    private static var disk = SkipSegmentStore()
    private static var storage: BlobStorage?

    /// Ablage einmal anhängen und die gespeicherten Marken laden.
    static func attachDisk(_ s: BlobStorage) {
        guard storage == nil else { return }
        storage = s
        disk = SkipSegmentStore.load(from: s)
        RemoteLog.info("skip", "IntroDB-Plattencache: \(disk.entries.count) Einträge")
    }

    private static func saveDisk() {
        guard let storage else { return }
        do { try disk.save(to: storage) } catch { RemoteLog.error("skip", "IntroDB-Plattencache nicht gespeichert: \(error)") }
    }

    /// IntroDB einmal je Wiedergabe abfragen. Abgebrochen (Player verlassen/Panel) → beim nächsten Mal erneut.
    func lookup(_ query: (@MainActor () async -> IntroDBQuery?)?) async {
        guard let query else { return }
        if lookupDone {
            if !estimateDone, let q = self.query { await estimateFromSeason(q) }
            return
        }
        // Kein `leaving`-Wächter nötig: hier wird nur Zustand dieses Controllers gesetzt (kein Start, kein Ausgang,
        // keine Engine-Aufrufe). Beim Verlassen bricht `.task` ab, und der Controller stirbt mit PlayerControls.
        guard let q = await query() else { lookupDone = true; estimateDone = true; RemoteLog.info("skip", "IntroDB: keine Abfrage (Trailer oder ohne IMDb-ID)"); return }
        guard !Task.isCancelled else { return }
        self.query = q
        introDB = await Self.segments(q)
        guard !Task.isCancelled else { return }
        lookupDone = true
        rebuild()
        await estimateFromSeason(q)
    }

    /// Marken aus dem Plattencache oder von IntroDB. Gespeichert werden Antworten mit Marken (60 Tage) und
    /// „keine Marken“ (5 Tage, keine wiederholten Abfragen); Fehler nie.
    private static func segments(_ q: IntroDBQuery) async -> [SkipSegment] {
        if let hit = disk.entry(q) { return hit.segments }
        let tag = "\(q.imdb)\(q.isMovie ? "" : " S\(q.season ?? 0)E\(q.episode ?? 0)")"
        let answer = await IntroDBClient().lookup(q, log: { line in
            Task { @MainActor in RemoteLog.info("skip", "IntroDB \(tag): \(line)") }
        })
        guard let list = answer, !Task.isCancelled else { return answer ?? [] }
        disk.store(list, for: q)
        saveDisk()
        return list
    }

    /// Folge ohne Intro/Rückblick: aus anderen Folgen der Staffel schätzen (Nachbarn nachladen, bis zwei mit Marken
    /// bekannt sind; höchstens vier Abfragen). Echte Marken und Kapitel gewinnen immer; kein Auto-Sprung.
    private func estimateFromSeason(_ q: IntroDBQuery) async {
        guard !q.isMovie, let s = q.season, let e = q.episode,
              !introDB.contains(where: { $0.kind == .intro || $0.kind == .recap }) else { estimateDone = true; return }
        var known = Self.disk.seasonNeighbors(of: q)
        let withIntro = { (list: [SkipSegmentStore.Entry]) in list.filter { $0.segments.contains { $0.kind == .intro } }.count }
        if withIntro(known) < SeasonSkipEstimate.minEpisodes {
            let missing = SkipSegmentStore.neighborEpisodes(of: e).map { IntroDBQuery(imdb: q.imdb, season: s, episode: $0) }
                .filter { Self.disk.entry($0) == nil }
            await withTaskGroup(of: Void.self) { g in
                for n in missing { g.addTask { @MainActor in _ = await Self.segments(n) } }
            }
            guard !Task.isCancelled else { return }
            known = Self.disk.seasonNeighbors(of: q)
        }
        neighbors = known
        estimateDone = true
        RemoteLog.info("skip", "Staffel-Schätzung S\(s)E\(e): \(withIntro(known)) Folgen mit Intro bekannt")
        rebuild()
    }

    /// Stand der Engine übernehmen (Kapitel, Laufzeit, Position). Etwa zweimal je Sekunde.
    func update<E: PlaybackEngine>(engine: E) {
        let marks = engine.chapterMarks, d = engine.duration
        if marks != chapters || abs(d - duration) > 1 { chapters = marks; duration = d; rebuild() }
        // Laufzeit der Datei zu den IntroDB-Marken legen (für die Abspann-Schätzung anderer Folgen).
        if !durationNoted, let q = query, d > 60, !engine.isLoading {
            durationNoted = true
            if Self.disk.noteDuration(d, for: q) { Self.saveDisk() }
        }
        // Ohne Laufzeit (vor dem Laden) oder bei Fehler nie ein Knopf: wie „Engine beschäftigt“ behandeln.
        let pos = engine.currentTime, busy = engine.isLoading || engine.duration <= 0 || engine.errorText != nil
        planner.observe(position: pos, engineSeeking: busy, now: Self.now)
        updateCards(position: pos, busy: busy)
        let context = SkipContext(upNextCard: upNextCard, postPlayCard: isMovie && settings.postPlayCard, duration: duration)
        // The ring stands still while jumps are blocked (panel open, leaving, after background).
        let decision = planner.evaluate(at: pos, engineSeeking: busy, playing: engine.isPlaying && canSkip(), now: Self.now,
                                        settings: settings, context: context)
        if let s = decision.autoSkip {
            RemoteLog.info("skip", "\(s.kind.rawValue) automatisch übersprungen (Countdown abgelaufen)")
            prompt = nil; countdown = nil
            Task { await jump(s, engine: engine) }
            return
        }
        // The card after a movie covers the corner of the button.
        let p = postPlayVisible ? nil : decision.prompt?.segment
        if p != prompt {
            if let p { RemoteLog.info("skip", "Knopf \(p.kind.rawValue) (\(p.source.rawValue)) \(Int(p.start))–\(Int(p.end))s bei \(Int(pos))s\(decision.prompt?.countdown != nil ? " · automatisch in \(Int(SkipPlanner.countdownSeconds)) s" : "")") }
            prompt = p
        }
        let c = p == nil ? nil : decision.prompt?.countdown
        if c != countdown { countdown = c }
    }

    /// Wave P-a: card after a movie and the scene hint, from the end credits (PlayerCore `SkipPolicy`).
    private func updateCards(position pos: Double, busy: Bool) {
        let window = isMovie && settings.postPlayCard ? SkipPolicy.postPlayWindow(segments, duration: duration) : nil
        if let w = window, pos < w.lowerBound - 5 { postPlayClosed = false }   // rewound before the credits
        let card = !busy && !postPlayClosed && (window?.contains(pos) ?? false)
        if card != postPlayVisible {
            RemoteLog.info("skip", card ? "Karte nach dem Film bei \(Int(pos))s" : "Karte nach dem Film weg bei \(Int(pos))s")
            postPlayVisible = card
        }
        let scene = SkipPolicy.sceneAfterCredits(segments, duration: duration)
        if scene != sceneStart { sceneStart = scene }
        let hint = !busy && !card && (SkipPolicy.sceneHintWindow(segments, duration: duration)?.contains(pos) ?? false)
        if hint != sceneHint {
            if hint { RemoteLog.info("skip", "Hinweis: Szene nach dem Abspann ab \(Int(scene ?? 0))s") }
            sceneHint = hint
        }
    }

    /// Wave P-a: any key in the player. Stops a running countdown (the button stays). true = the card is up and
    /// takes the arrow keys (no ±10 s jump behind it).
    @discardableResult
    func noteKey() -> Bool {
        if planner.cancelCountdown() {
            countdown = nil
            RemoteLog.info("skip", "Countdown abgebrochen (Taste), Knopf bleibt")
        }
        return postPlayVisible
    }

    /// Wave P-a: „Abspann weiterschauen“ or Menu on the card.
    func closePostPlay(_ reason: String) {
        guard postPlayVisible else { return }
        postPlayClosed = true
        postPlayVisible = false
        RemoteLog.info("skip", "Karte nach dem Film geschlossen (\(reason))")
    }

    /// Knopf gedrückt: ans Bereichsende springen. Während des Sprungs zeigt der Planer keinen Knopf.
    func skip<E: PlaybackEngine>(engine: E) async {
        guard let s = prompt else { return }
        prompt = nil; countdown = nil
        await jump(s, engine: engine)
    }

    /// Jump over a segment (button or countdown). Credits followed by a scene land at the scene (`SkipPolicy.target`).
    private func jump<E: PlaybackEngine>(_ s: SkipSegment, engine: E) async {
        guard canSkip() else { RemoteLog.info("skip", "\(s.kind.rawValue): Sprung gesperrt"); return }
        let target = planner.beginSkip(s, duration: engine.duration, now: Self.now)
        let scene = s.kind == .credits && sceneStart.map { abs($0 - target) < 1 } == true ? " (Szene nach dem Abspann)" : ""
        RemoteLog.info("skip", "\(s.kind.rawValue) übersprungen \(Int(engine.currentTime)) → \(Int(target))s\(scene)")
        await engine.seek(target, exact: true)
    }

    /// Menü/Zurück bei sichtbarem Knopf: Knopf weg (bis der Bereich verlassen wurde). true = Taste verbraucht.
    /// Wave P-a: the card after a movie closes first („Abspann weiterschauen“).
    func dismissPrompt() -> Bool {
        if postPlayVisible { closePostPlay("Menü"); return true }
        guard let s = prompt else { return false }
        countdown = nil
        planner.dismiss(s)
        prompt = nil
        RemoteLog.info("skip", "Knopf \(s.kind.rawValue) weggeschickt")
        return true
    }

    private func rebuild() {
        // Reihenfolge: Kapitel > IntroDB > Staffel-Schätzung (nur fehlende Arten).
        let have = Set(introDB.map(\.kind))
        let estimate = neighbors.isEmpty ? [] : SeasonSkipEstimate.estimate(from: neighbors, duration: duration)
            .filter { !have.contains($0.kind) }
        let merged = SkipSegments.merge(chapters: SkipSegments.fromChapters(chapters, duration: duration),
                                        introDB: introDB + estimate, duration: duration)
        guard merged != segments else { return }
        segments = merged
        planner.setSegments(merged)
        upNextAt = SkipSegments.upNextTime(merged, duration: duration)
        if !merged.isEmpty {
            RemoteLog.info("skip", "Bereiche: " + merged.map { "\($0.kind.rawValue)/\($0.source.rawValue) \(Int($0.start))–\(Int($0.end))s" }
                .joined(separator: ", ") + (upNextAt.map { " · Up-next ab \(Int($0))s" } ?? ""))
        }
    }

    private static var now: Double { ProcessInfo.processInfo.systemUptime }
}

/// „Intro überspringen“ / „Rückblick überspringen“ unten rechts. Fokussierbar (PlayerControls nimmt sich dafür
/// den Fokus weg, solange der Knopf steht); verschwindet nach dem Bereich.
/// Wave P-a: per type off / button / automatic (`Profile.skip`); "Automatisch" shows a countdown ring, Select jumps at
/// once, any other key stops the countdown. Also hosts the hint „Szene nach dem Abspann“ and the card after a movie.
struct SkipSegmentButton<E: PlaybackEngine>: View {
    @ObservedObject var controller: SkipSegmentController
    let engine: E
    var lookup: (@MainActor () async -> IntroDBQuery?)?
    /// Vor dem Sprung: gesammelten ±10-s-Sprung in PlayerControls verwerfen. false = Sprung gerade gesperrt
    /// (nach dem Hintergrund bis Play), der Knopf tut dann nichts.
    var onBeforeSkip: () -> Bool = { true }
    /// Wave P-a: skip action per segment type.
    var settings = SkipSettings()
    /// Wave P-a: the next-episode card is on for this playback (it covers the credits).
    var upNextCard = false
    /// Wave P-a: the movie for the card after the movie (nil = episode, trailer, own file).
    var postPlayItem: MetaPreview? = nil
    /// Wave P-a: jumps allowed right now, without side effects (see `SkipSegmentController.canSkip`).
    var canSkip: () -> Bool = { true }
    /// Wave P-a: „Zurück“ on the card: leave the player.
    var onLeave: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
            if controller.sceneHint {
                Label("Szene nach dem Abspann", systemImage: "sparkles")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 26).padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.trailing, 80).padding(.top, 80)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
            if let s = controller.prompt, let title = s.buttonTitle {
                Button { guard onBeforeSkip() else { return }; Task { await controller.skip(engine: engine) } } label: {
                    HStack(spacing: 16) {
                        if let left = controller.countdown {
                            SkipCountdownRing(fraction: left / SkipPlanner.countdownSeconds)
                        } else {
                            Image(systemName: "forward.end.fill")
                        }
                        Text(title)
                    }
                    .font(.headline)
                }
                .focused($focused)
                .padding(.trailing, 80).padding(.bottom, 300)
                .transition(.opacity)
                .onAppear { focused = true }
                .task(id: s) {
                    // Fokus sofort und noch einmal eine Runde später (falls der Knopf beim ersten Mal noch nicht im
                    // Fokus-Baum war): die Fläche ist ab jetzt nicht fokussierbar, ohne Knopf-Fokus gingen Befehle verloren.
                    focused = true
                    try? await Task.sleep(for: .milliseconds(50))
                    if !focused { focused = true }
                }
            }
            if controller.postPlayVisible, let item = postPlayItem {
                PostPlayCard(item: item, sceneFollows: controller.sceneStart != nil,
                             onKeepWatching: { controller.closePostPlay("Abspann weiterschauen") },
                             onLeave: onLeave)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: controller.prompt)
        .animation(.easeInOut(duration: 0.3), value: controller.postPlayVisible)
        .animation(.easeInOut(duration: 0.3), value: controller.sceneHint)
        // IntroDB einmal je Wiedergabe; daneben zweimal je Sekunde Kapitel/Position übernehmen.
        .task { await controller.lookup(lookup) }
        .task {
            while !Task.isCancelled {
                controller.settings = settings
                controller.upNextCard = upNextCard
                controller.isMovie = postPlayItem != nil
                controller.canSkip = canSkip
                controller.update(engine: engine)
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}

/// Wave P-a: countdown ring before an automatic jump (full = 5 s left).
private struct SkipCountdownRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.3), lineWidth: 5)
            Circle().trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: fraction)
        }
        .frame(width: 34, height: 34)
    }
}
